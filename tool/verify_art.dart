// 猎奇跨类型转换引擎自检（纯 Dart，不依赖 Flutter）。
//
// 用法：dart run tool/verify_art.dart
//
// 覆盖：
// - ascii_art：灰度高宽比、字符集范围、braille 模式 U+2800..U+28FF
// - qr：PNG 尺寸、纯黑白、矩阵逐模块与标准功能图形一致、版本/Mask
// - identicon：尺寸与非纯色
// - palette_image：GPL/JSON 调色板 → 色卡 PNG、尺寸与颜色数量
import 'dart:convert';
import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:omniforge/engine/engines/ascii_art_engine.dart';
import 'package:omniforge/engine/engines/identicon_engine.dart';
import 'package:omniforge/engine/engines/palette_image_engine.dart';
import 'package:omniforge/engine/engines/qr_engine.dart';
import 'package:omniforge/engine/i_engine.dart';

var _failures = 0;

void check(bool condition, String message) {
  if (condition) {
    stdout.writeln('  ✓ $message');
  } else {
    _failures++;
    stderr.writeln('  ✗ $message');
  }
}

void section(String name) => stdout.writeln('\n[$name]');

Future<bool> runEngine(
  IEngine engine, {
  required String input,
  required String output,
  required String format,
  Map<String, dynamic> params = const {},
}) async {
  final events = await engine
      .convert(EngineContext(
        inputPath: input,
        outputPath: output,
        targetFormat: format,
        params: params,
      ))
      .toList();
  for (final event in events) {
    if (event is Error) {
      stderr.writeln('  ✗ ${engine.id} 失败：${event.message}');
      _failures++;
      return false;
    }
  }
  if (events.whereType<Success>().isEmpty) {
    stderr.writeln('  ✗ ${engine.id} 未返回成功事件');
    _failures++;
    return false;
  }
  return true;
}

void printSize(String label, String path) {
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('  ✗ 输出文件不存在：$path');
    _failures++;
    return;
  }
  final bytes = file.lengthSync();
  stdout.writeln('  · $label 文件大小：$bytes B（$path）');
}

Future<void> main() async {
  final tempDir =
      await Directory.systemTemp.createTemp('omniforge_art_verify_');
  stdout.writeln('临时目录：${tempDir.path}');
  try {
    final inputImage = await _makeTestImage(tempDir.path);
    await _testAscii(tempDir.path, inputImage);
    await _testQr(tempDir.path);
    await _testIdenticon(tempDir.path, inputImage);
    await _testPalette(tempDir.path);
  } catch (error, stack) {
    _failures++;
    stderr.writeln('  ✗ 未捕获异常：$error\n$stack');
  } finally {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {
      // 清理失败不影响判定。
    }
  }

  stdout.writeln(
    _failures == 0 ? '\n✓ 全部验证通过' : '\n✗ 共 $_failures 项失败',
  );
  await stdout.flush();
  exit(_failures == 0 ? 0 : 1);
}

/// 生成 200×150 渐变 + 色块测试图。
Future<String> _makeTestImage(String dir) async {
  const width = 200;
  const height = 150;
  final image = img.Image(width: width, height: height, numChannels: 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      int r;
      int g;
      int b;
      if (x < width ~/ 2) {
        r = (x * 255 / (width ~/ 2 - 1)).round();
        g = (y * 255 / (height - 1)).round();
        b = (x + y) % 2 == 0 ? 210 : 40;
      } else {
        r = ((x - width ~/ 2) * 255 / (width ~/ 2 - 1)).round();
        g = (y * 255 / (height - 1)).round();
        b = 255;
      }
      // 两个高对比色块，保证字符画有明暗层次。
      if (x >= 20 && x < 70 && y >= 20 && y < 70) {
        r = 255;
        g = 255;
        b = 0;
      }
      if (x >= 130 && x < 180 && y >= 80 && y < 130) {
        r = 0;
        g = 0;
        b = 0;
      }
      image.setPixelRgb(x, y, r, g, b);
    }
  }
  final path = '$dir/test_input.png';
  await File(path).writeAsBytes(img.encodePng(image));
  stdout.writeln('测试图：$path（$width×$height）');
  return path;
}

