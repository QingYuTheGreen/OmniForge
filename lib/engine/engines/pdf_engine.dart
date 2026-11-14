import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../engine_utils.dart';
import '../i_engine.dart';
import '../common/text_format.dart';

/// PDF 引擎：
/// - 图片 → PDF（真实嵌入，纯 Dart）
/// - 文本 / Markdown / HTML → PDF（自动寻找系统字体，找到中文字体即可排版）
/// - PDF → 文本（解压内容流、提取文本操作符）
class PdfEngine extends SimpleEngine {
  const PdfEngine();

  @override
  String get id => 'pdf';

  @override
  Future<void> execute(EngineContext context) async {
    final target = context.targetFormat.toLowerCase();
    final source = inputExtension(context);
    if (target == 'pdf') {
      if (_isImage(source)) {
        await _imageToPdf(context);
      } else {
        await _textToPdf(context);
      }
      return;
    }
    if (target == 'txt') {
      await _pdfToText(context);
      return;
    }
    throw EngineException('PDF 引擎不支持输出格式：$target');
  }

  bool _isImage(String ext) =>
      const {'jpg', 'jpeg', 'png', 'bmp', 'webp', 'tif', 'tiff', 'tga', 'ico', 'gif'}
          .contains(ext);

  // ─────────────────────────── 图片 → PDF ───────────────────────────

