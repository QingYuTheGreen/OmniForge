// 图片类引擎自测脚本（纯 Dart，可用 `dart run tool/verify_img.dart` 运行）。
//
// 生成一张测试位图，依次跑通：
//   png → svg_vector（SVG 结构 + 体积）
//   png → image_palette（ase / aco / gpl / json 的魔数与字段）
//   png → image_doc（docx 包结构 + document.xml 里的画图节点）
// 任意断言失败直接 exit(1)。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:omniforge/engine/common/package_io.dart';
import 'package:omniforge/engine/engines/image_doc_engine.dart';
import 'package:omniforge/engine/engines/image_palette_engine.dart';
import 'package:omniforge/engine/engines/svg_vector_engine.dart';
import 'package:omniforge/engine/i_engine.dart';

int _step = 0;

void _check(bool condition, String message) {
  if (!condition) throw StateError('断言失败：$message');
}

void _ok(String message) {
  _step++;
  stdout.writeln('[$_step] OK  $message');
}

Future<void> _run(IEngine engine, EngineContext context) async {
  EngineProgress? last;
  await for (final event in engine.convert(context)) {
    last = event;
    if (event is Error) {
      throw StateError('引擎返回错误：${event.message}');
    }
    if (event is PluginRequired) {
      throw StateError('引擎意外要求插件：${event.pluginId}');
    }
  }
  if (last is! Success) {
    throw StateError('引擎没有返回 Success（最后事件：$last）');
  }
}

Future<void> _expectError(
  IEngine engine,
  EngineContext context,
  String expectedFragment,
) async {
  await for (final event in engine.convert(context)) {
    if (event is Error) {
      _check(
        event.message.contains(expectedFragment),
        '错误信息应包含 "$expectedFragment"，实际为 "${event.message}"',
      );
      return;
    }
    if (event is Success) {
      throw StateError('期望转换失败，但实际成功了');
    }
  }
  throw StateError('期望转换失败，但没有收到 Error 事件');
}

Future<void> main() async {
  final directory = Directory.systemTemp.createTempSync('omniforge_img_verify_');
  stdout.writeln('临时目录：${directory.path}');
  try {
    final source = _makeTestImage();
    final inputPath = '${directory.path}/sample.png';
    await File(inputPath).writeAsBytes(source);
    stdout.writeln('测试图：320x200 PNG，${source.length} 字节');

    await _verifySvg(directory, inputPath);
    await _verifyPalettes(directory, inputPath);
    await _verifyDocx(directory, inputPath, source);
    await _verifyDocxError(directory, inputPath);

    stdout.writeln('\n全部断言通过 ✅  （共 $_step 项检查）');
  } catch (error) {
    stderr.writeln('\n❌ 验证失败：$error');
    exit(1);
  } finally {
    try {
      directory.deleteSync(recursive: true);
    } catch (_) {
      // 清理失败不影响结论。
    }
  }
}

/// 画一张带渐变底、色块和圆形的测试图。
Uint8List _makeTestImage() {
  final image = img.Image(width: 320, height: 200, numChannels: 3);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      image.setPixelRgb(
        x,
        y,
        (x * 255) ~/ (image.width - 1),
        (y * 255) ~/ (image.height - 1),
        120,
      );
    }
  }
  img.fillRect(
    image,
    x1: 20,
    y1: 20,
    x2: 150,
    y2: 120,
    color: img.ColorRgb8(220, 40, 40),
  );
  img.fillCircle(
    image,
    x: 240,
    y: 100,
    radius: 62,
    color: img.ColorRgb8(30, 90, 200),
  );
  img.fillCircle(
    image,
    x: 240,
    y: 100,
    radius: 30,
    color: img.ColorRgb8(250, 220, 40),
  );
  return img.encodePng(image);
}

Future<void> _verifySvg(Directory directory, String inputPath) async {
  final outputPath = '${directory.path}/sample.svg';
  await _run(
    const SvgVectorEngine(),
    EngineContext(
      inputPath: inputPath,
      outputPath: outputPath,
      targetFormat: 'svg',
      sourceFormat: 'png',
      params: <String, dynamic>{
        'colors': 12,
        'tolerance': 1.2,
        'max_size': 256,
      },
    ),
  );
  final file = File(outputPath);
  _check(await file.exists(), 'SVG 输出文件存在');
  final size = await file.length();
  final content = await file.readAsString();
  _check(size > 200, 'SVG 体积应大于 200 字节，实际 $size');
  _check(size < 3 * 1024 * 1024, 'SVG 体积不应超过 3MB，实际 $size');
  _check(content.startsWith('<?xml'), 'SVG 应以 XML 声明开头');
  _check(content.contains('<svg'), 'SVG 应包含 <svg');
  _check(content.contains('</svg>'), 'SVG 应正确闭合 </svg>');
  _check(
    content.contains('viewBox="0 0 256 160"'),
    'max_size=256 时应缩放到 256x160 的 viewBox',
  );
  final pathCount = RegExp(r'<path ').allMatches(content).length;
  _check(pathCount >= 1, 'SVG 至少应有一条 <path>');
  _check(pathCount <= 12, '颜色数 12 时 <path> 不应超过 12 条，实际 $pathCount');
  for (final match in RegExp(r'd="([^"]+)"').allMatches(content)) {
    final data = match.group(1)!;
    _check(data.contains('M'), 'path 数据应包含 M 指令');
    _check(data.contains('Z'), 'path 数据应以 Z 闭合');
  }
  _ok('png → svg：$pathCount 条 path，${size} 字节');
}

