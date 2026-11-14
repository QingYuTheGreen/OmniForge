import 'dart:io';
import 'dart:typed_data';

import '../common/binary_io.dart';
import '../engine_utils.dart';
import '../i_engine.dart';

/// 字体引擎：ttf / otf ↔ woff（WOFF1）纯 Dart 互转。
///
/// - `woff → ttf / otf`：解压每张表，按 sfnt 规范重建表目录与 4 字节对齐数据。
/// - `ttf / otf → woff`：按表 zlib 压缩，生成 44 字节 WOFF 头 + 20 字节表目录。
/// - `woff2` 需要 brotli 解码，属于可选插件能力，转换时返回 [PluginRequiredException]。
class FontEngine extends SimpleEngine {
  const FontEngine();

  @override
  String get id => 'font';

  @override
  Future<void> execute(EngineContext context) async {
    final bytes = await readFileBytes(context.inputPath);
    final target = context.targetFormat.toLowerCase();
    final source = _detectSource(bytes);
    switch (source) {
      case 'woff2':
        throw const PluginRequiredException('font-woff2', 6);
      case 'woff':
        if (target != 'ttf' && target != 'otf') {
          throw EngineException(
            'woff 仅支持转换为 ttf / otf，当前目标格式：$target',
          );
        }
        final sfnt = _woffToSfnt(bytes);
        _validateSfnt(sfnt);
        await writeFileBytes(context.outputPath, sfnt);
      case 'sfnt':
        if (target != 'woff') {
          throw EngineException(
            '字体引擎支持 ttf/otf → woff 与 woff → ttf/otf，当前目标格式：$target',
          );
        }
        final tableCount = _parseSfnt(bytes).tables.length;
        final woff = _sfntToWoff(bytes);
        _validateWoff(woff, tableCount);
        await writeFileBytes(context.outputPath, woff);
      default:
        throw const EngineException(
          '无法识别的字体格式：仅支持 ttf / otf / woff（woff2 需要字体插件）',
        );
    }
  }

  String _detectSource(Uint8List bytes) {
    if (bytes.length < 4) return 'unknown';
    final magic = String.fromCharCodes(bytes.sublist(0, 4));
    if (magic == 'wOF2') return 'woff2';
    if (magic == 'wOFF') return 'woff';
    if (magic == 'OTTO' || magic == 'true' || magic == 'typ1') return 'sfnt';
    final version = ByteReader(bytes).u32be();
    if (version == 0x00010000 || version == 0x00020000) return 'sfnt';
    return 'unknown';
  }

  // ─────────────────────────── WOFF → sfnt ───────────────────────────

  Uint8List _woffToSfnt(Uint8List bytes) {
    final font = _parseWoff(bytes);
    final tables = <_SfntTableData>[];
    for (final table in font.tables) {
      if (table.offset + table.compLength > bytes.length) {
        throw EngineException('WOFF 字体表 ${table.tag} 数据越界，文件可能已损坏');
      }
      var data = Uint8List.sublistView(
        bytes,
        table.offset,
        table.offset + table.compLength,
      );
      if (table.compLength < table.origLength) {
        try {
          data = Uint8List.fromList(ZLibDecoder().convert(data));
        } catch (_) {
          throw EngineException('WOFF 字体表 ${table.tag} 解压失败，文件可能已损坏');
        }
      } else if (table.compLength > table.origLength) {
        throw EngineException('WOFF 字体表 ${table.tag} 压缩长度异常');
      }
      if (data.length != table.origLength) {
        throw EngineException(
          'WOFF 字体表 ${table.tag} 解压后长度不符'
          '（期望 ${table.origLength}，实际 ${data.length}）',
        );
      }
      tables.add(_SfntTableData(table.tag, Uint8List.fromList(data)));
    }
    tables.sort((left, right) => left.tag.compareTo(right.tag));
    return _buildSfnt(font.flavor, tables);
  }

