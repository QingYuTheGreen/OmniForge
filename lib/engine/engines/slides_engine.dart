import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:xml/xml.dart';

import '../common/package_io.dart';
import '../common/text_format.dart';
import '../engine_utils.dart';
import '../i_engine.dart';

/// 幻灯片引擎：pptx / odp → txt / md / html / pdf。
///
/// 纯 Dart 实现：pptx / odp 都是 ZIP 容器（OOXML / ODF），
/// 不依赖 LibreOffice 等外部程序，因此移动端也能离线转换。
/// 复杂版式（动画、SmartArt、图表、艺术字）只按阅读顺序提取文本与图片。
class SlidesEngine extends SimpleEngine {
  const SlidesEngine();

  @override
  String get id => 'slides';

  @override
  Future<void> execute(EngineContext context) async {
    final source = _detectSource(context);
    final bytes = await readFileBytes(context.inputPath);
    final deck = switch (source) {
      'pptx' => _readPptx(bytes),
      'odp' => _readOdp(bytes),
      _ => throw EngineException('幻灯片引擎不支持输入格式：$source'),
    };
    if (deck.slides.isEmpty) {
      throw const EngineException('幻灯片中没有可读取的页面');
    }
    if (deck.slides.every((slide) => slide.isEmpty)) {
      throw const EngineException('未能从幻灯片中提取到任何文本或图片');
    }

    final target = context.targetFormat.toLowerCase();
    switch (target) {
      case 'txt':
        await _writeTxt(context, deck);
      case 'md' || 'markdown':
        await _writeMarkdown(context, deck);
      case 'html' || 'htm':
        await _writeHtml(context, deck);
      case 'pdf':
        await _writePdf(context, deck);
      default:
        throw EngineException('幻灯片引擎不支持输出格式：$target');
    }
  }

  String _detectSource(EngineContext context) {
    final ext = inputExtension(context);
    if (ext == 'pptx') return 'pptx';
    if (ext == 'odp') return 'odp';
    if (ext == 'ppt') {
      throw const EngineException('不支持旧版二进制 .ppt，请先用 PowerPoint / WPS 另存为 .pptx');
    }
    throw EngineException(
      '幻灯片引擎仅支持 pptx / odp 输入，当前格式：.${ext.isEmpty ? '未知' : ext}',
    );
  }

  // ─────────────────────────── 输出：txt / md / html ───────────────────────────

  Future<void> _writeTxt(EngineContext context, _SlideDeck deck) async {
    final buffer = StringBuffer();
    for (var i = 0; i < deck.slides.length; i++) {
      buffer.writeln('=== 第 ${i + 1} 页 ===');
      final slide = deck.slides[i];
      if (slide.paragraphs.isEmpty) {
        buffer.writeln('（本页无可提取文本）');
      } else {
        for (final paragraph in slide.paragraphs) {
          buffer.writeln(paragraph);
        }
      }
      buffer.writeln();
    }
    await writeFileText(
      context.outputPath,
      '${buffer.toString().trimRight()}\n',
    );
  }

  Future<void> _writeMarkdown(EngineContext context, _SlideDeck deck) async {
    final title = stringParam(context, 'title', inputStem(context));
    final buffer = StringBuffer()
      ..writeln('# $title')
      ..writeln();
    for (var i = 0; i < deck.slides.length; i++) {
      final slide = deck.slides[i];
      buffer
        ..writeln('## 第 ${i + 1} 页')
        ..writeln();
      if (slide.paragraphs.isEmpty) {
        buffer
          ..writeln('_（本页无可提取文本）_')
          ..writeln();
      } else {
        for (final paragraph in slide.paragraphs) {
          buffer
            ..writeln(paragraph)
            ..writeln();
        }
      }
      for (final image in slide.images) {
        buffer
          ..writeln('![](${image.name})')
          ..writeln();
      }
    }
    await writeFileText(
      context.outputPath,
      '${buffer.toString().trimRight()}\n',
    );
  }

