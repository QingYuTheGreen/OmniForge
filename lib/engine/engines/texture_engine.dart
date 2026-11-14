import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../engine_utils.dart';
import '../i_engine.dart';

/// 纹理引擎：DDS / KTX / TGA → 通用图片，以及图片 → DDS / TGA。
///
/// 支持 DDS 的 DXT1 / DXT3 / DXT5 / 未压缩 RGB(A)，
/// KTX 的 DXT1 / DXT5 / 未压缩 RGBA8；其它压缩格式（ASTC / XNB）需要插件。
class TextureEngine extends SimpleEngine {
  const TextureEngine();

  @override
  String get id => 'texture';

  @override
  Future<void> execute(EngineContext context) async {
    final source = inputExtension(context);
    final bytes = await readFileBytes(context.inputPath);
    final hasAlpha = boolParam(context, 'alpha', true);

    img.Image? image;
    switch (source) {
      case 'dds':
        image = _decodeDds(bytes);
      case 'ktx' || 'ktx2':
        image = _decodeKtx(bytes);
      case 'tga':
        image = img.decodeTga(bytes);
      case 'png' || 'jpg' || 'jpeg' || 'webp' || 'bmp' || 'gif' || 'tiff':
        image = img.decodeImage(bytes);
      default:
        throw EngineException('暂不支持读取该纹理格式：$source');
    }
    if (image == null) {
      throw const EngineException('纹理解码失败（压缩格式可能不受支持）');
    }

    final target = context.targetFormat.toLowerCase();
    final quality = intParam(context, 'quality', 90).clamp(1, 100);
    Uint8List? encoded;
    switch (target) {
      case 'png':
        encoded = img.encodePng(image);
      case 'jpg' || 'jpeg':
        encoded = img.encodeJpg(
          hasAlpha ? image : _flatten(image),
          quality: quality,
        );
      case 'webp':
        encoded = img.encodeWebP(image, quality: quality);
      case 'bmp':
        encoded = img.encodeBmp(image);
      case 'tga':
        encoded = img.encodeTga(image);
      case 'dds':
        encoded = _encodeDdsUncompressed(image);
      default:
        throw EngineException('纹理引擎不支持输出格式：$target');
    }
    await writeFileBytes(context.outputPath, encoded);
  }

  img.Image _flatten(img.Image image) {
    final canvas = img.Image(
      width: image.width,
      height: image.height,
      numChannels: image.numChannels >= 3 ? 3 : image.numChannels,
    );
    img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(canvas, image);
    return canvas;
  }

  // ─────────────────────────── DDS ───────────────────────────

  img.Image? _decodeDds(Uint8List bytes) {
    if (bytes.length < 128) return null;
    final magic = String.fromCharCodes(bytes.sublist(0, 4));
    if (magic != 'DDS ') return null;
    final data = ByteData.sublistView(bytes);
    final height = data.getUint32(12, Endian.little);
    final width = data.getUint32(16, Endian.little);
    if (width == 0 || height == 0) return null;

    // pixel format 在偏移 76
    final fourCC = String.fromCharCodes(bytes.sublist(84, 88));
    final bitCount = data.getUint32(88, Endian.little);
    final redMask = data.getUint32(92, Endian.little);
    final greenMask = data.getUint32(96, Endian.little);
    final blueMask = data.getUint32(100, Endian.little);
    final alphaMask = data.getUint32(104, Endian.little);
    final payload = bytes.sublist(128);

    switch (fourCC) {
      case 'DXT1':
        return _decodeDxt(payload, width, height, dxt5: false);
      case 'DXT3':
      case 'DXT5':
        return _decodeDxt(payload, width, height, dxt5: true);
      case 'ATI2':
      case 'BC5U':
        throw const EngineException('DDS 使用 BC5 压缩，需要纹理插件支持');
      default:
        break;
    }
    if (bitCount == 32) {
      return _decodeMasks(payload, width, height, redMask, greenMask, blueMask,
          alphaMask, 4);
    }
    if (bitCount == 24) {
      return _decodeMasks(payload, width, height, redMask, greenMask, blueMask,
          0, 3);
    }
    throw const EngineException('不支持的 DDS 像素格式（需要纹理插件）');
  }

