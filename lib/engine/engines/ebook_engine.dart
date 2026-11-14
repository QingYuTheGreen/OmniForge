import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../engine_utils.dart';
import '../i_engine.dart';
import '../common/package_io.dart';
import '../common/text_format.dart';

/// 电子书引擎：epub 读写，epub ↔ txt / md / html。
///
/// 纯 Dart 实现：epub 本质是 zip + xhtml，不依赖外部程序。
class EbookEngine extends SimpleEngine {
  const EbookEngine();

  @override
  String get id => 'ebook';

  @override
  Future<void> execute(EngineContext context) async {
    final source = _detectSource(context);
    final title = stringParam(context, 'title', inputStem(context));
    final author = stringParam(context, 'author', 'OmniForge');
    final target = context.targetFormat.toLowerCase();

    if (source == 'epub') {
      final book = _readEpub(await readFileBytes(context.inputPath));
      switch (target) {
        case 'txt':
          await writeFileText(context.outputPath, book.plainText);
        case 'md' || 'markdown':
          await writeFileText(context.outputPath, _toMarkdown(book));
        case 'html' || 'htm':
          await writeFileText(
            context.outputPath,
            textToHtml(book.plainText, title: book.title),
          );
        case 'epub':
          await writeFileBytes(
            context.outputPath,
            _writeEpub(book.title.isEmpty ? title : book.title, author,
                book.chapters),
          );
        default:
          throw EngineException('电子书引擎不支持输出格式：$target');
      }
      return;
    }

    if (target != 'epub') {
      throw EngineException('电子书引擎不支持 $source → $target');
    }
    final text = await _readTextSource(context, source);
    final chapters = splitParagraphs(text);
    if (chapters.isEmpty) {
      throw const EngineException('输入文本为空，无法生成电子书');
    }
    await writeFileBytes(
      context.outputPath,
      _writeEpub(title, author, chapters),
    );
  }

  String _detectSource(EngineContext context) {
    final ext = inputExtension(context);
    if (ext == 'epub') return 'epub';
    if (ext == 'md' || ext == 'markdown') return 'md';
    if (ext == 'html' || ext == 'htm') return 'html';
    return 'txt';
  }

  Future<String> _readTextSource(EngineContext context, String source) async {
    final raw = utf8.decode(
      await readFileBytes(context.inputPath),
      allowMalformed: true,
    );
    return switch (source) {
      'html' => stripHtml(raw),
      'md' => stripHtml(raw),
      _ => raw,
    };
  }

  // ─────────────────────────── 读取 ───────────────────────────

  _Ebook _readEpub(Uint8List bytes) {
    final package = ZipPackage.decode(bytes);

    // 1. 找 opf
    String? opfPath;
    final container = package.textOf('META-INF/container.xml');
    if (container != null) {
      final document = XmlDocument.parse(container);
      for (final node in document.descendantElements) {
        if (node.localName == 'rootfile') {
          opfPath = node.getAttribute('full-path');
          if (opfPath != null) break;
        }
      }
    }
    opfPath ??= package.firstWhereName((name) => name.endsWith('.opf')) ?? '';
    if (opfPath.isEmpty || !package.contains(opfPath)) {
      throw const EngineException('epub 中缺少 content.opf');
    }

    final basePath = opfPath.contains('/')
        ? opfPath.substring(0, opfPath.lastIndexOf('/') + 1)
        : '';
    final opf = XmlDocument.parse(package.textOf(opfPath)!);
    final title = opf.descendantElements
        .where((e) => e.localName == 'title')
        .map((e) => e.innerText.trim())
        .firstWhere((e) => e.isNotEmpty, orElse: () => '');
    final manifest = <String, String>{};
    for (final item in opf.descendantElements.where((e) => e.localName == 'item')) {
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      if (id != null && href != null) manifest[id] = href;
    }
    final spine = <String>[];
    for (final itemref in opf.descendantElements.where((e) => e.localName == 'itemref')) {
      final idref = itemref.getAttribute('idref');
      if (idref != null) spine.add(idref);
    }

    final chapters = <String>[];
    final ordered = spine.isEmpty ? manifest.values.toList() : [
      for (final id in spine)
        if (manifest[id] != null) manifest[id]!,
    ];
    for (final href in ordered) {
      final path = Uri.decodeFull('$basePath$href').replaceAll('%2F', '/');
      final content = package.textOf(path) ?? package.textOf(basePath + href);
      if (content == null) continue;
      final text = stripHtml(content);
      if (text.trim().isEmpty) continue;
      chapters.add(text.trim());
    }
    if (chapters.isEmpty) {
      throw const EngineException('epub 中没有解析到正文内容');
    }
    return _Ebook(title: title, chapters: chapters);
  }