  Uint8List _buildSfnt(int flavor, List<_SfntTableData> tables) {
    final count = tables.length;
    if (count == 0) {
      throw const EngineException('WOFF 字体中没有可重建的数据表');
    }
    final headerSize = 12 + count * 16;
    final offsets = <int>[];
    var cursor = headerSize;
    for (final table in tables) {
      offsets.add(cursor);
      cursor += _pad4(table.data.length);
    }
    final total = cursor;
    final out = Uint8List(total);
    final view = ByteData.sublistView(out);

    var entrySelector = 0;
    while ((1 << (entrySelector + 1)) <= count) {
      entrySelector++;
    }
    final searchRange = (1 << entrySelector) * 16;

    view.setUint32(0, flavor);
    view.setUint16(4, count);
    view.setUint16(6, searchRange);
    view.setUint16(8, entrySelector);
    view.setUint16(10, count * 16 - searchRange);

    var headOffset = -1;
    for (var i = 0; i < count; i++) {
      final table = tables[i];
      final directoryOffset = 12 + i * 16;
      _writeTag(view, directoryOffset, table.tag);
      var data = table.data;
      if (table.tag == 'head' && data.length >= 12) {
        data = Uint8List.fromList(data);
        // 先清零 checkSumAdjustment 再计算表校验和
        data[8] = 0;
        data[9] = 0;
        data[10] = 0;
        data[11] = 0;
        headOffset = offsets[i];
      }
      view.setUint32(directoryOffset + 4, _checksum(data));
      view.setUint32(directoryOffset + 8, offsets[i]);
      view.setUint32(directoryOffset + 12, data.length);
      out.setRange(offsets[i], offsets[i] + data.length, data);
    }

    if (headOffset >= 0) {
      final fontChecksum = _checksum(out);
      final adjustment = (0xB1B0AFBA - fontChecksum) & 0xFFFFFFFF;
      view.setUint32(headOffset + 8, adjustment);
    }
    return out;
  }

  // ─────────────────────────── sfnt → WOFF ───────────────────────────

  Uint8List _sfntToWoff(Uint8List bytes) {
    final font = _parseSfnt(bytes);
    if (font.tables.isEmpty) {
      throw const EngineException('字体中没有数据表，无法转换为 WOFF');
    }
    final sorted = [...font.tables]
      ..sort((left, right) => left.tag.compareTo(right.tag));

    final entries = <_WoffEntry>[];
    for (final table in sorted) {
      final data = Uint8List.sublistView(
        bytes,
        table.offset,
        table.offset + table.length,
      );
      final compressed = Uint8List.fromList(ZLibEncoder(level: 9).convert(data));
      if (compressed.length < data.length) {
        entries.add(_WoffEntry(table.tag, compressed, data.length, table.checksum));
      } else {
        // 压缩没有收益时按 WOFF 规范存原始数据（compLength == origLength）
        entries.add(_WoffEntry(table.tag, data, data.length, table.checksum));
      }
    }

    final count = entries.length;
    final headerSize = 44 + count * 20;
    final offsets = <int>[];
    var cursor = headerSize;
    for (final entry in entries) {
      offsets.add(cursor);
      cursor += _pad4(entry.compressed.length);
    }
    final totalLength = cursor;
    final totalSfntSize =
        12 + count * 16 + entries.fold<int>(0, (sum, entry) => sum + _pad4(entry.origLength));

    var major = 1;
    var minor = 0;
    for (final table in font.tables) {
      if (table.tag != 'head' || table.length < 8) continue;
      final revision = ByteReader(
        bytes.sublist(table.offset, table.offset + table.length),
      )..skip(4);
      final value = revision.u32be();
      major = (value >> 16) & 0xFFFF;
      minor = value & 0xFFFF;
      break;
    }

    final out = Uint8List(totalLength);
    final view = ByteData.sublistView(out);
    view.setUint32(0, 0x774F4646); // 'wOFF'
    view.setUint32(4, font.version);
    view.setUint32(8, totalLength);
    view.setUint16(12, count);
    view.setUint16(14, 0); // reserved
    view.setUint32(16, totalSfntSize);
    view.setUint16(20, major);
    view.setUint16(22, minor);
    // meta / priv 区域留空（offset / length 均为 0）

    for (var i = 0; i < count; i++) {
      final entry = entries[i];
      final directoryOffset = 44 + i * 20;
      _writeTag(view, directoryOffset, entry.tag);
      view.setUint32(directoryOffset + 4, offsets[i]);
      view.setUint32(directoryOffset + 8, entry.compressed.length);
      view.setUint32(directoryOffset + 12, entry.origLength);
      view.setUint32(directoryOffset + 16, entry.checksum);
      out.setRange(
        offsets[i],
        offsets[i] + entry.compressed.length,
        entry.compressed,
      );
    }
    return out;
  }

  // ─────────────────────────── 解析 ───────────────────────────

