// ignore_for_file: avoid_print
// 幻灯片引擎 / 字体引擎离线自测脚本（纯 Dart，无 flutter 依赖）。
//
// 运行：/opt/dart/dart-sdk/bin/dart run tool/verify_office.dart
// 覆盖：
//   - 现造最小 pptx（2 页中文 + 1 张图片）→ SlidesEngine → txt / md / html / pdf
//   - 现造最小 odp（2 页）→ slides → txt
//   - 系统 TTF → woff → ttf 往返（魔数、表数量、表数据一致）
//   - OTF → woff → otf 往返（保留 OTTO flavor）
//   - woff2 输入 → PluginRequiredException（font-woff2）
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:omniforge/engine/common/package_io.dart';
import 'package:omniforge/engine/engines/font_engine.dart';
import 'package:omniforge/engine/engines/slides_engine.dart';
import 'package:omniforge/engine/i_engine.dart';

class VerifyFailure implements Exception {
  const VerifyFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class EngineRunResult {
  const EngineRunResult(this.outputPath, this.error, this.pluginId);

  final String? outputPath;
  final String? error;
  final String? pluginId;

  bool get ok => error == null && pluginId == null && outputPath != null;
}

final Map<String, int> _sizes = <String, int>{};

void expect(bool condition, String message) {
  if (!condition) throw VerifyFailure(message);
}

Uint8List _utf8Bytes(String text) =>
    Uint8List.fromList(utf8.encode(text));

Future<EngineRunResult> _run(
  IEngine engine, {
  required String inputPath,
  required String outputPath,
  required String targetFormat,
  required String sourceFormat,
  Map<String, dynamic> params = const <String, dynamic>{},
}) async {
  String? path;
  String? error;
  String? plugin;
  final context = EngineContext(
    inputPath: inputPath,
    outputPath: outputPath,
    targetFormat: targetFormat,
    sourceFormat: sourceFormat,
    params: params,
  );
  await for (final event in engine.convert(context)) {
    switch (event) {
      case Success():
        path = event.outputPath;
      case Error():
        error = event.message;
      case PluginRequired():
        plugin = event.pluginId;
      case Progress():
        break;
    }
  }
  return EngineRunResult(path, error, plugin);
}

String _readText(String path) => File(path).readAsStringSync();

void _record(String outputPath) {
  final file = File(outputPath);
  expect(file.existsSync(), '输出文件不存在：$outputPath');
  final size = file.lengthSync();
  expect(size > 0, '输出文件为空：$outputPath');
  _sizes[outputPath] = size;
}

int _u16be(Uint8List bytes, int offset) =>
    (bytes[offset] << 8) | bytes[offset + 1];

int _u32be(Uint8List bytes, int offset) =>
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3];