  Future<void> _imageToPdf(EngineContext context) async {
    final bytes = await readFileBytes(context.inputPath);
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const EngineException('无法解码图片，无法生成 PDF');
    }
    final document = pw.Document();
    final image = pw.MemoryImage(
      Uint8List.fromList(img.encodePng(decoded)),
    );
    final landscape = decoded.width > decoded.height;
    final format = landscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;
    final margin = doubleParam(context, 'margin', 18);
    document.addPage(
      pw.Page(
        pageFormat: format,
        margin: pw.EdgeInsets.all(margin),
        build: (context) => pw.Center(
          child: pw.Image(image, fit: pw.BoxFit.contain),
        ),
      ),
    );
    await writeFileBytes(context.outputPath, await document.save());
  }

  // ─────────────────────────── 文本 → PDF ───────────────────────────

  Future<void> _textToPdf(EngineContext context) async {
    final source = inputExtension(context);
    var text = utf8.decode(
      await readFileBytes(context.inputPath),
      allowMalformed: true,
    );
    if (source == 'md' || source == 'markdown') {
      text = stripHtml(text);
    } else if (source == 'html' || source == 'htm') {
      text = stripHtml(text);
    }
    if (text.trim().isEmpty) {
      throw const EngineException('文本为空，无法生成 PDF');
    }
    final font = _resolveFont(text);
    final paragraphs = splitParagraphs(text);
    final document = pw.Document();
    final margin = doubleParam(context, 'margin', 36);
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.all(margin),
        theme: font == null ? null : pw.ThemeData.withFont(base: font),
        build: (context) => [
          for (final paragraph in paragraphs)
            pw.Paragraph(
              text: paragraph,
              style: const pw.TextStyle(fontSize: 12, lineSpacing: 3),
            ),
        ],
      ),
    );
    await writeFileBytes(context.outputPath, await document.save());
  }

  /// 找一款能覆盖输入文本的系统字体；找不到时回退 Helvetica（仅拉丁字符安全）。
  pw.Font? _resolveFont(String text) {
    final hasCjk = RegExp(r'[\u3400-\u9fff\u3040-\u30ff\uac00-\ud7af]')
        .hasMatch(text);
    final candidates = <String>[
      // Android / HarmonyOS
      '/system/fonts/NotoSansSC-Regular.otf',
      '/system/fonts/NotoSansCJK-Regular.ttf',
      '/system/fonts/NotoSansHans-Regular.otf',
      '/system/fonts/DroidSansFallback.ttf',
      '/system/fonts/DroidSansFallbackFull.ttf',
      // Windows
      r'C:\Windows\Fonts\msyh.ttf',
      r'C:\Windows\Fonts\simhei.ttf',
      r'C:\Windows\Fonts\simsun.ttc',
      // macOS
      '/System/Library/Fonts/Supplemental/Songti.ttc',
      '/System/Library/Fonts/PingFang.ttc',
      // Linux
      '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttf',
      '/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttf',
      '/usr/share/fonts/truetype/wqy/wqy-microhei.ttc',
      '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    ];
    for (final path in candidates) {
      if (!File(path).existsSync()) continue;
      try {
        final data = File(path).readAsBytesSync();
        if (data.length < 4) continue;
        // TTC 字体集合暂不支持，跳过
        if (String.fromCharCodes(data.sublist(0, 4)) == 'ttcf') continue;
        return pw.Font.ttf(ByteData.sublistView(data));
      } catch (_) {
        // 该字体不可用，尝试下一个
      }
    }
    if (hasCjk) {
      throw const EngineException(
        '未找到可嵌入 PDF 的中文字体。图片、英文文本可直接转 PDF；'
        '中文文本转 PDF 需要字体插件（后续版本提供）。',
      );
    }
    return null;
  }

  // ─────────────────────────── PDF → 文本 ───────────────────────────

  Future<void> _pdfToText(EngineContext context) async {
    final bytes = await readFileBytes(context.inputPath);
    final latin = latin1.decode(bytes, allowInvalid: true);
    if (!latin.contains('%PDF')) {
      throw const EngineException('不是有效的 PDF 文件');
    }
    final buffer = StringBuffer();
    var index = 0;
    while (true) {
      final streamIndex = latin.indexOf('stream', index);
      if (streamIndex < 0) break;
      var start = streamIndex + 6;
      if (start < latin.length && latin[start] == '\r') start++;
      if (start < latin.length && latin[start] == '\n') start++;
      final end = latin.indexOf('endstream', start);
      if (end < 0) break;
      final raw = bytes.sublist(start, end.clamp(start, bytes.length));
      var content = _tryInflate(raw);
      if (content == null) content = raw;
      buffer.write(_extractTextFromContent(latin1.decode(content, allowInvalid: true)));
      buffer.write('\n');
      index = end + 9;
    }
    final text = buffer.toString().replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    if (text.isEmpty) {
      throw const EngineException(
        '未能从 PDF 中提取文字（可能是扫描件或加密文档）',
      );
    }
    await writeFileText(context.outputPath, text);
  }

  List<int>? _tryInflate(List<int> data) {
    try {
      return ZLibDecoder().decodeBytes(data);
    } catch (_) {
      return null;
    }
  }

  String _extractTextFromContent(String content) {
    final buffer = StringBuffer();
    final token = RegExp(
      r'\((?:[^()\\]|\\.)*\)\s*Tj|\[(?:[^\[\]]*)\]\s*TJ|T\*|Td|TD|ET',
    );
    for (final match in token.allMatches(content)) {
      final raw = match.group(0)!;
      if (raw == 'T*' || raw == 'Td' || raw == 'TD' || raw == 'ET') {
        if (buffer.isNotEmpty && !buffer.toString().endsWith('\n')) {
          buffer.write('\n');
        }
        continue;
      }
      if (raw.endsWith('Tj')) {
        final text = raw.substring(0, raw.lastIndexOf(')') + 1);
        buffer.write(_decodePdfString(text.substring(1, text.length - 1)));
      } else {
        final arrayOpen = raw.indexOf('[');
        final arrayClose = raw.lastIndexOf(']');
        if (arrayOpen < 0 || arrayClose < 0) continue;
        final inner = raw.substring(arrayOpen + 1, arrayClose);
        for (final part in RegExp(r'\((?:\\.|[^()\\])*\)').allMatches(inner)) {
          final value = part.group(0)!;
          buffer.write(_decodePdfString(value.substring(1, value.length - 1)));
        }
      }
    }
    return buffer.toString();
  }

  String _decodePdfString(String raw) {
    final buffer = StringBuffer();
    for (var i = 0; i < raw.length; i++) {
      final char = raw[i];
      if (char != r'\\') {
        buffer.write(char);
        continue;
      }
      i++;
      if (i >= raw.length) break;
      switch (raw[i]) {
        case 'n':
          buffer.write('\n');
        case 'r':
          buffer.write('\r');
        case 't':
          buffer.write('\t');
        case 'b':
          buffer.write('\b');
        case 'f':
          buffer.write('\f');
        case '(':
        case ')':
        case r'\\':
          buffer.write(raw[i]);
        default:
          final octal = RegExp(r'[0-7]{1,3}').matchAsPrefix(raw, i);
          if (octal != null) {
            buffer.write(String.fromCharCode(
              int.parse(octal.group(0)!, radix: 8),
            ));
            i += octal.group(0)!.length - 1;
          } else {
            buffer.write(raw[i]);
          }
      }
    }
    return buffer.toString();
  }
}