Future<void> _verifyPalettes(Directory directory, String inputPath) async {
  const count = 8;
  final outputs = <String, String>{};
  for (final format in <String>['ase', 'aco', 'gpl', 'json']) {
    final outputPath = '${directory.path}/sample.$format';
    await _run(
      const ImagePaletteEngine(),
      EngineContext(
        inputPath: inputPath,
        outputPath: outputPath,
        targetFormat: format,
        sourceFormat: 'png',
        params: <String, dynamic>{'colors': count},
      ),
    );
    _check(await File(outputPath).exists(), '$format 输出文件存在');
    final size = await File(outputPath).length();
    _check(size > 20, '$format 输出体积应大于 20 字节，实际 $size');
    outputs[format] = outputPath;
    stdout.writeln('    $format → ${size} 字节');
  }

  _verifyAse(await File(outputs['ase']!).readAsBytes(), count);
  _verifyAco(await File(outputs['aco']!).readAsBytes(), count);
  _verifyGpl(await File(outputs['gpl']!).readAsString(), count);
  _verifyPaletteJson(await File(outputs['json']!).readAsString(), count);
  _ok('png → ase / aco / gpl / json 结构校验通过（各 $count 色）');
}

void _verifyAse(Uint8List bytes, int expectedColors) {
  _check(bytes.length >= 12, 'ASE 头部长度不足');
  _check(
    String.fromCharCodes(bytes.sublist(0, 4)) == 'ASEF',
    'ASE 魔数应为 ASEF',
  );
  final data = ByteData.sublistView(bytes);
  _check(data.getUint16(4, Endian.little) == 1, 'ASE 版本应为 1');
  final blockCount = data.getUint32(8, Endian.little);
  _check(blockCount == expectedColors, 'ASE 颜色块数量应为 $expectedColors');
  var offset = 12;
  var colorBlocks = 0;
  for (var i = 0; i < blockCount && offset + 6 <= bytes.length; i++) {
    final type = data.getUint16(offset, Endian.little);
    final length = data.getUint32(offset + 2, Endian.little);
    final blockStart = offset + 6;
    final blockEnd = blockStart + length;
    _check(blockEnd <= bytes.length, 'ASE 块长度越界');
    if (type == 0x0001) {
      colorBlocks++;
      final nameLength = data.getUint16(blockStart, Endian.little);
      _check(nameLength >= 2, 'ASE 颜色名称长度非法');
      final name = String.fromCharCodes(<int>[
        for (var j = 0; j < nameLength - 1; j++)
          data.getUint16(blockStart + 2 + j * 2, Endian.big),
      ]);
      if (colorBlocks == 1) {
        _check(name == 'Color 1', 'ASE 首个颜色名应为 "Color 1"，实际 "$name"');
      }
      final modelOffset = blockStart + 2 + nameLength * 2;
      _check(
        String.fromCharCodes(
              bytes.sublist(modelOffset, modelOffset + 4),
            ) ==
            'RGB ',
        'ASE 颜色模型应为 RGB',
      );
    }
    offset = blockEnd;
  }
  _check(colorBlocks == expectedColors, 'ASE 颜色块数量与预期不符');
}

void _verifyAco(Uint8List bytes, int expectedColors) {
  final data = ByteData.sublistView(bytes);
  _check(data.getUint16(0, Endian.little) == 1, 'ACO 版本应为 1');
  _check(
    data.getUint16(2, Endian.little) == expectedColors,
    'ACO 颜色数量应为 $expectedColors',
  );
  _check(
    bytes.length == 4 + expectedColors * 10,
    'ACO 长度应为 4 + N*10，实际 ${bytes.length}',
  );
  for (var i = 0; i < expectedColors; i++) {
    final base = 4 + i * 10;
    _check(data.getUint16(base, Endian.little) == 0, 'ACO 颜色空间应为 RGB(0)');
    for (var channel = 1; channel <= 3; channel++) {
      final value = data.getUint16(base + channel * 2, Endian.little);
      _check(value <= 255, 'ACO RGB 分量应在 0..255，实际 $value');
    }
  }
}

