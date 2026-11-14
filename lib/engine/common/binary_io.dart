/// 统一的二进制读写工具库。
///
/// 纹理（DDS/KTX）、调色板（ASE/ACO）、哈希输出等格式都直接操作字节，
/// 各引擎不再各自实现 readUint16 / writeUint32 之类的样板代码。
library;

import 'dart:typed_data';

const String _hexDigits = '0123456789abcdef';

/// 小端字节序读取器。
class ByteReader {
  ByteReader(this.bytes);

  final Uint8List bytes;
  int offset = 0;

  int get remaining => bytes.length - offset;

  bool get isEOF => offset >= bytes.length;

  void skip(int count) => offset += count;

  int u8() => bytes[offset++];

  int u16le() {
    final value = bytes[offset] | (bytes[offset + 1] << 8);
    offset += 2;
    return value;
  }

  int u16be() {
    final value = (bytes[offset] << 8) | bytes[offset + 1];
    offset += 2;
    return value;
  }

  int u32le() {
    final value = bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);
    offset += 4;
    return value & 0xFFFFFFFF;
  }

  int u32be() {
    final value = (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
    offset += 4;
    return value & 0xFFFFFFFF;
  }

  double f32le() {
    final data = ByteData.sublistView(bytes, offset, offset + 4);
    offset += 4;
    return data.getFloat32(0, Endian.little);
  }

  Uint8List take(int count) {
    final data = bytes.sublist(offset, offset + count);
    offset += count;
    return data;
  }

  /// UTF-16BE 字符串（ASE 使用）。
  String utf16be(int codeUnitCount) {
    final buffer = StringBuffer();
    for (var i = 0; i < codeUnitCount; i++) {
      buffer.writeCharCode(u16be());
    }
    return buffer.toString();
  }
}

/// 小端字节序写入器。
class ByteWriter {
  final BytesBuilder _builder = BytesBuilder(copy: false);

  int get length => _builder.length;

  void u8(int value) => _builder.addByte(value & 0xFF);

  void u16le(int value) {
    _builder.addByte(value & 0xFF);
    _builder.addByte((value >> 8) & 0xFF);
  }

  void u32le(int value) {
    _builder.addByte(value & 0xFF);
    _builder.addByte((value >> 8) & 0xFF);
    _builder.addByte((value >> 16) & 0xFF);
    _builder.addByte((value >> 24) & 0xFF);
  }

  void f32le(double value) {
    final data = ByteData(4)..setFloat32(0, value, Endian.little);
    _builder.add(data.buffer.asUint8List());
  }

  void ascii(String text) => _builder.add(text.codeUnits);

  void utf16be(String text) {
    for (final codeUnit in text.codeUnits) {
      _builder.addByte((codeUnit >> 8) & 0xFF);
      _builder.addByte(codeUnit & 0xFF);
    }
  }

  void bytes(List<int> data) => _builder.add(data);

  Uint8List toBytes() => _builder.toBytes();
}

/// 字节数组转小写十六进制字符串。
String toHex(List<int> bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer
      ..write(_hexDigits[(byte >> 4) & 0x0F])
      ..write(_hexDigits[byte & 0x0F]);
  }
  return buffer.toString();
}

/// 十六进制字符串转字节数组（忽略大小写和空白）。
Uint8List fromHex(String text) {
  final cleaned = text.replaceAll(RegExp(r'\s'), '');
  final result = Uint8List(cleaned.length ~/ 2);
  for (var i = 0; i < result.length; i++) {
    result[i] = int.parse(cleaned.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return result;
}
