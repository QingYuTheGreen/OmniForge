// image_doc 引擎自测脚本（纯 Dart，可用 `dart run tool/verify_imgdoc.dart` 运行）。
//
// 生成一张 240×160 的测试 PNG，依次验证：
//   png → docx（默认参数：包结构、DrawingML 节点、EMU 尺寸）
//   png → docx（width=120 + caption：缩放后的宽度与说明文字）
//   png → pdf（非法目标格式必须给出「仅支持 docx」错误）
// 任意断言失败直接 exit(1)，全部通过打印 `✓ image_doc 自检通过`。
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:omniforge/engine/common/package_io.dart';
import 'package:omniforge/engine/engines/image_doc_engine.dart';
import 'package:omniforge/engine/i_engine.dart';

/// 96 DPI 下 1 像素对应的 EMU。
const int _emuPerPixel = 9525;

/// 源图片尺寸。
const int _sourceWidth = 240;
const int _sourceHeight = 160;

int _step = 0;

void _check(bool condition, String message) {
  if (!condition) throw StateError('断言失败：$message');
}

void _ok(String message) {
  _step++;
  stdout.writeln('[$_step] OK  $message');
}

/// 跑一次转换，要求最终返回 Success。
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

/// 跑一次转换，要求最终返回 Error 且消息包含 [fragment]。
Future<void> _expectError(
  IEngine engine,
  EngineContext context,
  String fragment,
) async {
  await for (final event in engine.convert(context)) {
    if (event is Error) {
      _check(
        event.message.contains(fragment),
        '错误信息应包含 "$fragment"，实际为 "${event.message}"',
      );
      return;
    }
    if (event is Success) {
      throw StateError('期望转换失败，但实际成功了');
    }
  }
  throw StateError('期望转换失败，但没有收到 Error 事件');
}

/// 断言实际 EMU 与期望值的偏差不超过 ±1%。
void _expectEmu(int actual, int expected, String label) {
  final delta = (actual - expected).abs();
  _check(
    delta <= expected * 0.01,
    '$label 应约为 $expected EMU（±1%），实际 $actual',
  );
}

/// 从 document.xml 中取出 `<wp:extent cx="…" cy="…"/>` 的宽高。
(int, int) _extentOf(String documentXml) {
  final match = RegExp(r'<wp:extent cx="(\d+)" cy="(\d+)"/>')
      .firstMatch(documentXml);
  _check(match != null, 'document.xml 中应存在 <wp:extent cx="…" cy="…"/>');
  return (int.parse(match!.group(1)!), int.parse(match.group(2)!));
}

/// 画一张 240×160、带三块色块的测试图。
Uint8List _makeTestImage() {
  final image = img.Image(width: _sourceWidth, height: _sourceHeight);
  img.fillRect(
    image,
    x1: 0,
    y1: 0,
    x2: 79,
    y2: _sourceHeight - 1,
    color: img.ColorRgb8(220, 40, 40),
  );
  img.fillRect(
    image,
    x1: 80,
    y1: 0,
    x2: 159,
    y2: _sourceHeight - 1,
    color: img.ColorRgb8(40, 180, 90),
  );
  img.fillRect(
    image,
    x1: 160,
    y1: 0,
    x2: _sourceWidth - 1,
    y2: _sourceHeight - 1,
    color: img.ColorRgb8(40, 90, 220),
  );
  return Uint8List.fromList(img.encodePng(image));
}

Future<void> main() async {
  final directory = Directory.systemTemp.createTempSync('omniforge_imgdoc_');
  stdout.writeln('临时目录：${directory.path}');
  try {
    final source = _makeTestImage();
    final inputPath = '${directory.path}/sample.png';
    await File(inputPath).writeAsBytes(source);
    stdout.writeln(
      '测试图：${_sourceWidth}x$_sourceHeight PNG，${source.length} 字节',
    );

    await _verifyDefault(directory, inputPath);
    await _verifyWidthAndCaption(directory, inputPath);
    await _verifyAlign(directory, inputPath);
    await _verifyInvalidTarget(directory, inputPath);

    stdout.writeln('\n✓ image_doc 自检通过（共 $_step 项检查）');
  } catch (error) {
    stderr.writeln('\n❌ image_doc 自检失败：$error');
    exit(1);
  } finally {
    try {
      directory.deleteSync(recursive: true);
    } catch (_) {
      // 清理失败不影响结论。
    }
  }
}

