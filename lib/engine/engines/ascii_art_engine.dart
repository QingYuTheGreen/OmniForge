import 'dart:math' as math;

import 'package:image/image.dart' as img;

import '../engine_utils.dart';
import '../i_engine.dart';

/// ASCII 字符画引擎：任意位图 → 纯文本字符画 / 盲文点阵。
///
/// 输出统一写成 UTF-8 文本（txt），终端字符高宽比约为 1:2，因此行数按
/// 「列数 × 图片高宽比 × 0.5」换算。
///
/// 必选参数：
/// - `width`  int    目标列数，默认 100，clamp 20..400
/// - `charset` String 浅→深字符梯度，默认 `" .:-=+*#%@"`
/// - `invert`  bool   是否反相，默认 false
/// - `mode`    String `"braille"` 时切换盲文模式（也可用 targetFormat=braille）
/// - `threshold` int  盲文模式灰度阈值，默认 128
class AsciiArtEngine extends SimpleEngine {
  const AsciiArtEngine();

  @override
  String get id => 'ascii_art';

  static const String defaultCharset = ' .:-=+*#%@';

  @override
  Future<void> execute(EngineContext context) async {
    final bytes = await readFileBytes(context.inputPath);
    final source = img.decodeImage(bytes);
    if (source == null || source.width <= 0 || source.height <= 0) {
      throw const EngineException('无法解码该文件为图片，请确认输入是 jpg/png/webp/bmp/gif/tiff 等位图');
    }

    final mode = stringParam(context, 'mode').toLowerCase();
    final target = context.targetFormat.toLowerCase();
    final useBraille = mode == 'braille' || target == 'braille';

    final text = useBraille
        ? _renderBraille(context, source)
        : _renderAscii(context, source);
    await writeFileText(context.outputPath, text);
  }

  int _columns(EngineContext context) =>
      intParam(context, 'width', 100).clamp(20, 400);

  /// 按终端字符高宽比 0.5 计算输出行数（行是字符行）。
  int _rowCount(EngineContext context, img.Image image) {
    final columns = _columns(context);
    final rows = columns * image.height / image.width * 0.5;
    return math.max(1, rows.round());
  }

  String _renderAscii(EngineContext context, img.Image image) {
    final columns = _columns(context);
    final rows = _rowCount(context, image);

    var charset = stringParam(context, 'charset', defaultCharset);
    if (charset.runes.length < 2) {
      throw const EngineException('charset 至少需要 2 个字符');
    }
    final ramp = charset.runes.map(String.fromCharCode).toList();
    final invert = boolParam(context, 'invert', false);
    final shades = invert ? ramp.reversed.toList() : ramp;

    final resized = img.copyResize(
      image,
      width: columns,
      height: rows,
      interpolation: img.Interpolation.average,
    );

    final buffer = StringBuffer();
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < columns; x++) {
        final pixel = resized.getPixel(x, y);
        final luminance =
            0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
        // 浅色 → ramp 前面的字符，深色 → ramp 后面的字符。
        final index = ((1 - luminance / 255.0) * (shades.length - 1))
            .round()
            .clamp(0, shades.length - 1);
        buffer.write(shades[index]);
      }
      buffer.write('\n');
    }
    return buffer.toString();
  }

  String _renderBraille(EngineContext context, img.Image image) {
    final columns = _columns(context);
    // 一个盲文字符 = 2 像素宽 × 4 像素高，字符高宽比恰为 0.5，无需额外拉伸。
    final charRows = _rowCount(context, image);
    final pixelWidth = columns * 2;
    final pixelHeight = charRows * 4;

    final resized = img.copyResize(
      image,
      width: pixelWidth,
      height: pixelHeight,
      interpolation: img.Interpolation.average,
    );

    final threshold = intParam(context, 'threshold', 128).clamp(0, 255);
    final invert = boolParam(context, 'invert', false);

    // Unicode 盲文 8 点阵位值：列 0 = 左，列 1 = 右。
    const dots = <List<int>>[
      [0x01, 0x08],
      [0x02, 0x10],
      [0x04, 0x20],
      [0x40, 0x80],
    ];

    final buffer = StringBuffer();
    for (var cy = 0; cy < charRows; cy++) {
      for (var cx = 0; cx < columns; cx++) {
        var bits = 0;
        for (var dy = 0; dy < 4; dy++) {
          for (var dx = 0; dx < 2; dx++) {
            final pixel =
                resized.getPixel(cx * 2 + dx, cy * 4 + dy);
            final luminance =
                0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
            final dark =
                invert ? luminance >= threshold : luminance < threshold;
            if (dark) bits |= dots[dy][dx];
          }
        }
        // U+2800 为空白盲文，位值叠加即得目标字符。
        buffer.writeCharCode(0x2800 + bits);
      }
      buffer.write('\n');
    }
    return buffer.toString();
  }
}