Future<void> _testAscii(String dir, String input) async {
  section('ascii_art');
  const engine = AsciiArtEngine();
  check(engine.id == 'ascii_art', 'id = ascii_art');

  final asciiPath = '$dir/ascii.txt';
  if (await runEngine(
    engine,
    input: input,
    output: asciiPath,
    format: 'txt',
  )) {
    final text = await File(asciiPath).readAsString();
    final lines = text.split('\n');
    final rowCount = lines.isNotEmpty && lines.last.isEmpty
        ? lines.length - 1
        : lines.length;
    check(rowCount > 10, '输出行数 $rowCount > 10');
    final allowed = AsciiArtEngine.defaultCharset.split('').toSet();
    var invalid = '';
    for (final rune in text.runes) {
      if (rune == 0x0A || rune == 0x0D) continue;
      final char = String.fromCharCode(rune);
      if (!allowed.contains(char)) {
        invalid = char;
        break;
      }
    }
    check(invalid.isEmpty, '字符全部在默认梯度 "$allowed" 之内'
        '${invalid.isEmpty ? '' : '（发现 "$invalid"）'}');
    final bytes = File(asciiPath).lengthSync();
    check(bytes > 200, '文件大小 $bytes B > 200 B');
    printSize('ascii', asciiPath);
  }

  // braille：分别用参数 mode=braille 与 targetFormat=braille 触发。
  for (final variant in [
    ('params', <String, dynamic>{'mode': 'braille'}, 'txt'),
    ('targetFormat', <String, dynamic>{}, 'braille'),
  ]) {
    final label = variant.$1;
    final path = '$dir/braille_$label.txt';
    if (await runEngine(
      engine,
      input: input,
      output: path,
      format: variant.$3,
      params: variant.$2,
    )) {
      final text = await File(path).readAsString();
      final hasBraille =
          text.runes.any((rune) => rune >= 0x2800 && rune <= 0x28FF);
      check(hasBraille, '[$label] 含 U+2800..U+28FF 盲文字符');
      final brailleLines = text.split('\n').where((l) => l.isNotEmpty).length;
      check(brailleLines > 10, '[$label] 输出行数 $brailleLines > 10');
      printSize('braille[$label]', path);
    }
  }
}

Future<void> _testQr(String dir) async {
  section('qr');
  const text = 'https://example.com';
  final input = '$dir/qr_input.txt';
  await File(input).writeAsString(text);
  const engine = QrEngine();
  check(engine.id == 'qr', 'id = qr');

  final pngPath = '$dir/qr.png';
  const size = 512;
  if (!await runEngine(
    engine,
    input: input,
    output: pngPath,
    format: 'png',
    params: {'size': size, 'margin': 4, 'ec': 'M'},
  )) {
    return;
  }
  printSize('qr', pngPath);

  final bytes = await File(pngPath).readAsBytes();
  final output = img.decodeImage(bytes);
  check(output != null, '输出 PNG 可解码');
  if (output == null) return;
  check(output.width == size && output.height == size,
      '输出尺寸 ${output.width}×${output.height} == $size×$size');

  final colors = <int>{};
  for (var y = 0; y < output.height; y++) {
    for (var x = 0; x < output.width; x++) {
      final pixel = output.getPixel(x, y);
      colors.add(
        (pixel.r.toInt() << 16) |
            (pixel.g.toInt() << 8) |
            pixel.b.toInt(),
      );
    }
  }
  check(colors.length == 2, '颜色种数 ${colors.length} == 2（纯黑白）');
  check(colors.contains(0x000000) && colors.contains(0xFFFFFF),
      '包含纯黑 0x000000 与纯白 0xFFFFFF');

  // 用同一编码器拿到矩阵，逐模块核对渲染是否正确。
  final symbol = QrSymbol.encodeBytes(utf8.encode(text), 'M');
  stdout.writeln(
    '  · QR 版本 ${symbol.version}（${symbol.dimension}×${symbol.dimension} 模块），'
    '纠错 ${symbol.ecLevel}，掩码 ${symbol.mask}',
  );
  check(symbol.version == 2, '“$text” 在 M 级下选择版本 ${symbol.version} == 2');

  const margin = 4;
  final total = symbol.dimension + margin * 2;
  final scale = size / total;
  var mismatches = 0;
  for (var row = 0; row < symbol.dimension; row++) {
    for (var col = 0; col < symbol.dimension; col++) {
      final cx = (((col + margin) + 0.5) * scale).floor().clamp(0, size - 1);
      final cy = (((row + margin) + 0.5) * scale).floor().clamp(0, size - 1);
      final pixel = output.getPixel(cx, cy);
      final dark = pixel.r < 128;
      if (dark != symbol.modules[row][col]) mismatches++;
    }
  }
  check(mismatches == 0, '渲染矩阵与符号矩阵逐模块一致（不一致 $mismatches 个）');

  // 三个角的定位图形：外圈 7×7 的边应为黑，中心 3×3 应为黑。
  bool finderOk(int top, int left) {
    for (var dy = 0; dy < 7; dy++) {
      for (var dx = 0; dx < 7; dx++) {
        final expected =
            dy == 0 || dy == 6 || dx == 0 || dx == 6 ||
            (dy >= 2 && dy <= 4 && dx >= 2 && dx <= 4);
        if (symbol.modules[top + dy][left + dx] != expected) return false;
      }
    }
    return true;
  }

  final last = symbol.dimension - 7;
  check(
    finderOk(0, 0) && finderOk(0, last) && finderOk(last, 0),
    '三个角的 7×7 定位图形符合标准',
  );
  // 定时图形：第 6 行/列黑白交替。
  var timingOk = true;
  for (var i = 8; i < symbol.dimension - 8; i++) {
    if (symbol.modules[6][i] != i.isEven) timingOk = false;
    if (symbol.modules[i][6] != i.isEven) timingOk = false;
  }
  check(timingOk, '第 6 行/列定时图形黑白交替');

  // 左上角静区（margin 区域内）应为纯白。
  check(
    output.getPixel(0, 0).r > 200 &&
        output.getPixel(margin * scale ~/ 2, margin * scale ~/ 2).r > 200,
    '静区（margin=4 模块）为白色',
  );
}

