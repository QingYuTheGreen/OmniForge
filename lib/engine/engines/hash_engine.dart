import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;

import '../common/binary_io.dart';
import '../engine_utils.dart';
import '../i_engine.dart';

/// 哈希 / 编码引擎：把任意文件转成 md5 / sha / crc32 / base64 结果文件。
class HashEngine extends SimpleEngine {
  const HashEngine();

  @override
  String get id => 'hash';

  @override
  Future<void> execute(EngineContext context) async {
    final bytes = await readFileBytes(context.inputPath);
    final target = context.targetFormat.toLowerCase();
    final name = p.basename(context.inputPath);

    switch (target) {
      case 'base64':
        await writeFileText(context.outputPath, base64Encode(bytes));
        return;
      case 'md5':
        await writeFileText(
          context.outputPath,
          '${crypto.md5.convert(bytes)}  $name\n',
        );
        return;
      case 'crc':
        final value = _crc32(bytes).toRadixString(16).padLeft(8, '0');
        await writeFileText(context.outputPath, '$value  $name\n');
        return;
      case 'sha':
        final algorithm = stringParam(context, 'algorithm', 'sha256');
        final digest = switch (algorithm.toLowerCase()) {
          'sha1' => crypto.sha1.convert(bytes),
          'sha512' => crypto.sha512.convert(bytes),
          _ => crypto.sha256.convert(bytes),
        };
        await writeFileText(context.outputPath, '$digest  $name\n');
        return;
      default:
        throw EngineException('哈希引擎不支持输出格式：$target');
    }
  }

  static int _crc32(List<int> bytes) {
    var crc = 0xFFFFFFFF;
    for (final byte in bytes) {
      crc ^= byte & 0xFF;
      for (var i = 0; i < 8; i++) {
        final mask = -(crc & 1);
        crc = (crc >> 1) ^ (0xEDB88320 & mask);
      }
    }
    return (~crc) & 0xFFFFFFFF;
  }
}

/// 供其它引擎复用：把字节转成十六进制字符串。
String hexOf(List<int> bytes) => toHex(bytes);

/// 供其它引擎复用：判断字节是否基本是文本。
bool looksLikeText(Uint8List bytes, {int limit = 4096}) {
  final end = bytes.length < limit ? bytes.length : limit;
  for (var i = 0; i < end; i++) {
    final b = bytes[i];
    if (b == 0) return false;
    if (b < 7 || (b > 13 && b < 32)) return false;
  }
  return true;
}
