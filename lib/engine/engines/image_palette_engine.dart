import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../common/binary_io.dart';
import '../engine_utils.dart';
import '../i_engine.dart';

/// 图片 → 调色板引擎（纯 Dart）。
///
/// 用中位切分从位图里量化出 [colors] 种主色，输出 ASE / ACO / GPL / JSON
/// 四种调色板格式。颜色统一命名为 `Color 1..N`。
class ImagePaletteEngine extends SimpleEngine {
  const ImagePaletteEngine();

  @override
  String get id => 'image_palette';

  @override
  Future<void> execute(EngineContext context) async {
    final target = context.targetFormat.toLowerCase();
    if (!_supportedOutputs.contains(target)) {
      throw EngineException('图片调色板引擎不支持输出格式：$target');
    }

    final bytes = await readFileBytes(context.inputPath);
    final image = img.decodeImage(bytes);
    if (image == null) {
      throw const EngineException('无法解码输入图片');
    }

    final colorCount = intParam(context, 'colors', 8).clamp(1, 64);
    final packed = _quantize(image, colorCount);
    final colors = <_Rgb>[
      for (var i = 0; i < packed.length; i++)
        _Rgb.fromPacked(packed[i], 'Color ${i + 1}'),
    ];

    final Uint8List output;
    switch (target) {
      case 'ase':
        output = _writeAse(colors);
        break;
      case 'aco':
        output = _writeAco(colors);
        break;
      case 'gpl':
        output = _writeGpl(colors, inputStem(context));
        break;
      default:
        output = _writeJson(colors);
        break;
    }
    await writeFileBytes(context.outputPath, output);
  }

  static const Set<String> _supportedOutputs = <String>{
    'ase',
    'aco',
    'gpl',
    'json',
  };

  // ─────────────────────────── 颜色量化 ───────────────────────────

  /// 中位切分，返回按像素数量从多到少排列的 `0xRRGGBB` 颜色表。
  List<int> _quantize(img.Image image, int colorCount) {
    final bins = <int, _PaletteBin>{};
    for (final pixel in image) {
      final r = _channel255(pixel.rNormalized);
      final g = _channel255(pixel.gNormalized);
      final b = _channel255(pixel.bNormalized);
      final key = ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3);
      var bin = bins[key];
      if (bin == null) {
        bin = _PaletteBin(r >> 3, g >> 3, b >> 3);
        bins[key] = bin;
      }
      bin
        ..count += 1
        ..sumR += r
        ..sumG += g
        ..sumB += b;
    }

    final boxes = <List<_PaletteBin>>[bins.values.toList(growable: false)];
    while (boxes.length < colorCount) {
      var bestIndex = -1;
      var bestScore = -1.0;
      for (var i = 0; i < boxes.length; i++) {
        final box = boxes[i];
        if (box.length < 2) continue;
        final range = _boxRange(box);
        if (range < 1) continue;
        final weight =
            box.fold<int>(0, (sum, bin) => sum + bin.count).toDouble();
        final score = range * math.sqrt(weight);
        if (score > bestScore) {
          bestScore = score;
          bestIndex = i;
        }
      }
      if (bestIndex < 0) break;
      final split = _splitBox(boxes[bestIndex]);
      if (split == null) break;
      boxes[bestIndex] = split[0];
      boxes.add(split[1]);
    }