/// 生成一个最小可解析 pptx（2 页 + 1 张 png）。
Uint8List _buildPptx({
  required String title1,
  required String body1,
  required String title2,
  required String body2,
  Uint8List? png,
}) {
  const declaration = '<?xml version="1.0" encoding="UTF-8" '
      'standalone="yes"?>\n';
  const relNs = 'http://schemas.openxmlformats.org/package/2006/relationships';
  const officeRel =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

  String slideXml(String title, String body) => '$declaration'
      '<p:sld '
      'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:r="$officeRel" '
      'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
      '<p:cSld><p:spTree><p:sp><p:txBody>'
      '<a:bodyPr/><a:lstStyle/>'
      '<a:p><a:r><a:t>$title</a:t></a:r></a:p>'
      '<a:p><a:r><a:t>$body</a:t></a:r></a:p>'
      '</p:txBody></p:sp></p:spTree></p:cSld></p:sld>';

  final contentTypes = '$declaration'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/'
      'content-types">'
      '<Default Extension="rels" ContentType="application/vnd.'
      'openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Default Extension="png" ContentType="image/png"/>'
      '<Override PartName="/ppt/presentation.xml" ContentType="application/'
      'vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>'
      '<Override PartName="/ppt/slides/slide1.xml" ContentType="application/'
      'vnd.openxmlformats-officedocument.presentationml.slide+xml"/>'
      '<Override PartName="/ppt/slides/slide2.xml" ContentType="application/'
      'vnd.openxmlformats-officedocument.presentationml.slide+xml"/>'
      '</Types>';

  final rootRels = '$declaration'
      '<Relationships xmlns="$relNs">'
      '<Relationship Id="rId1" Type="$officeRel/officeDocument" '
      'Target="ppt/presentation.xml"/>'
      '</Relationships>';

  final presentation = '$declaration'
      '<p:presentation '
      'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:r="$officeRel" '
      'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
      '<p:sldIdLst>'
      '<p:sldId id="256" r:id="rId2"/>'
      '<p:sldId id="257" r:id="rId3"/>'
      '</p:sldIdLst>'
      '</p:presentation>';

  final presentationRels = '$declaration'
      '<Relationships xmlns="$relNs">'
      '<Relationship Id="rId1" Type="$officeRel/slideMaster" '
      'Target="slideMasters/slideMaster1.xml"/>'
      '<Relationship Id="rId2" Type="$officeRel/slide" '
      'Target="slides/slide1.xml"/>'
      '<Relationship Id="rId3" Type="$officeRel/slide" '
      'Target="slides/slide2.xml"/>'
      '</Relationships>';

  final slide1Rels = '$declaration'
      '<Relationships xmlns="$relNs">'
      '<Relationship Id="rId1" Type="$officeRel/image" '
      'Target="../media/image1.png"/>'
      '</Relationships>';

  final entries = <PackageEntry>[
    PackageEntry('[Content_Types].xml', _utf8Bytes(contentTypes)),
    PackageEntry('_rels/.rels', _utf8Bytes(rootRels)),
    PackageEntry('ppt/presentation.xml', _utf8Bytes(presentation)),
    PackageEntry('ppt/_rels/presentation.xml.rels', _utf8Bytes(presentationRels)),
    PackageEntry('ppt/slides/slide1.xml', _utf8Bytes(slideXml(title1, body1))),
    PackageEntry('ppt/slides/slide2.xml', _utf8Bytes(slideXml(title2, body2))),
    PackageEntry('ppt/slides/_rels/slide1.xml.rels', _utf8Bytes(slide1Rels)),
  ];
  if (png != null) {
    entries.add(PackageEntry('ppt/media/image1.png', png));
  }
  return ZipPackage.encodeEntries(entries);
}

/// 生成一个最小可解析 odp（2 页文本）。
Uint8List _buildOdp() {
  const content = '<?xml version="1.0" encoding="UTF-8"?>'
      '<office:document-content '
      'xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" '
      'xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0" '
      'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" '
      'xmlns:xlink="http://www.w3.org/1999/xlink" office:version="1.3">'
      '<office:body><office:presentation>'
      '<draw:page draw:name="page1"><draw:frame><draw:text-box>'
      '<text:p>ODP 第一页标题</text:p><text:p>ODP 第一页正文</text:p>'
      '</draw:text-box></draw:frame></draw:page>'
      '<draw:page draw:name="page2"><draw:frame><draw:text-box>'
      '<text:p>ODP 第二页标题</text:p><text:p>ODP 第二页正文</text:p>'
      '</draw:text-box></draw:frame></draw:page>'
      '</office:presentation></office:body></office:document-content>';
  return ZipPackage.encodeEntries(<PackageEntry>[
    PackageEntry(
      'mimetype',
      _utf8Bytes('application/vnd.oasis.opendocument.presentation'),
    ),
    PackageEntry('content.xml', _utf8Bytes(content)),
  ]);
}

