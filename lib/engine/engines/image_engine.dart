import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../engine_utils.dart';
import '../i_engine.dart';

/// 图片引擎：基于纯 Dart 的 image 包，支持 jpg / png / webp / bmp /
/// tiff / ico / gif / tga 之间的互转，以及缩放、质量参数。
class ImageEngine extends SimpleEngine {
  const ImageEngine();

  @override
  String get id => 'image';

  @override
  void validate(EngineContext context) {
    final source = inputExtension(context);
    if (_decoders.contains(source) == false) {
      throw EngineException('暂不支持读取该图片格式：$source');
    }
  }

  static const _decoders = {
    'jpg',
    'jpeg',
    'jpe',
    'jfif',
    'png',
    'apng',
    'gif',
    'bmp',
    'dib',
    'tiff',
    'tif',
    'ico',
    'webp',
    'tga',
    'psd',
    'pvr',
    'exr',
  };

  static const _encoders = {
    'jpg',
    'jpeg',
    'png',
    'gif',
    'bmp',
    'tiff',
    'tif',
    'ico',
    'webp',
    'tga',
  };

  @override
  Future<void> execute(EngineContext context) async {
    final bytes = await readFileBytes(context.inputPath);
    var image = img.decodeImage(bytes);
    if (image == null) {
      throw const EngineException('无法解码输入图片');
    }

    // 等比缩放：宽高任一为 0 时按比例推算
    final targetWidth = intParam(context, 'width', 0);
    final targetHeight = intParam(context, 'height', 0);
    if (targetWidth > 0 || targetHeight > 0) {
      var width = targetWidth;
      var height = targetHeight;
      if (width <= 0) {
        width = (image.width * height / image.height).round();
      } else if (height <= 0) {
        height = (image.height * width / image.width).round();
      }
      width = width.clamp(1, 20000);
      height = height.clamp(1, 20000);
      image = img.copyResize(
        image,
        width: width,
        height: height,
        interpolation: img.Interpolation.cubic,
      );
    }

    final quality = intParam(context, 'quality', 90).clamp(1, 100);
    final target = context.targetFormat.toLowerCase();
    if (!_encoders.contains(target)) {
      throw EngineException('暂不支持导出该图片格式：$target');
    }

    // 透明通道目标不支持时铺白底，避免出现黑块
    if (target == 'jpg' || target == 'jpeg' || target == 'bmp') {
      image = _flattenOnWhite(image);
    }

    final encoded = _encode(image, target, quality);
    if (encoded == null) {
      throw EngineException('编码图片失败：$target');
    }
    await writeFileBytes(context.outputPath, encoded);
  }

  img.Image _flattenOnWhite(img.Image image) {
    if (!image.hasAlpha) return image;
    final canvas = img.Image(
      width: image.width,
      height: image.height,
      numChannels: 3,
    );
    img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(canvas, image);
    return canvas;
  }

  Uint8List? _encode(img.Image image, String format, int quality) {
    switch (format) {
      case 'jpg':
      case 'jpeg':
        return img.encodeJpg(image, quality: quality);
      case 'png':
        return img.encodePng(image, level: 6);
      case 'gif':
        return img.encodeGif(image);
      case 'bmp':
        return img.encodeBmp(image);
      case 'tiff':
      case 'tif':
        return img.encodeTiff(image);
      case 'ico':
        return img.encodeIco(image);
      case 'webp':
        return img.encodeWebP(image, quality: quality);
      case 'tga':
        return img.encodeTga(image);
      default:
        return null;
    }
  }
}