  Future<void> _writeHtml(EngineContext context, _SlideDeck deck) async {
    final title = stringParam(context, 'title', inputStem(context));
    final buffer = StringBuffer()
      ..writeln('<!DOCTYPE html>')
      ..writeln('<html lang="zh-CN">')
      ..writeln('<head>')
      ..writeln('<meta charset="utf-8"/>')
      ..writeln(
        '<meta name="viewport" content="width=device-width, initial-scale=1"/>',
      )
      ..writeln('<title>${escapeHtml(title)}</title>')
      ..writeln('<style>')
      ..writeln(
        'body { font-family: system-ui, -apple-system, "Segoe UI", '
        '"Noto Sans SC", sans-serif; line-height: 1.7; max-width: 960px; '
        'margin: 2rem auto; padding: 0 1.2rem; color: #1f1f1f; }',
      )
      ..writeln(
        'section.slide { border: 1px solid #e3e3e3; border-radius: 12px; '
        'padding: 1.2rem 1.5rem; margin: 0 0 1.5rem; background: #fff; }',
      )
      ..writeln('section.slide h2 { margin: 0 0 1rem; font-size: 1.25rem; }')
      ..writeln('p { margin: 0 0 .7rem; white-space: pre-wrap; }')
      ..writeln('figure { margin: 1rem 0; text-align: center; }')
      ..writeln('img { max-width: 100%; height: auto; }')
      ..writeln('figcaption { color: #777; font-size: .85rem; }')
      ..writeln('</style>')
      ..writeln('</head>')
      ..writeln('<body>');
    for (var i = 0; i < deck.slides.length; i++) {
      final slide = deck.slides[i];
      buffer
        ..writeln('<section class="slide" id="slide-${i + 1}">')
        ..writeln('<h2>第 ${i + 1} 页</h2>');
      if (slide.paragraphs.isEmpty) {
        buffer.writeln('<p><em>（本页无可提取文本）</em></p>');
      } else {
        for (final paragraph in slide.paragraphs) {
          buffer.writeln(
            '<p>${escapeHtml(paragraph).replaceAll('\n', '<br/>')}</p>',
          );
        }
      }
      for (final image in slide.images) {
        buffer
          ..writeln('<figure>')
          ..writeln(
            '<img src="data:${_mediaMime(image.name)};base64,'
            '${base64Encode(image.bytes)}" alt="${escapeHtml(image.name)}"/>',
          )
          ..writeln('<figcaption>${escapeHtml(image.name)}</figcaption>')
          ..writeln('</figure>');
      }
      buffer.writeln('</section>');
    }
    buffer
      ..writeln('</body>')
      ..writeln('</html>');
    await writeFileText(context.outputPath, buffer.toString());
  }

  String _mediaMime(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.bmp')) return 'image/bmp';
    if (lower.endsWith('.svg')) return 'image/svg+xml';
    return 'image/png';
  }

  // ─────────────────────────── 输出：pdf ───────────────────────────