Future<void> _verifySlidesPptx(Directory outputDir) async {
  print('── pptx → txt / md / html / pdf ──');
  final pptx = _buildPptx(
    title1: '第一页标题',
    body1: '第一页正文',
    title2: '第二页标题',
    body2: '第二页正文',
    png: _solidPng(),
  );
  final pptxPath = '${outputDir.path}/sample.pptx';
  File(pptxPath).writeAsBytesSync(pptx);

  const engine = SlidesEngine();

  final txtResult = await _run(
    engine,
    inputPath: pptxPath,
    outputPath: '${outputDir.path}/slides.txt',
    targetFormat: 'txt',
    sourceFormat: 'pptx',
  );
  expect(txtResult.ok, 'pptx → txt 失败：${txtResult.error ?? txtResult.pluginId}');
  final txt = _readText(txtResult.outputPath!);
  _record(txtResult.outputPath!);
  expect(txt.contains('=== 第 1 页 ==='), 'txt 缺少第 1 页标记');
  expect(txt.contains('=== 第 2 页 ==='), 'txt 缺少第 2 页标记');
  expect(txt.contains('第一页标题'), 'txt 缺少第一页标题');
  expect(txt.contains('第二页标题'), 'txt 缺少第二页标题');

  final mdResult = await _run(
    engine,
    inputPath: pptxPath,
    outputPath: '${outputDir.path}/slides.md',
    targetFormat: 'md',
    sourceFormat: 'pptx',
  );
  expect(mdResult.ok, 'pptx → md 失败：${mdResult.error ?? mdResult.pluginId}');
  final markdown = _readText(mdResult.outputPath!);
  _record(mdResult.outputPath!);
  expect(markdown.contains('## 第 1 页'), 'md 缺少第 1 页标题');
  expect(markdown.contains('## 第 2 页'), 'md 缺少第 2 页标题');
  expect(markdown.contains('![](media/image1.png)'), 'md 缺少图片引用');

  final htmlResult = await _run(
    engine,
    inputPath: pptxPath,
    outputPath: '${outputDir.path}/slides.html',
    targetFormat: 'html',
    sourceFormat: 'pptx',
  );
  expect(htmlResult.ok, 'pptx → html 失败：${htmlResult.error ?? htmlResult.pluginId}');
  final html = _readText(htmlResult.outputPath!);
  _record(htmlResult.outputPath!);
  expect(html.contains('<section class="slide"'), 'html 缺少 section');
  expect(html.contains('<h2>第 1 页</h2>'), 'html 缺少 h2 标题');
  expect(html.contains('data:image/png;base64,'), 'html 未内嵌图片');

  // 中文 PDF：有中文字体时应成功；本机无中文字体时应给出明确错误（不输出豆腐块）。
  final cjkPdf = await _run(
    engine,
    inputPath: pptxPath,
    outputPath: '${outputDir.path}/slides-cjk.pdf',
    targetFormat: 'pdf',
    sourceFormat: 'pptx',
  );
  if (cjkPdf.ok) {
    _checkPdf(cjkPdf.outputPath!, '中文 PDF');
    print('  中文 PDF：已使用系统字体生成');
  } else {
    expect(
      (cjkPdf.error ?? '').contains('字体'),
      '中文 PDF 失败信息应提示缺少字体，实际：${cjkPdf.error}',
    );
    print('  中文 PDF：本机无中文字体，按设计返回提示：${cjkPdf.error}');
  }

  // 英文 PDF：不依赖中文字体，必须真实产出 %PDF。
  final latin = _buildPptx(
    title1: 'Page One Title',
    body1: 'Page one body text.',
    title2: 'Page Two Title',
    body2: 'Page two body text.',
  );
  final latinPath = '${outputDir.path}/sample-latin.pptx';
  File(latinPath).writeAsBytesSync(latin);
  final pdfResult = await _run(
    engine,
    inputPath: latinPath,
    outputPath: '${outputDir.path}/slides-latin.pdf',
    targetFormat: 'pdf',
    sourceFormat: 'pptx',
  );
  expect(pdfResult.ok, 'pptx → pdf 失败：${pdfResult.error ?? pdfResult.pluginId}');
  _checkPdf(pdfResult.outputPath!, 'pptx pdf');
}

void _checkPdf(String path, String label) {
  final bytes = File(path).readAsBytesSync();
  _record(path);
  expect(bytes.length > 500, '$label 文件过小：${bytes.length}B（应 > 500B）');
  expect(
    String.fromCharCodes(bytes.sublist(0, 4)) == '%PDF',
    '$label 魔数不是 %PDF',
  );
}

Map<String, Uint8List> _sfntTables(Uint8List bytes) {
  final count = _u16be(bytes, 4);
  final tables = <String, Uint8List>{};
  for (var i = 0; i < count; i++) {
    final base = 12 + i * 16;
    final tag = String.fromCharCodes(bytes.sublist(base, base + 4));
    final offset = _u32be(bytes, base + 8);
    final length = _u32be(bytes, base + 12);
    tables[tag] = Uint8List.sublistView(bytes, offset, offset + length);
  }
  return tables;
}

bool _sameBytes(Uint8List left, Uint8List right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}

/// 往返后除 head（checkSumAdjustment 会重算）外表数据必须完全一致。
void _checkSfntRoundTrip(Uint8List original, Uint8List rebuilt, String label) {
  final before = _sfntTables(original);
  final after = _sfntTables(rebuilt);
  expect(before.length == after.length, '$label 表数量不一致');
  for (final entry in before.entries) {
    expect(after.containsKey(entry.key), '$label 缺少表 ${entry.key}');
    if (entry.key == 'head') continue;
    expect(
      _sameBytes(entry.value, after[entry.key]!),
      '$label 表 ${entry.key} 数据不一致',
    );
  }
}