    final weighted = <_WeightedColor>[
      for (final box in boxes) _averageColor(box),
    ]..sort((a, b) => b.weight.compareTo(a.weight));
    final result = <int>[];
    for (final entry in weighted) {
      if (!result.contains(entry.packed)) result.add(entry.packed);
    }
    if (result.isEmpty) result.add(0x000000);
    return result;
  }

  int _channel255(num normalized) =>
      (normalized * 255).round().clamp(0, 255);

  int _boxRange(List<_PaletteBin> box) {
    var range = 0;
    for (var channel = 0; channel < 3; channel++) {
      var low = 32;
      var high = -1;
      for (final bin in box) {
        final value = bin.channel(channel);
        if (value < low) low = value;
        if (value > high) high = value;
      }
      if (high - low > range) range = high - low;
    }
    return range;
  }

  List<List<_PaletteBin>>? _splitBox(List<_PaletteBin> box) {
    var splitChannel = -1;
    var bestRange = 0;
    for (var channel = 0; channel < 3; channel++) {
      var low = 32;
      var high = -1;
      for (final bin in box) {
        final value = bin.channel(channel);
        if (value < low) low = value;
        if (value > high) high = value;
      }
      if (high - low > bestRange) {
        bestRange = high - low;
        splitChannel = channel;
      }
    }
    if (splitChannel < 0 || bestRange < 1) return null;

    final sorted = List<_PaletteBin>.from(box)
      ..sort((a, b) =>
          a.channel(splitChannel).compareTo(b.channel(splitChannel)));
    var total = 0;
    for (final bin in sorted) {
      total += bin.count;
    }
    var accumulated = 0;
    var splitAt = 0;
    for (var i = 0; i < sorted.length; i++) {
      accumulated += sorted[i].count;
      if (accumulated * 2 >= total) {
        splitAt = i;
        break;
      }
    }
    if (splitAt >= sorted.length - 1) splitAt = sorted.length - 2;
    if (splitAt < 0) return null;
    return <List<_PaletteBin>>[
      sorted.sublist(0, splitAt + 1),
      sorted.sublist(splitAt + 1),
    ];
  }

  _WeightedColor _averageColor(List<_PaletteBin> box) {
    var count = 0;
    var red = 0;
    var green = 0;
    var blue = 0;
    for (final bin in box) {
      count += bin.count;
      red += bin.sumR;
      green += bin.sumG;
      blue += bin.sumB;
    }
    if (count == 0) return const _WeightedColor(0, 0);
    final r = (red / count).round().clamp(0, 255);
    final g = (green / count).round().clamp(0, 255);
    final b = (blue / count).round().clamp(0, 255);
    return _WeightedColor((r << 16) | (g << 8) | b, count);
  }

  // ─────────────────────────── ASE ───────────────────────────

  Uint8List _writeAse(List<_Rgb> colors) {
    final writer = ByteWriter()
      ..ascii('ASEF')
      ..u16le(1) // version major
      ..u16le(0) // version minor
      ..u32le(colors.length);
    for (final color in colors) {
      final payload = ByteWriter()
        // 名称长度（UTF-16 码元数，含结尾 0）
        ..u16le(color.name.codeUnits.length + 1)
        ..utf16be(color.name)
        ..u16le(0)
        ..ascii('RGB ')
        ..f32le(color.red / 255.0)
        ..f32le(color.green / 255.0)
        ..f32le(color.blue / 255.0)
        ..u16le(0); // 颜色类型：全局
      writer
        ..u16le(0x0001) // 颜色块
        ..u32le(payload.length)
        ..bytes(payload.toBytes());
    }
    return writer.toBytes();
  }

  // ─────────────────────────── ACO ───────────────────────────

  Uint8List _writeAco(List<_Rgb> colors) {
    final writer = ByteWriter()
      ..u16le(1) // version 1
      ..u16le(colors.length);
    for (final color in colors) {
      writer
        ..u16le(0) // RGB 色彩空间
        ..u16le(color.red)
        ..u16le(color.green)
        ..u16le(color.blue)
        ..u16le(0);
    }
    return writer.toBytes();
  }

  // ─────────────────────────── GPL ───────────────────────────

  Uint8List _writeGpl(List<_Rgb> colors, String paletteName) {
    final buffer = StringBuffer()
      ..writeln('GIMP Palette')
      ..writeln('Name: $paletteName')
      ..writeln('Columns: 0')
      ..writeln('#')
      ..writeln('# Generated by OmniForge');
    for (final color in colors) {
      buffer.writeln(
        '${color.red.toString().padLeft(3)} '
        '${color.green.toString().padLeft(3)} '
        '${color.blue.toString().padLeft(3)}\t${color.name}',
      );
    }
    return Uint8List.fromList(utf8.encode(buffer.toString()));
  }

  // ─────────────────────────── JSON ───────────────────────────

  Uint8List _writeJson(List<_Rgb> colors) {
    final data = <Map<String, Object>>[
      for (final color in colors)
        <String, Object>{
          'hex': color.hex,
          'r': color.red,
          'g': color.green,
          'b': color.blue,
          'name': color.name,
        },
    ];
    return Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(data)),
    );
  }
}

/// 5bit 颜色直方图桶。
class _PaletteBin {
  _PaletteBin(this.r, this.g, this.b);

  final int r;
  final int g;
  final int b;
  int count = 0;
  int sumR = 0;
  int sumG = 0;
  int sumB = 0;

  int channel(int index) {
    switch (index) {
      case 0:
        return r;
      case 1:
        return g;
      default:
        return b;
    }
  }
}

/// 量化后的一种颜色及其覆盖的像素数。
class _WeightedColor {
  const _WeightedColor(this.packed, this.weight);

  final int packed;
  final int weight;
}

/// 调色板里的一个颜色。
class _Rgb {
  const _Rgb(this.red, this.green, this.blue, this.name);

  factory _Rgb.fromPacked(int packed, String name) => _Rgb(
        (packed >> 16) & 0xFF,
        (packed >> 8) & 0xFF,
        packed & 0xFF,
        name,
      );

  final int red;
  final int green;
  final int blue;
  final String name;

  String get hex => '#${red.toRadixString(16).padLeft(2, '0')}'
      '${green.toRadixString(16).padLeft(2, '0')}'
      '${blue.toRadixString(16).padLeft(2, '0')}';
}