  Future<void> _writePdf(EngineContext context, _SlideDeck deck) async {
    final allText = deck.slides
        .expand((slide) => slide.paragraphs)
        .join('\n');
    final font = _resolveFont(
      stringParam(context, 'font_path', ''),
      allText,
    );
    final theme = font == null ? null : pw.ThemeData.withFont(base: font);
    final format = _pageFormat(context);
    final margin = doubleParam(context, 'margin', 36);
    final document = pw.Document();
    for (var i = 0; i < deck.slides.length; i++) {
      final slide = deck.slides[i];
      final paragraphs = slide.paragraphs.isEmpty
          ? const ['（本页无可提取文本）']
          : slide.paragraphs;
      document.addPage(
        pw.MultiPage(
          pageFormat: format,
          margin: pw.EdgeInsets.all(margin),
          theme: theme,
          build: (pw.Context pdfContext) => [
            pw.Paragraph(
              text: '第 ${i + 1} 页',
              style: const pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
                lineSpacing: 4,
              ),
            ),
            pw.SizedBox(height: 10),
            for (final paragraph in paragraphs)
              pw.Paragraph(
                text: paragraph,
                style: const pw.TextStyle(fontSize: 12, lineSpacing: 4),
              ),
          ],
        ),
      );
    }
    await writeFileBytes(context.outputPath, await document.save());
  }

  PdfPageFormat _pageFormat(EngineContext context) {
    final value = stringParam(context, 'page_size', 'a4').toLowerCase();
    final landscape = value.contains('land') ||
        value.contains('wide') ||
        value == 'a4l' ||
        value == '16:9';
    return landscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;
  }

  /// 中文字体候选路径（不含 TTC，pdf 包暂不支持字体集合）。
  static const List<String> _cjkFontCandidates = [
    // Android / HarmonyOS
    '/system/fonts/NotoSansSC-Regular.otf',
    '/system/fonts/NotoSansCJK-Regular.ttf',
    '/system/fonts/NotoSansHans-Regular.otf',
    '/system/fonts/DroidSansFallback.ttf',
    '/system/fonts/DroidSansFallbackFull.ttf',
    // Windows
    r'C:\Windows\Fonts\msyh.ttf',
    r'C:\Windows\Fonts\simhei.ttf',
    // macOS
    '/System/Library/Fonts/Supplemental/Songti.ttc',
    '/System/Library/Fonts/PingFang.ttc',
    // Linux
    '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttf',
    '/usr/share/fonts/opentype/noto/NotoSansCJKsc-Regular.otf',
    '/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttf',
    '/usr/share/fonts/truetype/wqy/wqy-microhei.ttf',
    '/usr/share/fonts/truetype/wqy/wqy-zenhei.ttf',
  ];

  /// 返回可嵌入的中文字体；无中文且找不到字体时回退 Helvetica。
  ///
  /// 含中文却找不到可嵌入字体时抛出 [EngineException]，避免输出豆腐块 PDF。
  pw.Font? _resolveFont(String explicitPath, String text) {
    final hasCjk =
        RegExp(r'[\u3400-\u9fff\u3040-\u30ff\uac00-\ud7af]').hasMatch(text);
    final explicit = explicitPath.trim();
    if (explicit.isNotEmpty) {
      final font = _loadFont(explicit);
      if (font != null) return font;
    }
    if (!hasCjk) return null;
    for (final path in _cjkFontCandidates) {
      final font = _loadFont(path);
      if (font != null) return font;
    }
    throw const EngineException(
      '幻灯片转 PDF 需要可嵌入的中文字体，但当前系统未找到中文字体。'
      '英文内容可直接转 PDF；如需中文 PDF，请先安装 Noto Sans CJK / 思源黑体等字体。',
    );
  }

  pw.Font? _loadFont(String path) {
    try {
      final file = File(path);
      if (!file.existsSync()) return null;
      final data = file.readAsBytesSync();
      if (data.length < 4) return null;
      // 字体集合（TTC）暂不支持
      if (String.fromCharCodes(data.sublist(0, 4)) == 'ttcf') return null;
      return pw.Font.ttf(ByteData.sublistView(Uint8List.fromList(data)));
    } catch (_) {
      return null;
    }
  }

  // ─────────────────────────── pptx 读取 ───────────────────────────

  _SlideDeck _readPptx(Uint8List bytes) {
    final package = ZipPackage.decode(bytes);
    final presentationXml = package.textOf('ppt/presentation.xml');
    if (presentationXml == null) {
      throw const EngineException('pptx 中缺少 ppt/presentation.xml，文件可能已损坏');
    }
    final relationships = _parseRelationships(
      package.textOf('ppt/_rels/presentation.xml.rels'),
      'ppt',
    );
    final byId = <String, _Relationship>{
      for (final relationship in relationships) relationship.id: relationship,
    };
    final slidePaths = <String>[];
    final document = XmlDocument.parse(presentationXml);
    for (final sldId in document.descendantElements
        .where((element) => element.localName == 'sldId')) {
      final rid = _relationshipId(sldId);
      final relationship = rid == null ? null : byId[rid];
      if (relationship != null && package.contains(relationship.target)) {
        slidePaths.add(relationship.target);
      }
    }
    if (slidePaths.isEmpty) {
      // 缺少 sldIdLst 时按 slideN.xml 编号兜底排序
      final pattern = RegExp(r'^ppt/slides/slide(\d+)\.xml$');
      final fallback = package.names
          .where((name) => pattern.hasMatch(name))
          .toList()
        ..sort((a, b) {
          final left = int.tryParse(pattern.firstMatch(a)?.group(1) ?? '') ?? 0;
          final right = int.tryParse(pattern.firstMatch(b)?.group(1) ?? '') ?? 0;
          return left.compareTo(right);
        });
      slidePaths.addAll(fallback);
    }
    if (slidePaths.isEmpty) {
      throw const EngineException('pptx 中未找到任何幻灯片');
    }
    return _SlideDeck([
      for (final path in slidePaths) _readPptxSlide(package, path),
    ]);
  }

  _Slide _readPptxSlide(ZipPackage package, String path) {
    final xml = package.textOf(path);
    if (xml == null) return const _Slide([], []);
    final document = XmlDocument.parse(xml);
    final paragraphs = <String>[];
    for (final paragraph in document.descendantElements
        .where((element) => _isPrefixed(element, 'a', 'p'))) {
      final text = _drawingParagraphText(paragraph);
      if (text.isNotEmpty) paragraphs.add(text);
    }
    final images = <_SlideImage>[];
    final seen = <String>{};
    final directory = _directoryOf(path);
    final relsPath = '$directory/_rels/${_baseName(path)}.rels';
    for (final relationship
        in _parseRelationships(package.textOf(relsPath), directory)) {
      if (!relationship.type.toLowerCase().endsWith('/image')) continue;
      if (!seen.add(relationship.target)) continue;
      final data = package.bytesOf(relationship.target);
      if (data == null) continue;
      images.add(
        _SlideImage('media/${_baseName(relationship.target)}', data),
      );
    }
    return _Slide(paragraphs, images);
  }

  String _drawingParagraphText(XmlElement paragraph) {
    final buffer = StringBuffer();
    void walk(XmlElement element) {
      for (final node in element.children) {
        if (node is XmlText) {
          buffer.write(node.value);
        } else if (node is XmlElement) {
          if (node.localName == 't') {
            buffer.write(node.innerText);
          } else if (node.localName == 'br' ||
              node.localName == 'line-break') {
            buffer.write('\n');
          } else if (node.localName == 'tab') {
            buffer.write('\t');
          } else {
            walk(node);
          }
        }
      }
    }

    walk(paragraph);
    return buffer.toString().trim();
  }

  // ─────────────────────────── odp 读取 ───────────────────────────

  _SlideDeck _readOdp(Uint8List bytes) {
    final package = ZipPackage.decode(bytes);
    final contentXml = package.textOf('content.xml');
    if (contentXml == null) {
      throw const EngineException('odp 中缺少 content.xml，文件可能已损坏');
    }
    final document = XmlDocument.parse(contentXml);
    final slides = <_Slide>[];
    for (final page in document.descendantElements
        .where((element) => _isPrefixed(element, 'draw', 'page'))) {
      final paragraphs = <String>[];
      for (final paragraph in page.descendantElements.where(
        (element) =>
            _isPrefixed(element, 'text', 'p') ||
            _isPrefixed(element, 'text', 'h'),
      )) {
        if (_hasParagraphAncestor(paragraph)) continue;
        final text = _odfParagraphText(paragraph).trim();
        if (text.isNotEmpty) paragraphs.add(text);
      }
      final images = <_SlideImage>[];
      final seen = <String>{};
      for (final image in page.descendantElements
          .where((element) => _isPrefixed(element, 'draw', 'image'))) {
        final href = _xlinkHref(image);
        if (href == null || href.isEmpty) continue;
        final path = _resolvePath('', href);
        if (!seen.add(path)) continue;
        final data = package.bytesOf(path);
        if (data == null) continue;
        images.add(_SlideImage(path, data));
      }
      slides.add(_Slide(paragraphs, images));
    }
    if (slides.isEmpty) {
      throw const EngineException('odp 中未找到任何幻灯片页面');
    }
    return _SlideDeck(slides);
  }

  String? _xlinkHref(XmlElement element) {
    for (final attribute in element.attributes) {
      if (attribute.name.local == 'href') return attribute.value;
    }
    return null;
  }

  bool _hasParagraphAncestor(XmlElement element) {
    var parent = element.parentElement;
    while (parent != null) {
      if (_isPrefixed(parent, 'text', 'p') ||
          _isPrefixed(parent, 'text', 'h')) {
        return true;
      }
      parent = parent.parentElement;
    }
    return false;
  }

  String _odfParagraphText(XmlElement paragraph) {
    final buffer = StringBuffer();
    void walk(XmlNode node) {
      for (final child in node.children) {
        if (child is XmlText) {
          buffer.write(child.value);
        } else if (child is XmlElement) {
          if (child.localName == 's') {
            final count = int.tryParse(
                  _attribute(child, 'c') ?? '',
                ) ??
                1;
            buffer.write(' ' * count.clamp(1, 64));
          } else if (child.localName == 'tab') {
            buffer.write('\t');
          } else if (child.localName == 'line-break') {
            buffer.write('\n');
          } else if (_isPrefixed(child, 'text', 'p') ||
              _isPrefixed(child, 'text', 'h')) {
            // 嵌套段落由外层段落统一处理，避免内容重复
            continue;
          } else {
            walk(child);
          }
        }
      }
    }

    walk(paragraph);
    return buffer.toString();
  }

  // ─────────────────────────── XML / 路径工具 ───────────────────────────

  bool _isPrefixed(XmlElement element, String prefix, String localName) {
    if (element.localName != localName) return false;
    final actualPrefix = element.name.prefix;
    return actualPrefix == null ||
        actualPrefix.isEmpty ||
        actualPrefix == prefix;
  }

  String? _relationshipId(XmlElement element) {
    for (final attribute in element.attributes) {
      if (attribute.name.local == 'id' && attribute.name.prefix == 'r') {
        return attribute.value;
      }
    }
    return null;
  }

  String? _attribute(XmlElement element, String localName) {
    for (final attribute in element.attributes) {
      if (attribute.name.local == localName) return attribute.value;
    }
    return null;
  }

  List<_Relationship> _parseRelationships(String? xmlText, String baseDir) {
    final relationships = <_Relationship>[];
    if (xmlText == null) return relationships;
    final document = XmlDocument.parse(xmlText);
    for (final element in document.descendantElements
        .where((element) => element.localName == 'Relationship')) {
      final id = element.getAttribute('Id');
      final target = element.getAttribute('Target');
      if (id == null || target == null) continue;
      relationships.add(
        _Relationship(
          id,
          element.getAttribute('Type') ?? '',
          _resolvePath(baseDir, target),
        ),
      );
    }
    return relationships;
  }

  String _directoryOf(String path) {
    final index = path.lastIndexOf('/');
    return index < 0 ? '' : path.substring(0, index);
  }

  String _baseName(String path) {
    final index = path.lastIndexOf('/');
    return index < 0 ? path : path.substring(index + 1);
  }

  /// 解析 ZIP 内相对路径（处理 `..` / `.` / 前导 `/`）。
  String _resolvePath(String baseDir, String target) {
    final segments = <String>[
      for (final part in baseDir.split('/'))
        if (part.isNotEmpty) part,
    ];
    if (target.startsWith('/')) segments.clear();
    for (final part in target.split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (segments.isNotEmpty) segments.removeLast();
      } else {
        segments.add(part);
      }
    }
    return segments.join('/');
  }
}

// ─────────────────────────── 数据模型 ───────────────────────────

class _SlideImage {
  const _SlideImage(this.name, this.bytes);

  /// 包内引用名（pptx 为 media/xxx，odp 为 Pictures/xxx）。
  final String name;
  final Uint8List bytes;
}

class _Slide {
  const _Slide(this.paragraphs, this.images);

  final List<String> paragraphs;
  final List<_SlideImage> images;

  bool get isEmpty => paragraphs.isEmpty && images.isEmpty;
}

class _SlideDeck {
  const _SlideDeck(this.slides);

  final List<_Slide> slides;
}

class _Relationship {
  const _Relationship(this.id, this.type, this.target);

  final String id;
  final String type;
  final String target;
}