/// 默认参数：docx 包结构 + DrawingML 内嵌图片 + 原图 EMU 尺寸。
Future<void> _verifyDefault(Directory directory, String inputPath) async {
  final outputPath = '${directory.path}/default.docx';
  await _run(
    const ImageDocEngine(),
    EngineContext(
      inputPath: inputPath,
      outputPath: outputPath,
      targetFormat: 'docx',
      sourceFormat: 'png',
    ),
  );

  final file = File(outputPath);
  _check(await file.exists(), 'docx 输出文件存在');
  final bytes = await file.readAsBytes();
  _check(bytes.isNotEmpty, 'docx 输出文件非空');
  _check(bytes.length > 1000, 'docx 体积应大于 1000 字节，实际 ${bytes.length}');

  final package = ZipPackage.decode(bytes);
  for (final name in <String>[
    '[Content_Types].xml',
    '_rels/.rels',
    'word/document.xml',
    'word/_rels/document.xml.rels',
    'word/media/image1.png',
  ]) {
    _check(package.contains(name), 'docx 缺少条目 $name');
  }

  final contentTypes = package.textOf('[Content_Types].xml')!;
  _check(
    contentTypes.contains('Extension="png"'),
    'Content_Types 应声明 png 扩展名',
  );
  _check(
    contentTypes.contains('document.xml'),
    'Content_Types 应声明 word/document.xml',
  );

  final documentRels = package.textOf('word/_rels/document.xml.rels')!;
  _check(
    documentRels.contains('media/image1.png'),
    'document.xml.rels 应引用 media/image1.png',
  );

  final documentXml = package.textOf('word/document.xml')!;
  _check(documentXml.contains('<w:drawing>'), 'document.xml 应包含 <w:drawing>');
  _check(documentXml.contains('<wp:extent'), 'document.xml 应包含 <wp:extent');
  _check(
    documentXml.contains('r:embed="rId1"'),
    'document.xml 应包含 r:embed="rId1"',
  );

  final (cx, cy) = _extentOf(documentXml);
  _expectEmu(cx, _sourceWidth * _emuPerPixel, '默认宽度');
  _expectEmu(cy, _sourceHeight * _emuPerPixel, '默认高度');

  final media = package.bytesOf('word/media/image1.png')!;
  _check(
    media.length > 8 && media[0] == 0x89 && media[1] == 0x50,
    '嵌入媒体应为 PNG 数据',
  );

  _ok(
    'png → docx 默认：${bytes.length} 字节，'
    'extent=${cx}x$cy EMU（原图 ${_sourceWidth}x$_sourceHeight px）',
  );
}

/// width=120 + caption：等比缩放后的宽度与说明文字。
Future<void> _verifyWidthAndCaption(
  Directory directory,
  String inputPath,
) async {
  final outputPath = '${directory.path}/scaled.docx';
  await _run(
    const ImageDocEngine(),
    EngineContext(
      inputPath: inputPath,
      outputPath: outputPath,
      targetFormat: 'docx',
      sourceFormat: 'png',
      params: <String, dynamic>{'width': 120, 'caption': '测试图片'},
    ),
  );

  final package = ZipPackage.decode(await File(outputPath).readAsBytes());
  final documentXml = package.textOf('word/document.xml')!;
  final (cx, cy) = _extentOf(documentXml);
  _expectEmu(cx, 120 * _emuPerPixel, 'width=120 时的宽度');
  _expectEmu(cy, 80 * _emuPerPixel, 'width=120 时的高度（等比）');
  _check(
    documentXml.contains('测试图片'),
    'document.xml 应包含说明文字「测试图片」',
  );

  _ok('png → docx width=120 + caption：extent=${cx}x$cy EMU，含说明文字');
}

/// align=left / right 应写进 w:jc，未知值回退 center。
Future<void> _verifyAlign(Directory directory, String inputPath) async {
  for (final align in <String>['left', 'right']) {
    final outputPath = '${directory.path}/align_$align.docx';
    await _run(
      const ImageDocEngine(),
      EngineContext(
        inputPath: inputPath,
        outputPath: outputPath,
        targetFormat: 'docx',
        sourceFormat: 'png',
        params: <String, dynamic>{'align': align},
      ),
    );
    final documentXml = ZipPackage.decode(
      await File(outputPath).readAsBytes(),
    ).textOf('word/document.xml')!;
    _check(
      documentXml.contains('<w:jc w:val="$align"/>'),
      'align=$align 时 document.xml 应包含 <w:jc w:val="$align"/>',
    );
  }
  _ok('align=left / right 正确写入 w:jc');
}

/// 非法目标格式必须报「仅支持 docx」。
Future<void> _verifyInvalidTarget(
  Directory directory,
  String inputPath,
) async {
  final outputPath = '${directory.path}/invalid.pdf';
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
  _check(!await File(outputPath).exists(), '失败时不应生成输出文件');

  _ok('非法目标格式 pdf 正确报错（仅支持 docx），且未生成输出');
}