  _WoffFont _parseWoff(Uint8List bytes) {
    if (bytes.length < 44) {
      throw const EngineException('不是有效的 WOFF 字体：文件长度不足');
    }
    final reader = ByteReader(bytes);
    if (String.fromCharCodes(reader.take(4)) != 'wOFF') {
      throw const EngineException('不是有效的 WOFF1 字体：魔数不是 wOFF');
    }
    final flavor = reader.u32be();
    final length = reader.u32be();
    final numTables = reader.u16be();
    reader.u16be(); // reserved
    reader.u32be(); // totalSfntSize（重建时按表实际长度计算）
    reader.u16be(); // majorVersion
    reader.u16be(); // minorVersion
    reader.u32be(); // metaOffset
    reader.u32be(); // metaLength
    reader.u32be(); // metaOrigLength
    reader.u32be(); // privOffset
    reader.u32be(); // privLength

    if (numTables == 0) {
      throw const EngineException('WOFF 字体表数量为 0，文件可能已损坏');
    }
    if (length != bytes.length) {
      throw EngineException(
        'WOFF 头部记录的长度 $length 与实际文件长度 ${bytes.length} 不一致',
      );
    }
    if (44 + numTables * 20 > bytes.length) {
      throw const EngineException('WOFF 表目录越界，文件可能已损坏');
    }
    final tables = <_WoffTable>[];
    for (var i = 0; i < numTables; i++) {
      final tag = String.fromCharCodes(reader.take(4));
      final offset = reader.u32be();
      final compLength = reader.u32be();
      final origLength = reader.u32be();
      reader.u32be(); // origChecksum（重建 sfnt 时重新计算）
      tables.add(
        _WoffTable(tag, offset, compLength, origLength),
      );
    }
    return _WoffFont(flavor, numTables, tables);
  }

  _SfntFont _parseSfnt(Uint8List bytes) {
    if (bytes.length < 12) {
      throw const EngineException('不是有效的字体文件：文件长度不足');
    }
    final reader = ByteReader(bytes);
    final version = reader.u32be();
    final numTables = reader.u16be();
    reader.u16be(); // searchRange
    reader.u16be(); // entrySelector
    reader.u16be(); // rangeShift
    if (numTables == 0) {
      throw const EngineException('字体表数量为 0，文件可能已损坏');
    }
    if (12 + numTables * 16 > bytes.length) {
      throw const EngineException('字体表目录越界，文件可能已损坏');
    }
    final tables = <_SfntTable>[];
    for (var i = 0; i < numTables; i++) {
      final tag = String.fromCharCodes(reader.take(4));
      final checksum = reader.u32be();
      final offset = reader.u32be();
      final length = reader.u32be();
      if (offset + length > bytes.length) {
        throw EngineException('字体表 $tag 数据越界，文件可能已损坏');
      }
      tables.add(_SfntTable(tag, checksum, offset, length));
    }
    return _SfntFont(version, tables);
  }

  // ─────────────────────────── 校验 ───────────────────────────

  void _validateSfnt(Uint8List bytes) {
    final font = _parseSfnt(bytes);
    if (font.tables.isEmpty) {
      throw const EngineException('重建后的字体没有数据表');
    }
  }

  void _validateWoff(Uint8List bytes, int expectedTables) {
    final font = _parseWoff(bytes);
    if (font.numTables != expectedTables) {
      throw EngineException(
        'WOFF 表数量不一致（期望 $expectedTables，实际 ${font.numTables}）',
      );
    }
  }

  // ─────────────────────────── 工具 ───────────────────────────

  int _pad4(int length) => (length + 3) & ~3;

  void _writeTag(ByteData view, int offset, String tag) {
    for (var i = 0; i < 4; i++) {
      view.setUint8(offset + i, i < tag.length ? tag.codeUnitAt(i) : 0x20);
    }
  }

  /// 计算 sfnt 表校验和（按大端 u32 求和，末字补零）。
  int _checksum(Uint8List data) {
    var sum = 0;
    var index = 0;
    while (index + 4 <= data.length) {
      final word = (data[index] << 24) |
          (data[index + 1] << 16) |
          (data[index + 2] << 8) |
          data[index + 3];
      sum = (sum + word) & 0xFFFFFFFF;
      index += 4;
    }
    if (index < data.length) {
      var word = 0;
      for (var i = 0; i < 4; i++) {
        word = (word << 8) | (index + i < data.length ? data[index + i] : 0);
      }
      sum = (sum + word) & 0xFFFFFFFF;
    }
    return sum;
  }
}

// ─────────────────────────── 数据模型 ───────────────────────────

class _WoffTable {
  const _WoffTable(this.tag, this.offset, this.compLength, this.origLength);

  final String tag;
  final int offset;
  final int compLength;
  final int origLength;
}

class _WoffFont {
  const _WoffFont(this.flavor, this.numTables, this.tables);

  final int flavor;
  final int numTables;
  final List<_WoffTable> tables;
}

class _WoffEntry {
  const _WoffEntry(this.tag, this.compressed, this.origLength, this.checksum);

  final String tag;
  final Uint8List compressed;
  final int origLength;
  final int checksum;
}

class _SfntTable {
  const _SfntTable(this.tag, this.checksum, this.offset, this.length);

  final String tag;
  final int checksum;
  final int offset;
  final int length;
}

class _SfntFont {
  const _SfntFont(this.version, this.tables);

  final int version;
  final List<_SfntTable> tables;
}

class _SfntTableData {
  const _SfntTableData(this.tag, this.data);

  final String tag;
  final Uint8List data;
}