Uint8List _solidPng() {
  final image = img.Image(width: 4, height: 4);
  img.fill(image, color: img.ColorRgb8(220, 60, 60));
  return Uint8List.fromList(img.encodePng(image));
}

Future<void> _verifySlidesOdp(Directory outputDir) async {
  print('── odp → txt ──');
  final odpPath = '${outputDir.path}/sample.odp';
  File(odpPath).writeAsBytesSync(_buildOdp());
  final result = await _run(
    const SlidesEngine(),
    inputPath: odpPath,
    outputPath: '${outputDir.path}/slides-odp.txt',
    targetFormat: 'txt',
    sourceFormat: 'odp',
  );
  expect(result.ok, 'odp → txt 失败：${result.error ?? result.pluginId}');
  final text = _readText(result.outputPath!);
  _record(result.outputPath!);
  expect(text.contains('=== 第 1 页 ==='), 'odp txt 缺少第 1 页标记');
  expect(text.contains('=== 第 2 页 ==='), 'odp txt 缺少第 2 页标记');
  expect(text.contains('ODP 第一页标题'), 'odp txt 缺少第一页标题');
  expect(text.contains('ODP 第二页正文'), 'odp txt 缺少第二页正文');

  // 旧版二进制 .ppt 不支持，应给出明确错误而不是产出损坏文件。
  final pptPath = '${outputDir.path}/legacy.ppt';
  File(pptPath).writeAsBytesSync(Uint8List.fromList(<int>[0xD0, 0xCF, 0x11, 0xE0]));
  final legacy = await _run(
    const SlidesEngine(),
    inputPath: pptPath,
    outputPath: '${outputDir.path}/legacy.txt',
    targetFormat: 'txt',
    sourceFormat: 'ppt',
  );
  expect(!legacy.ok, '旧版 .ppt 应被拒绝');
  expect(
    (legacy.error ?? '').contains('不支持'),
    '旧版 .ppt 错误信息不明确：${legacy.error}',
  );
}

Future<void> _verifyFonts(Directory outputDir) async {
  print('── 字体 ttf / otf ↔ woff ──');
  final ttfPath = _findFont(const ['.ttf']);
  expect(ttfPath != null, '未找到可用于测试的 .ttf 字体（系统缺少字体）');
  final sfnt = File(ttfPath!).readAsBytesSync();
  final sfntTables = _u16be(sfnt, 4);
  final sfntVersion = _u32be(sfnt, 0);
  print('  测试字体：$ttfPath（$sfntTables 张表）');

  final woffResult = await _run(
    const FontEngine(),
    inputPath: ttfPath,
    outputPath: '${outputDir.path}/font.woff',
    targetFormat: 'woff',
    sourceFormat: 'ttf',
  );
  expect(woffResult.ok, 'ttf → woff 失败：${woffResult.error ?? woffResult.pluginId}');
  final woff = File(woffResult.outputPath!).readAsBytesSync();
  _record(woffResult.outputPath!);
  expect(
    String.fromCharCodes(woff.sublist(0, 4)) == 'wOFF',
    'woff 魔数错误',
  );
  expect(_u16be(woff, 12) == sfntTables, 'woff 表数量与源字体不一致');
  expect(_u32be(woff, 8) == woff.length, 'woff 头部 length 字段与实际长度不一致');
  expect(_u32be(woff, 4) == sfntVersion, 'woff flavor 未保留源 sfntVersion');

  final backResult = await _run(
    const FontEngine(),
    inputPath: woffResult.outputPath!,
    outputPath: '${outputDir.path}/font-roundtrip.ttf',
    targetFormat: 'ttf',
    sourceFormat: 'woff',
  );
  expect(backResult.ok, 'woff → ttf 失败：${backResult.error ?? backResult.pluginId}');
  final rebuilt = File(backResult.outputPath!).readAsBytesSync();
  _record(backResult.outputPath!);
  expect(_u32be(rebuilt, 0) == sfntVersion, '回转 ttf 魔数错误');
  expect(_u16be(rebuilt, 4) == sfntTables, '回转 ttf 表数量不一致');
  _checkSfntRoundTrip(sfnt, rebuilt, 'ttf→woff→ttf');

  final otfPath = _findFont(const ['.otf']);
  if (otfPath != null) {
    final otf = File(otfPath).readAsBytesSync();
    final otfTables = _u16be(otf, 4);
    final otfWoffResult = await _run(
      const FontEngine(),
      inputPath: otfPath,
      outputPath: '${outputDir.path}/font-otf.woff',
      targetFormat: 'woff',
      sourceFormat: 'otf',
    );
    expect(
      otfWoffResult.ok,
      'otf → woff 失败：${otfWoffResult.error ?? otfWoffResult.pluginId}',
    );
    final otfWoff = File(otfWoffResult.outputPath!).readAsBytesSync();
    _record(otfWoffResult.outputPath!);
    expect(String.fromCharCodes(otfWoff.sublist(0, 4)) == 'wOFF', 'otf woff 魔数错误');
    expect(_u16be(otfWoff, 12) == otfTables, 'otf woff 表数量不一致');
    expect(
      String.fromCharCodes(otfWoff.sublist(4, 8)) == 'OTTO',
      'otf → woff 未保留 OTTO flavor',
    );
    final otfBack = await _run(
      const FontEngine(),
      inputPath: otfWoffResult.outputPath!,
      outputPath: '${outputDir.path}/font-otf-roundtrip.otf',
      targetFormat: 'otf',
      sourceFormat: 'woff',
    );
    expect(otfBack.ok, 'woff → otf 失败：${otfBack.error ?? otfBack.pluginId}');
    final otfRebuilt = File(otfBack.outputPath!).readAsBytesSync();
    _record(otfBack.outputPath!);
    expect(
      String.fromCharCodes(otfRebuilt.sublist(0, 4)) == 'OTTO',
      '回转 otf 魔数错误',
    );
    expect(_u16be(otfRebuilt, 4) == otfTables, '回转 otf 表数量不一致');
    _checkSfntRoundTrip(otf, otfRebuilt, 'otf→woff→otf');
  } else {
    print('  未找到 .otf 系统字体，跳过 otf 分支');
  }

  // woff2 应明确要求插件，而不是给出损坏的转换结果。
  final woff2Path = '${outputDir.path}/fake.woff2';
  File(woff2Path).writeAsBytesSync(
    Uint8List.fromList(<int>[0x77, 0x4F, 0x46, 0x32, ...List<int>.filled(40, 0)]),
  );
  final woff2Result = await _run(
    const FontEngine(),
    inputPath: woff2Path,
    outputPath: '${outputDir.path}/font-out.ttf',
    targetFormat: 'ttf',
    sourceFormat: 'woff2',
  );
  expect(!woff2Result.ok, 'woff2 输入应被拒绝');
  expect(woff2Result.pluginId == 'font-woff2', 'woff2 应返回插件 font-woff2');
}