Future<void> _testIdenticon(String dir, String input) async {
  section('identicon');
  const engine = IdenticonEngine();
  check(engine.id == 'identicon', 'id = identicon');

  final pngPath = '$dir/identicon.png';
  if (!await runEngine(
    engine,
    input: input,
    output: pngPath,
    format: 'png',
  )) {
    return;
  }
  printSize('identicon', pngPath);
  final output = img.decodeImage(await File(pngPath).readAsBytes());
  check(output != null, '输出 PNG 可解码');
  if (output == null) return;
  check(output.width == 420 && output.height == 420,
      '默认尺寸 ${output.width}×${output.height} == 420×420');

  final colors = <int>{};
  for (var y = 0; y < output.height; y++) {
    for (var x = 0; x < output.width; x++) {
      final pixel = output.getPixel(x, y);
      colors.add(
        (pixel.r.toInt() << 16) |
            (pixel.g.toInt() << 8) |
            pixel.b.toInt(),
      );
    }
  }
  check(colors.length >= 2, '非纯色：颜色种数 ${colors.length} >= 2');
  check(output.getPixel(0, 0).r > 240, '背景角落为白色');
}

Future<void> _testPalette(String dir) async {
  section('palette_image');
  const engine = PaletteImageEngine();
  check(engine.id == 'palette_image', 'id = palette_image');

  // 4 色 GPL。
  final gplPath = '$dir/palette.gpl';
  await File(gplPath).writeAsString(
    'GIMP Palette\n'
    'Name: test\n'
    'Columns: 4\n'
    '#\n'
    '255   0   0\tred\n'
    '  0 255   0\tgreen\n'
    '  0   0 255\tblue\n'
    '255 255   0\tyellow\n',
  );
  final pngPath = '$dir/palette.png';
  if (!await runEngine(
    engine,
    input: gplPath,
    output: pngPath,
    format: 'png',
  )) {
    return;
  }
  printSize('palette', pngPath);
  final output = img.decodeImage(await File(pngPath).readAsBytes());
  check(output != null, '输出 PNG 可解码');
  if (output == null) return;

  // columns=8 默认，4 色只有一行：宽 = 8 + 8*(96+8) = 840。
  check(output.width == 840, '输出宽度 ${output.width} == 840');
  check(output.height > 96, '输出高度 ${output.height} > 96');

  final colors = <int>{};
  for (var y = 0; y < output.height; y++) {
    for (var x = 0; x < output.width; x++) {
      final pixel = output.getPixel(x, y);
      colors.add(
        (pixel.r.toInt() << 16) |
            (pixel.g.toInt() << 8) |
            pixel.b.toInt(),
      );
    }
  }
  check(colors.length >= 4, '颜色种数 ${colors.length} >= 4');
  check(
    colors.contains(0xFF0000) &&
        colors.contains(0x00FF00) &&
        colors.contains(0x0000FF) &&
        colors.contains(0xFFFF00),
    '四个调色板颜色均出现在图中',
  );

  // JSON 调色板也能解析（hex 字符串）。
  final jsonPath = '$dir/palette.json';
  await File(jsonPath).writeAsString(jsonEncode({
    'name': 'json-test',
    'colors': ['#112233', '#445566', '#778899'],
  }));
  final jsonPng = '$dir/palette_json.png';
  if (await runEngine(
    engine,
    input: jsonPath,
    output: jsonPng,
    format: 'png',
    params: {'columns': 3, 'cell': 64},
  )) {
    final jsonImage = img.decodeImage(await File(jsonPng).readAsBytes());
    check(jsonImage != null && jsonImage.width == 8 + 3 * (64 + 8),
        'JSON 调色板：columns=3 / cell=64 时宽度正确');
    printSize('palette-json', jsonPng);
  }
}