  // ─────────────────────────── 输出 ───────────────────────────

  String _toMarkdown(_Ebook book) {
    final buffer = StringBuffer();
    if (book.title.isNotEmpty) {
      buffer.writeln('# ${book.title}');
      buffer.writeln();
    }
    for (var i = 0; i < book.chapters.length; i++) {
      buffer
        ..writeln('## 第 ${i + 1} 章')
        ..writeln()
        ..writeln(book.chapters[i])
        ..writeln();
    }
    return buffer.toString();
  }

  Uint8List _writeEpub(String title, String author, List<String> chapters) {
    final safeTitle = escapeXml(title);
    final safeAuthor = escapeXml(author);

    final chapterFiles = <String>[];
    for (var i = 0; i < chapters.length; i++) {
      final body = chapters[i]
          .split(RegExp(r'\n{2,}'))
          .map((p) => '<p>${escapeHtml(p.trim()).replaceAll('\n', '<br/>')}</p>')
          .join('\n');
      chapterFiles.add('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" lang="zh-CN">
<head><meta charset="utf-8"/><title>第 ${i + 1} 章</title>
<link rel="stylesheet" type="text/css" href="style.css"/></head>
<body><h1>第 ${i + 1} 章</h1>
$body
</body></html>
''');
    }

    final manifestItems = StringBuffer();
    final spineItems = StringBuffer();
    for (var i = 0; i < chapterFiles.length; i++) {
      manifestItems.writeln(
        '<item id="chapter${i + 1}" href="chapter${i + 1}.xhtml" '
        'media-type="application/xhtml+xml"/>',
      );
      spineItems.writeln('<itemref idref="chapter${i + 1}"/>');
    }

    final opf = '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="bookid">omniforge-${DateTime.now().millisecondsSinceEpoch}</dc:identifier>
    <dc:title>$safeTitle</dc:title>
    <dc:creator>$safeAuthor</dc:creator>
    <dc:language>zh-CN</dc:language>
    <meta property="dcterms:modified">${DateTime.now().toUtc().toIso8601String().split('.').first}Z</meta>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="css" href="style.css" media-type="text/css"/>
$manifestItems
  </manifest>
  <spine>
$spineItems
  </spine>
</package>
''';

    final nav = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="zh-CN">
<head><meta charset="utf-8"/><title>目录</title></head>
<body>
<nav epub:type="toc" id="toc"><h1>目录</h1><ol>
${[for (var i = 0; i < chapterFiles.length; i++) '<li><a href="chapter${i + 1}.xhtml">第 ${i + 1} 章</a></li>'].join()}
</ol></nav>
</body></html>
''';

    const containerXml = '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>
''';

    const css = '''
body { font-family: serif; line-height: 1.7; margin: 1.2em; }
h1 { font-size: 1.4em; margin: 1em 0 .6em; }
p { text-indent: 2em; margin: .4em 0; }
''';

    final archive = Archive()
      ..add(ArchiveFile('mimetype', 0, utf8.encode('application/epub+zip')))
      ..add(ArchiveFile(
        'META-INF/container.xml',
        0,
        utf8.encode(containerXml),
      ))
      ..add(ArchiveFile('OEBPS/content.opf', 0, utf8.encode(opf)))
      ..add(ArchiveFile('OEBPS/nav.xhtml', 0, utf8.encode(nav)))
      ..add(ArchiveFile('OEBPS/style.css', 0, utf8.encode(css)));
    for (var i = 0; i < chapterFiles.length; i++) {
      archive.add(ArchiveFile(
        'OEBPS/chapter${i + 1}.xhtml',
        0,
        utf8.encode(chapterFiles[i]),
      ));
    }
    return ZipEncoder().encodeBytes(archive);
  }
}

class _Ebook {
  final String title;
  final List<String> chapters;

  const _Ebook({required this.title, required this.chapters});

  String get plainText {
    final buffer = StringBuffer();
    if (title.isNotEmpty) {
      buffer
        ..writeln(title)
        ..writeln();
    }
    for (var i = 0; i < chapters.length; i++) {
      buffer
        ..writeln('第 ${i + 1} 章')
        ..writeln()
        ..writeln(chapters[i])
        ..writeln();
    }
    return buffer.toString().trim();
  }
}