/// 先查常见路径，再递归扫描候选目录。
String? _findFont(List<String> extensions) {
  const candidates = <String>[
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    '/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf',
    '/opt/flutter/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
    '/opt/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    '/opt/flutter/bin/cache/dart-sdk/bin/resources/devtools/assets/fonts/'
        'Roboto/Roboto-Regular.ttf',
  ];
  for (final candidate in candidates) {
    if (!File(candidate).existsSync()) continue;
    final lower = candidate.toLowerCase();
    if (extensions.any(lower.endsWith)) return candidate;
  }
  const directories = <String>[
    '/usr/share/fonts',
    '/opt/flutter/bin/cache/artifacts/material_fonts',
    '/opt/flutter/bin/cache/dart-sdk/bin/resources/devtools/assets/fonts',
  ];
  for (final directory in directories) {
    final dir = Directory(directory);
    if (!dir.existsSync()) continue;
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File) continue;
      final lower = entity.path.toLowerCase();
      if (extensions.any(lower.endsWith)) return entity.path;
    }
  }
  return null;
}

Future<void> main() async {
  final outputDir = Directory.systemTemp.createTempSync('omniforge_verify_');
  print('工作目录：${outputDir.path}\n');
  try {
    await _verifySlidesPptx(outputDir);
    await _verifySlidesOdp(outputDir);
    await _verifyFonts(outputDir);
    print('\n输出文件大小：');
    final keys = _sizes.keys.toList()..sort();
    for (final key in keys) {
      print('  ${_sizes[key]!.toString().padLeft(7)} B  $key');
    }
    print('\n✅ 全部验证通过（pptx/odp 文本与图片、PDF、字体双向转换）');
  } on VerifyFailure catch (failure) {
    stderr.writeln('\n❌ 验证失败：$failure');
    exitCode = 1;
  } catch (error) {
    stderr.writeln('\n❌ 验证异常：$error');
    exitCode = 1;
  } finally {
    try {
      outputDir.deleteSync(recursive: true);
    } catch (_) {
      // 临时目录清理失败不影响验证结论
    }
  }
}