void _verifyGpl(String text, int expectedColors) {
  _check(text.startsWith('GIMP Palette'), 'GPL 应以 "GIMP Palette" 开头');
  _check(text.contains('Name: '), 'GPL 应包含 Name 行');
  var colorLines = 0;
  for (final rawLine in text.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    if (line.startsWith('GIMP Palette') ||
        line.startsWith('Name:') ||
        line.startsWith('Columns:')) {
      continue;
    }
    final parts = line.split(RegExp(r'\s+'));
    _check(parts.length >= 3, 'GPL 颜色行至少应有 3 个分量：$line');
    for (var i = 0; i < 3; i++) {
      final value = int.tryParse(parts[i]);
      _check(
        value != null && value >= 0 && value <= 255,
        'GPL RGB 分量应为 0..255：$line',
      );
    }
    _check(
      line.contains('Color ${colorLines + 1}'),
      'GPL 颜色名应为 Color N：$line',
    );
    colorLines++;
  }
  _check(colorLines == expectedColors, 'GPL 颜色行数应为 $expectedColors');
}

void _verifyPaletteJson(String text, int expectedColors) {
  final decoded = jsonDecode(text);
  _check(decoded is List, 'JSON 调色板顶层应为数组');
  final list = decoded as List<dynamic>;
  _check(list.length == expectedColors, 'JSON 颜色数量应为 $expectedColors');
  final hexPattern = RegExp(r'^#[0-9a-f]{6}$');
  for (var i = 0; i < list.length; i++) {
    final item = list[i];
    _check(item is Map, 'JSON 颜色项应为对象');
    final map = item as Map<String, dynamic>;
    final hex = map['hex'];
    _check(hex is String && hexPattern.hasMatch(hex), 'JSON hex 字段非法：$hex');
    for (final key in <String>['r', 'g', 'b']) {
      final value = map[key];
      _check(
        value is int && value >= 0 && value <= 255,
        'JSON $key 字段应为 0..255 整数：$value',
      );
    }
    _check(map['name'] == 'Color ${i + 1}', 'JSON 颜色名应为 Color N');
  }
}

Future<void> _verifyDocx(
  Directory directory,
  String inputPath,
  Uint8List sourcePng,
) async {
  final outputPath = '${directory.path}/sample.docx';
  await _run(
    const ImageDocEngine(),
    EngineContext(
      inputPath: inputPath,
      outputPath: outputPath,
      targetFormat: 'docx',
      sourceFormat: 'png',
      params: <String, dynamic>{'margin': 36},
    ),
  );
  final bytes = await File(outputPath).readAsBytes();
  _check(bytes.length > 1000, 'docx 体积应大于 1000 字节，实际 ${bytes.length}');
  final package = ZipPackage.decode(bytes);
  _check(package.contains('[Content_Types].xml'), 'docx 缺少 [Content_Types].xml');
  _check(package.contains('_rels/.rels'), 'docx 缺少 _rels/.rels');
  _check(package.contains('word/document.xml'), 'docx 缺少 word/document.xml');
  _check(
    package.contains('word/_rels/document.xml.rels'),
    'docx 缺少 word/_rels/document.xml.rels',
  );
  _check(package.contains('word/media/image1.png'), 'docx 缺少 word/media/image1.png');

  final contentTypes = package.textOf('[Content_Types].xml')!;
  _check(
    contentTypes.contains('Extension="png"'),
    'Content_Types 应声明 png 扩展名',
  );
  _check(
    contentTypes.contains('Extension="jpeg"'),
    'Content_Types 应声明 jpeg 扩展名',
  );

  final document = package.textOf('word/document.xml')!;
  _check(document.contains('<w:drawing>'), 'document.xml 应包含 w:drawing');
  _check(document.contains('<wp:inline'), 'document.xml 应包含 wp:inline');
  _check(document.contains('r:embed="rId1"'), 'document.xml 应引用 rId1');
  _check(
    RegExp(r'<wp:extent cx="\d+" cy="\d+"/>').hasMatch(document),
    'document.xml 应包含合法的 wp:extent 尺寸',
  );
  _check(document.contains('<w:sectPr>'), 'document.xml 应包含节属性');

  final media = package.bytesOf('word/media/image1.png')!;
  _check(
    media.length == sourcePng.length,
    'PNG 输入应原样嵌入（${sourcePng.length} 字节），实际 ${media.length}',
  );
  _check(
    media[0] == 0x89 && media[1] == 0x50,
    '嵌入的媒体应为 PNG 数据',
  );
  _ok('png → docx：${bytes.length} 字节（含 ${media.length} 字节图片）');
}

Future<void> _verifyDocxError(Directory directory, String inputPath) async {
  final outputPath = '${directory.path}/sample_error.pdf';
  await _expectError(
    const ImageDocEngine(),
    EngineContext(
      inputPath: inputPath,
      outputPath: outputPath,
      targetFormat: 'pdf',
      sourceFormat: 'png',
    ),
    '仅支持 docx',
  );
  _ok('image_doc 非 docx 目标时正确报错');
}
