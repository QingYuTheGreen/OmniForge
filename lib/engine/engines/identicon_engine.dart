

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;

import '../engine_utils.dart';
import '../i_engine.dart';

/// Identicon 引擎：任意文件 → GitHub 风格 5×5 对称图标（PNG）。
///
/// 用文件内容的 MD5 摘要：
/// - 摘要前 15 字节决定 5×5 网格左半 3 列的明暗（镜像出右半）；
/// - 摘要末尾字节换算 HSL 色相，得到填充色；
/// - 背景默认白色。
///
/// 必选参数：
/// - `size`       int    输出边长像素，默认 420
/// - `margin`     int    四周留白像素，默认 40
/// - `background` String 背景色 hex，默认 `#ffffff`
class IdenticonEngine extends SimpleEngine {
  const IdenticonEngine();

  @override
  String get id => 'identicon';

  @override
  Future<void> execute(EngineContext context) async {
    final bytes = await readFileBytes(context.inputPath);
    final digest = md5.convert(bytes).bytes;
    if (digest.length < 15) {
      throw const EngineException('MD5 摘要长度异常，无法生成 identicon');
    }

    final size = intParam(context, 'size', 420).clamp(64, 2048);
    final margin =
        intParam(context, 'margin', 40).clamp(0, size ~/ 2 - 1);
    final background =
        _parseHex(stringParam(context, 'background', '#ffffff'), 0xFFFFFF);

    // 色相取摘要最后两字节，饱和/亮度固定，保证颜色鲜艳可辨。
    final hue = ((digest[14] << 8) | digest[15]) / 65535.0 * 360.0;
    final fill = _hslToRgb(hue, 0.65, 0.45);

    final image = img.Image(width: size, height: size, numChannels: 3);
    img.fill(image, color: _rgb(background));

    final usable = size - margin * 2;
    final cell = usable / 5.0;
    final fillColor = _rgb(fill);

    for (var row = 0; row < 5; row++) {
      for (var col = 0; col < 5; col++) {
        // 左半 3 列由摘要决定，右半镜像。
        final sourceCol = col < 3 ? col : 4 - col;
        final bit = digest[row * 3 + sourceCol] & 1;
        if (bit == 0) continue;
        final x1 = margin + (col * cell).round();
        final y1 = margin + (row * cell).round();
        final x2 = margin + ((col + 1) * cell).round() - 1;
        final y2 = margin + ((row + 1) * cell).round() - 1;
        img.fillRect(
          image,
          x1: x1,
          y1: y1,
          x2: x2,
          y2: y2,
          color: fillColor,
        );
      }
    }

    await writeFileBytes(context.outputPath, img.encodePng(image, level: 6));
  }

  static int _parseHex(String value, int fallback) {
    var text = value.trim().replaceFirst('#', '');
    if (text.length == 3) {
      text = text.split('').map((c) => '$c$c').join();
    }
    if (text.length != 6) return fallback;
    final parsed = int.tryParse(text, radix: 16);
    return parsed ?? fallback;
  }

  static img.ColorRgb8 _rgb(int value) => img.ColorRgb8(
        (value >> 16) & 0xFF,
        (value >> 8) & 0xFF,
        value & 0xFF,
      );

  /// HSL(0..360, 0..1, 0..1) → 0xRRGGBB。
  static int _hslToRgb(double hue, double saturation, double lightness) {
    if (saturation == 0) {
      final gray = (lightness * 255).round().clamp(0, 255);
      return (gray << 16) | (gray << 8) | gray;
    }
    final chroma =
        (1 - (2 * lightness - 1).abs()) * saturation;
    final hp = hue / 60.0;
    final x = chroma * (1 - (hp % 2 - 1).abs());
    double r = 0;
    double g = 0;
    double b = 0;
    if (hp < 1) {
      r = chroma;
      g = x;
    } else if (hp < 2) {
      r = x;
      g = chroma;
    } else if (hp < 3) {
      g = chroma;
      b = x;
    } else if (hp < 4) {
      g = x;
      b = chroma;
    } else if (hp < 5) {
      r = x;
      b = chroma;
    } else {
      r = chroma;
      b = x;
    }
    final m = lightness - chroma / 2;
    int channel(double value) =>
        ((value + m) * 255).round().clamp(0, 255);
    return (channel(r) << 16) | (channel(g) << 8) | channel(b);
  }
}