  img.Image _decodeMasks(
    Uint8List payload,
    int width,
    int height,
    int redMask,
    int greenMask,
    int blueMask,
    int alphaMask,
    int bytesPerPixel,
  ) {
    final image = img.Image(width: width, height: height, numChannels: 4);
    final redShift = _maskShift(redMask);
    final greenShift = _maskShift(greenMask);
    final blueShift = _maskShift(blueMask);
    final alphaShift = alphaMask == 0 ? 0 : _maskShift(alphaMask);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final offset = (y * width + x) * bytesPerPixel;
        if (offset + bytesPerPixel > payload.length) {
          return image;
        }
        var value = 0;
        for (var i = 0; i < bytesPerPixel; i++) {
          value |= payload[offset + i] << (8 * i);
        }
        final r = redMask == 0 ? 0 : (value & redMask) >> redShift;
        final g = greenMask == 0 ? 0 : (value & greenMask) >> greenShift;
        final b = blueMask == 0 ? 0 : (value & blueMask) >> blueShift;
        final a = alphaMask == 0 ? 255 : (value & alphaMask) >> alphaShift;
        image.setPixelRgba(x, y, r, g, b, a);
      }
    }
    return image;
  }

  int _maskShift(int mask) {
    if (mask == 0) return 0;
    var shift = 0;
    while ((mask & 1) == 0) {
      mask >>= 1;
      shift++;
    }
    return shift;
  }

  img.Image? _decodeDxt(
    Uint8List payload,
    int width,
    int height, {
    required bool dxt5,
  }) {
    final image = img.Image(width: width, height: height, numChannels: 4);
    final blockSize = dxt5 ? 16 : 8;
    final blockWidth = (width + 3) ~/ 4;
    final blockHeight = (height + 3) ~/ 4;
    final data = ByteData.sublistView(payload);
    var offset = 0;
    for (var by = 0; by < blockHeight; by++) {
      for (var bx = 0; bx < blockWidth; bx++) {
        if (offset + blockSize > payload.length) break;
        var alpha0 = 255;
        var alpha1 = 255;
        final alphas = List<int>.filled(16, 255);
        if (dxt5) {
          alpha0 = payload[offset];
          alpha1 = payload[offset + 1];
          final bits = data.getUint32(offset + 2, Endian.little);
          final bitsHigh = data.getUint16(offset + 6, Endian.little);
          for (var i = 0; i < 16; i++) {
            final index = i < 8
                ? (bits >> (i * 4)) & 0x7
                : (bitsHigh >> ((i - 8) * 4)) & 0x7;
            alphas[i] = _dxtAlpha(alpha0, alpha1, index);
          }
          offset += 8;
        }
        final color0 = data.getUint16(offset, Endian.little);
        final color1 = data.getUint16(offset + 2, Endian.little);
        final indices = data.getUint32(offset + 4, Endian.little);
        offset += 8;

        final colors = _dxtColors(color0, color1, alpha: !dxt5);
        for (var i = 0; i < 16; i++) {
          final x = bx * 4 + (i % 4);
          final y = by * 4 + (i ~/ 4);
          if (x >= width || y >= height) continue;
          final index = (indices >> (i * 2)) & 0x3;
          final color = colors[index];
          final alpha = alphas[i];
          image.setPixelRgba(
            x,
            y,
            color.$1,
            color.$2,
            color.$3,
            dxt5 ? alpha : color.$4,
          );
        }
      }
    }
    return image;
  }

  int _dxtAlpha(int a0, int a1, int index) {
    if (index == 0) return a0;
    if (index == 1) return a1;
    if (a0 > a1) {
      return ((a0 * (8 - index) + a1 * (index - 1)) / 7).round();
    }
    if (index == 6) return 0;
    if (index == 7) return 255;
    return ((a0 * (6 - index) + a1 * (index - 1)) / 5).round();
  }

  List<(int, int, int, int)> _dxtColors(
    int c0,
    int c1, {
    required bool alpha,
  }) {
    final r0 = ((c0 >> 11) & 0x1F) * 255 ~/ 31;
    final g0 = ((c0 >> 5) & 0x3F) * 255 ~/ 63;
    final b0 = (c0 & 0x1F) * 255 ~/ 31;
    final r1 = ((c1 >> 11) & 0x1F) * 255 ~/ 31;
    final g1 = ((c1 >> 5) & 0x3F) * 255 ~/ 63;
    final b1 = (c1 & 0x1F) * 255 ~/ 31;
    if (alpha && c0 > c1) {
      return [
        (r0, g0, b0, 255),
        (r1, g1, b1, 255),
        ((2 * r0 + r1) ~/ 3, (2 * g0 + g1) ~/ 3, (2 * b0 + b1) ~/ 3, 255),
        ((r0 + 2 * r1) ~/ 3, (g0 + 2 * g1) ~/ 3, (b0 + 2 * b1) ~/ 3, 255),
      ];
    }
    return [
      (r0, g0, b0, 255),
      (r1, g1, b1, 255),
      ((r0 + r1) ~/ 2, (g0 + g1) ~/ 2, (b0 + b1) ~/ 2, 255),
      (0, 0, 0, alpha ? 0 : 255),
    ];
  }

  Uint8List _encodeDdsUncompressed(img.Image image) {
    final header = ByteData(128);
    void writeAscii(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        header.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    writeAscii(0, 'DDS ');
    header.setUint32(4, 124, Endian.little);
    header.setUint32(8, 0x1 | 0x2 | 0x4 | 0x1000, Endian.little); // caps, h, w, pitch
    header.setUint32(12, image.height, Endian.little);
    header.setUint32(16, image.width, Endian.little);
    header.setUint32(20, image.width * 4, Endian.little);
    header.setUint32(76, 32, Endian.little); // pixel format size
    header.setUint32(80, 0x41, Endian.little); // RGB | ALPHAPIXELS
    writeAscii(84, '\x00\x00\x00\x00');
    header.setUint32(88, 32, Endian.little);
    header.setUint32(92, 0x00FF0000, Endian.little);
    header.setUint32(96, 0x0000FF00, Endian.little);
    header.setUint32(100, 0x000000FF, Endian.little);
    header.setUint32(104, 0xFF000000, Endian.little);
    header.setUint32(108, 0x1000, Endian.little); // DDPF_ALPHAPIXELS? 保持在 caps

    final payload = Uint8List(image.width * image.height * 4);
    var offset = 0;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        payload[offset++] = pixel.b.toInt();
        payload[offset++] = pixel.g.toInt();
        payload[offset++] = pixel.r.toInt();
        payload[offset++] = pixel.a.toInt();
      }
    }
    final out = BytesBuilder()
      ..add(header.buffer.asUint8List())
      ..add(payload);
    return out.toBytes();
  }

  // ─────────────────────────── KTX ───────────────────────────

  img.Image? _decodeKtx(Uint8List bytes) {
    if (bytes.length < 64) return null;
    final identifier = [
      0xAB, 0x4B, 0x54, 0x58, 0x20, 0x31, 0x31, 0xBB, 0x0D, 0x0A, 0x1A, 0x0A,
    ];
    for (var i = 0; i < identifier.length; i++) {
      if (bytes[i] != identifier[i]) return null;
    }
    final data = ByteData.sublistView(bytes);
    final internalFormat = data.getUint32(28, Endian.little);
    final width = data.getUint32(36, Endian.little);
    final height = data.getUint32(40, Endian.little);
    final kvBytes = data.getUint32(60, Endian.little);
    final payloadStart = 64 + kvBytes;
    if (payloadStart + 4 > bytes.length) return null;
    final imageSize = data.getUint32(payloadStart, Endian.little);
    final payload = bytes.sublist(payloadStart + 4);
    final payloadLimited = imageSize > 0 && imageSize <= payload.length
        ? payload.sublist(0, imageSize)
        : payload;

    switch (internalFormat) {
      case 0x8D64: // GL_ETC1_RGB8_OES
        throw const EngineException('KTX 使用 ETC1 压缩，需要纹理插件支持');
      case 0x83F1: // DXT1
        return _decodeDxt(payloadLimited, width, height, dxt5: false);
      case 0x83F3: // DXT5
        return _decodeDxt(payloadLimited, width, height, dxt5: true);
      default:
        break;
    }
    if (internalFormat == 0x8058 || internalFormat == 0x1908) {
      // RGBA8
      return _decodeMasks(
        payloadLimited,
        width,
        height,
        0x000000FF,
        0x0000FF00,
        0x00FF0000,
        0xFF000000,
        4,
      );
    }
    if (internalFormat == 0x8051 || internalFormat == 0x1907) {
      return _decodeMasks(
        payloadLimited,
        width,
        height,
        0x000000FF,
        0x0000FF00,
        0x00FF0000,
        0,
        3,
      );
    }
    throw EngineException(
      '不支持的 KTX 内部格式：0x${internalFormat.toRadixString(16)}',
    );
  }
}
