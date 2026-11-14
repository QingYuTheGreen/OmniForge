import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../engine_utils.dart';
import '../i_engine.dart';
import '../common/package_io.dart';
import '../common/text_format.dart';

/// 文档引擎：docx / rtf / txt / md / html 互转。
///
/// docx / rtf 为纯 Dart 实现（OOXML 段落读写、基础 RTF 解析），
/// 不依赖任何外部程序，因此移动端也能用。
class DocumentEngine extends SimpleEngine {
  const DocumentEngine();

  @override
  String get id => 'document';

  @override
  Future<void> execute(EngineContext context) async {
    final source = _detectSource(context);
    final document = switch (source) {
      'docx' => _readDocx(await readFileBytes(context.inputPath)),
      'rtf' => _readRtf(
          utf8.decode(await readFileBytes(context.inputPath),
              allowMalformed: true),
        ),
      'html' => _readHtml(
          utf8.decode(await readFileBytes(context.inputPath),
              allowMalformed: true),
        ),
      _ => _readPlainText(
          utf8.decode(await readFileBytes(context.inputPath),
              allowMalformed: true),
          source,
        ),
    };

    if (document.isEmpty) {
      throw const EngineException('文档内容为空或无法解析');
    }

    final target = context.targetFormat.toLowerCase();
    switch (target) {
      case 'docx':
        await writeFileBytes(
          context.outputPath,
          _writeDocx(document, inputStem(context)),
        );
      case 'rtf':
        await writeFileText(context.outputPath, _writeRtf(document));
      case 'txt':
        await writeFileText(context.outputPath, document.plainText);
      case 'md' || 'markdown':
        await writeFileText(context.outputPath, _writeMarkdown(document));
      case 'html' || 'htm':
        await writeFileText(
          context.outputPath,
          textToHtml(document.plainText, title: inputStem(context)),
        );
      default:
        throw EngineException('文档引擎不支持输出格式：$target');
    }
  }

  String _detectSource(EngineContext context) {
    final ext = inputExtension(context);
    if (ext == 'docx' || ext == 'doc') return 'docx';
    if (ext == 'rtf') return 'rtf';
    if (ext == 'html' || ext == 'htm') return 'html';
    if (ext == 'md' || ext == 'markdown') return 'md';
    return 'txt';
  }

  // ─────────────────────────── 读取 ───────────────────────────

  _Document _readDocx(Uint8List bytes) {
    final documentXml = ZipPackage.decode(bytes).textOf('word/document.xml');
    if (documentXml == null) {
      throw const EngineException('docx 中缺少 word/document.xml');
    }
    final xml = XmlDocument.parse(documentXml);
    final paragraphs = <_Paragraph>[];
    final body = xml.descendantElements.firstWhere(
      (e) => e.localName == 'body',
      orElse: () => xml.rootElement,
    );
    for (final child in body.childElements) {
      if (child.localName == 'p') {
        final text = child.descendantElements
            .where((e) => e.localName == 't')
            .map((e) => e.innerText)
            .join();
        if (text.trim().isEmpty) continue;
        final style = child.descendantElements
            .where((e) => e.localName == 'pStyle')
            .map((e) => e.getAttribute('w:val') ?? '')
            .join();
        paragraphs.add(_Paragraph(text.trim(), heading: _headingLevel(style)));
      } else if (child.localName == 'tbl') {
        for (final row in child.descendantElements
            .where((e) => e.localName == 'tr')) {
          final cells = row.childElements
              .where((e) => e.localName == 'tc')
              .map((cell) => cell.descendantElements
                  .where((e) => e.localName == 't')
                  .map((e) => e.innerText)
                  .join()
                  .trim())
              .where((value) => value.isNotEmpty)
              .toList();
          if (cells.isNotEmpty) {
            paragraphs.add(_Paragraph(cells.join(' | ')));
          }
        }
      }
    }
    return _Document(paragraphs);
  }

  int _headingLevel(String style) {
    final lower = style.toLowerCase();
    if (lower.contains('title')) return 1;
    final match = RegExp(r'heading\s*(\d)').firstMatch(lower);
    if (match != null) return int.parse(match.group(1)!);
    return 0;
  }

  _Document _readRtf(String rtf) {
    final buffer = StringBuffer();
    var index = 0;
    var skipGroup = false;
    var depth = 0;
    var pendingSkipDepth = -1;
    while (index < rtf.length) {
      final char = rtf[index];
      if (char == '{') {
        depth++;
        if (pendingSkipDepth < 0 && rtf.startsWith(r'{\*', index)) {
          pendingSkipDepth = depth;
        }
        index++;
        continue;
      }
      if (char == '}') {
        if (pendingSkipDepth == depth) pendingSkipDepth = -1;
        depth--;
        skipGroup = false;
        index++;
        continue;
      }
      if (char != r'\\') {
        if (pendingSkipDepth < 0 && !skipGroup) buffer.write(char);
        index++;
        continue;
      }
      index++;
      if (index >= rtf.length) break;
      final next = rtf[index];
      if (next == r'\\' || next == '{' || next == '}') {
        if (pendingSkipDepth < 0) buffer.write(next);
        index++;
        continue;
      }
      if (next == "'") {
        if (index + 2 < rtf.length) {
          final hex = rtf.substring(index + 1, index + 3);
          final code = int.tryParse(hex, radix: 16);
          if (code != null && pendingSkipDepth < 0) {
            buffer.write(String.fromCharCode(code));
          }
          index += 3;
          continue;
        }
        index++;
        continue;
      }
      final wordMatch = RegExp(r'[a-zA-Z]+(-?\d+)?[ ]?').matchAsPrefix(rtf, index);
      if (wordMatch == null) {
        index++;
        continue;
      }
      final word = wordMatch.group(1) ?? '';
      final parameter = wordMatch.group(2);
      index = wordMatch.end;
      if (pendingSkipDepth >= 0) continue;
      switch (word) {
        case 'par':
        case 'line':
        case 'sect':
          buffer.writeln();
        case 'tab':
          buffer.write('\t');
      }
      if (parameter == null && word == 'u' && index < rtf.length) {
        // \uN 后紧跟替代字符，跳过
        if (index + 1 < rtf.length) index++;
      }
    }
    final lines = buffer
        .toString()
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    return _Document([
      for (final line in lines) _Paragraph(line),
    ]);
  }

  _Document _readHtml(String html) {
    final plain = stripHtml(html);
    final blocks = splitParagraphs(plain);
    return _Document([
      for (final block in blocks) _Paragraph(block),
    ]);
  }

  _Document _readPlainText(String text, String source) {
    final normalized = text.replaceAll('\r\n', '\n');
    final blocks = splitParagraphs(normalized);
    if (blocks.isEmpty && normalized.trim().isNotEmpty) {
      return _Document([_Paragraph(normalized.trim())]);
    }
    return _Document([
      for (final block in blocks) _Paragraph(block),
    ]);
  }

  // ─────────────────────────── 输出 ───────────────────────────

  String _writeRtf(_Document document) {
    final buffer = StringBuffer(
      r'{\rtf1\ansi\ansicpg65001\deff0{\fonttbl{\f0\fnil Noto Sans SC;}}'
      r'\viewkind4\uc1\pard\f0\fs24 ',
    );
    for (final paragraph in document.paragraphs) {
      if (paragraph.heading > 0) {
        buffer.write(r'\b ');
      }
      for (final char in paragraph.text.split('')) {
        final code = char.codeUnitAt(0);
        if (char == r'\\' || char == '{' || char == '}') {
          buffer.write('\\$char');
        } else if (char == '\n') {
          buffer.write(r'\line ');
        } else if (code < 128) {
          buffer.write(char);
        } else {
          buffer.write('\\u${code.toSigned(16)}?');
        }
      }
      if (paragraph.heading > 0) buffer.write(r'\b0 ');
      buffer.write(r'\par ');
    }
    buffer.write('}');
    return buffer.toString();
  }

  String _writeMarkdown(_Document document) {
    final buffer = StringBuffer();
    for (final paragraph in document.paragraphs) {
      if (paragraph.heading > 0) {
        buffer.writeln('${'#' * paragraph.heading} ${paragraph.text}');
      } else {
        buffer.writeln(paragraph.text);
      }
      buffer.writeln();
    }
    return buffer.toString().trimRight() + '\n';
  }

  Uint8List _writeDocx(_Document document, String title) {
    final body = StringBuffer();
    for (final paragraph in document.paragraphs) {
      final styleXml = paragraph.heading > 0
          ? '<w:pPr><w:pStyle w:val="Heading${paragraph.heading}"/></w:pPr>'
          : '';
      final runs = paragraph.text.split('\n').map((line) {
        return '<w:r><w:t xml:space="preserve">${escapeXml(line)}</w:t></w:r>';
      }).join();
      body.write('<w:p>$styleXml$runs</w:p>');
    }

    final documentXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document '
        'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:body>$body'
        '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
        '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/>'
        '</w:sectPr></w:body></w:document>';

    final stylesXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:styles '
        'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '${[1, 2, 3, 4, 5, 6].map((level) => '<w:style w:type="paragraph" w:styleId="Heading$level"><w:name w:val="heading $level"/><w:pPr><w:outlineLvl w:val="${level - 1}"/></w:pPr><w:rPr><w:b/><w:sz w:val="${28 - level * 2}"/></w:rPr></w:style>').join()}'
        '</w:styles>';

    final archive = Archive()
      ..add(ArchiveFile(
        '[Content_Types].xml',
        0,
        utf8.encode(
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
          '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
          '<Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
          '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
          '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
          '</Types>',
        ),
      ))
      ..add(ArchiveFile(
        '_rels/.rels',
        0,
        utf8.encode(
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
          '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
          '</Relationships>',
        ),
      ))
      ..add(ArchiveFile(
        'word/_rels/document.xml.rels',
        0,
        utf8.encode(
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
          '</Relationships>',
        ),
      ))
      ..add(ArchiveFile('word/document.xml', 0, utf8.encode(documentXml)))
      ..add(ArchiveFile('word/styles.xml', 0, utf8.encode(stylesXml)))
      ..add(ArchiveFile(
        'docProps/core.xml',
        0,
        utf8.encode(
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<cp:coreProperties '
          'xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
          'xmlns:dc="http://purl.org/dc/elements/1.1/">'
          '<dc:title>${escapeXml(title)}</dc:title>'
          '<dc:creator>OmniForge</dc:creator>'
          '</cp:coreProperties>',
        ),
      ));
    return ZipEncoder().encodeBytes(archive);
  }
}

class _Paragraph {
  final String text;
  final int heading;

  const _Paragraph(this.text, {this.heading = 0});
}

class _Document {
  final List<_Paragraph> paragraphs;

  const _Document(this.paragraphs);

  bool get isEmpty => paragraphs.isEmpty;

  String get plainText =>
      paragraphs.map((p) => p.text).join('\n\n').trim();
}
