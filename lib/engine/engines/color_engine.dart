import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../engine_utils.dart';
import '../i_engine.dart';

/// 调色板中的一个颜色。
class PaletteColor {
  final int red;
  final int green;
  final int blue;
  final String name;

  const PaletteColor(this.red, this.green, this.blue, {this.name = ''});

  String get hex =>
      '#${red.toRadixString(16).padLeft(2, '0')}'
      '${green.toRadixString(16).padLeft(2, '0')}'
      '${blue.toRadixString(16).padLeft(2, '0')}'.toUpperCase();

  Map<String, dynamic> toJson() => {
        'name': name,
        'hex': hex,
        'rgb': [red, green, blue],
      };
}

/// 调色板引擎：ase / aco / gpl / json 互转（纯 Dart 二进制解析）。
class ColorEngine extends SimpleEngine {
  const ColorEngine();

  @override
  String get id => 'color';

  @override
  Future<void> execute(EngineContext context) async {
    final bytes = await readFileBytes(context.inputPath);
    final ext = inputExtension(context);
    final colors = switch (ext) {
      'ase' => _parseAse(bytes),
      'aco' => _parseAco(bytes),
      'gpl' => _parseGpl(utf8.decode(bytes, allowMalformed: true)),
      'json' => _parseJson(
          utf8.decode(bytes, allowMalformed: true),
        ),
      _ => throw EngineException('不支持的调色板输入格式：$ext'),
    };
    if (colors.isEmpty) {
      throw const EngineException('没有从输入文件里解析到颜色');
    }
    final paletteName = stringParam(context, 'name', inputStem(context));
    final target = context.targetFormat.toLowerCase();
    final out = switch (target) {
      'ase' => _writeAse(colors, paletteName),
      'aco' => _writeAco(colors),
      'gpl' => _writeGpl(colors, paletteName),
      'json' => _writeJson(colors, paletteName),
      _ => throw EngineException('调色板引擎不支持输出格式：$target'),
    };
    await writeFileBytes(context.outputPath, out);
  }

  // ─────────────────────────── ASE ───────────────────────────

  List<PaletteColor> _parseAse(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    if (bytes.length < 12) return const [];
    final magic = String.fromCharCodes(bytes.sublist(0, 4));
    if (magic != 'ASEF') {
      throw const EngineException('不是有效的 ASE 调色板文件');
    }
    final blockCount = data.getUint32(8);
    var offset = 12;
    final colors = <PaletteColor>[];
    for (var i = 0; i < blockCount && offset + 6 <= bytes.length; i++) {
      final type = data.getUint16(offset);
      final length = data.getUint32(offset + 2);
      final blockStart = offset + 6;
      final blockEnd = blockStart + length;
      if (blockEnd > bytes.length) break;
      if (type == 0x0001) {
        final nameLength = data.getUint16(blockStart);
        var cursor = blockStart + 2;
        final nameUnits = <int>[];
        for (var j = 0; j < nameLength && cursor + 1 < blockEnd; j++) {
          nameUnits.add(data.getUint16(cursor));
          cursor += 2;
        }
        final name = String.fromCharCodes(nameUnits).trim();
        cursor = blockStart + 2 + nameLength * 2;
        if (cursor + 4 + 12 <= blockEnd) {
          final model = String.fromCharCodes(
            bytes.sublist(cursor, cursor + 4),
          );
          cursor += 4;
          if (model == 'RGB ') {
            final r = _float01(data, cursor);
            final g = _float01(data, cursor + 4);
            final b = _float01(data, cursor + 8);
            colors.add(PaletteColor(
              (r * 255).round().clamp(0, 255),
              (g * 255).round().clamp(0, 255),
              (b * 255).round().clamp(0, 255),
              name: name,
            ));
          }
        }
      }
      offset = blockEnd;
    }
    return colors;
  }

  double _float01(ByteData data, int offset) =>
      data.getFloat32(offset).clamp(0.0, 1.0);

  Uint8List _writeAse(List<PaletteColor> colors, String name) {
    final payload = BytesBuilder();
    final block = BytesBuilder();
    for (final color in colors) {
      final nameBytes = _utf16Be(color.name.isEmpty ? color.hex : color.name);
      final body = BytesBuilder()
        ..add(_u16(nameBytes.length ~/ 2 + 1))
        ..add(nameBytes)
        ..add(_u16(0))
        ..add(ascii.encode('RGB '))
        ..add(_f32(color.red / 255))
        ..add(_f32(color.green / 255))
        ..add(_f32(color.blue / 255))
        ..add(_u16(0));
      block
        ..add(_u16(0x0001))
        ..add(_u32(body.length))
        ..add(body.toBytes());
    }
    payload
      ..add(ascii.encode('ASEF'))
      ..add(_u16(1))
      ..add(_u16(0))
      ..add(_u32(colors.length))
      ..add(block.toBytes());
    // 组名块（简单写入调色板名）
    final groupName = _utf16Be(name);
    final group = BytesBuilder()
      ..add(_u16(groupName.length ~/ 2 + 1))
      ..add(groupName)
      ..add(_u16(0));
    payload
      ..add(_u16(0xC001))
      ..add(_u32(group.length))
      ..add(group.toBytes());
    return payload.toBytes();
  }

  // ─────────────────────────── ACO ───────────────────────────

  List<PaletteColor> _parseAco(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    if (bytes.length < 4) return const [];
    final version = data.getUint16(0);
    if (version != 1 && version != 2) {
      throw const EngineException('不是有效的 ACO 调色板文件');
    }
    final count = data.getUint16(2);
    var offset = 4;
    final colors = <PaletteColor>[];
    for (var i = 0; i < count && offset + 10 <= bytes.length; i++) {
      final space = data.getUint16(offset);
      final r = data.getUint16(offset + 2) & 0xFF;
      final g = data.getUint16(offset + 4) & 0xFF;
      final b = data.getUint16(offset + 6) & 0xFF;
      if (space == 0) {
        colors.add(PaletteColor(r, g, b));
      } else if (space == 8) {
        // Lab 色彩空间：近似转成 sRGB
        final l = data.getUint16(offset + 2) / 100.0;
        final a = (data.getUint16(offset + 4) - 128) / 128.0;
        final bb = (data.getUint16(offset + 6) - 128) / 128.0;
        colors.add(_labToRgb(l * 100, a * 128, bb * 128));
      }
      offset += 10;
    }
    return colors;
  }

  PaletteColor _labToRgb(double l, double a, double b) {
    final fy = (l + 16) / 116;
    final fx = a / 500 + fy;
    final fz = fy - b / 200;
    double inverse(double t) {
      final cube = t * t * t;
      return cube > 0.008856 ? cube : (t - 16 / 116) / 7.787;
    }

    final x = 0.95047 * inverse(fx);
    final y = 1.0 * inverse(fy);
    final z = 1.08883 * inverse(fz);
    final rr = x * 3.2406 - y * 1.5372 - z * 0.4986;
    final gg = -x * 0.9689 + y * 1.8758 + z * 0.0415;
    final bb = x * 0.0557 - y * 0.2040 + z * 1.0570;
    int channel(double value) {
      final v = value <= 0.0031308
          ? 12.92 * value
          : 1.055 * math.pow(value, 1 / 2.4).toDouble() - 0.055;
      return (v * 255).round().clamp(0, 255);
    }

    return PaletteColor(channel(rr), channel(gg), channel(bb));
  }

  Uint8List _writeAco(List<PaletteColor> colors) {
    final builder = BytesBuilder()
      ..add(_u16(1))
      ..add(_u16(colors.length));
    for (final color in colors) {
      builder
        ..add(_u16(0))
        ..add(_u16(color.red))
        ..add(_u16(color.green))
        ..add(_u16(color.blue))
        ..add(_u16(0));
    }
    return builder.toBytes();
  }

  // ─────────────────────────── GPL ───────────────────────────

  List<PaletteColor> _parseGpl(String content) {
    final colors = <PaletteColor>[];
    for (final rawLine in content.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#') || line.contains(':')) continue;
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length < 3) continue;
      final r = int.tryParse(parts[0]);
      final g = int.tryParse(parts[1]);
      final b = int.tryParse(parts[2]);
      if (r == null || g == null || b == null) continue;
      colors.add(PaletteColor(
        r.clamp(0, 255),
        g.clamp(0, 255),
        b.clamp(0, 255),
        name: parts.length > 3 ? parts.sublist(3).join(' ') : '',
      ));
    }
    return colors;
  }

  Uint8List _writeGpl(List<PaletteColor> colors, String name) {
    final buffer = StringBuffer()
      ..writeln('GIMP Palette')
      ..writeln('Name: $name')
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

  List<PaletteColor> _parseJson(String content) {
    final decoded = jsonDecode(content);
    final colors = <PaletteColor>[];
    void add(Object? node) {
      if (node is String) {
        final parsed = _fromHex(node);
        if (parsed != null) colors.add(parsed);
      } else if (node is Map) {
        final hex = node['hex'] ?? node['color'] ?? node['value'];
        final rgb = node['rgb'];
        if (hex is String) {
          final parsed = _fromHex(hex);
          if (parsed != null) {
            colors.add(PaletteColor(
              parsed.red,
              parsed.green,
              parsed.blue,
              name: node['name']?.toString() ?? '',
            ));
          }
        } else if (rgb is List && rgb.length >= 3) {
          colors.add(PaletteColor(
            (rgb[0] as num).toInt().clamp(0, 255),
            (rgb[1] as num).toInt().clamp(0, 255),
            (rgb[2] as num).toInt().clamp(0, 255),
            name: node['name']?.toString() ?? '',
          ));
        }
      }
    }

    if (decoded is Map) {
      final list = decoded['colors'] ?? decoded['palette'] ?? decoded['data'];
      if (list is List) {
        for (final item in list) {
          add(item);
        }
      }
    } else if (decoded is List) {
      for (final item in decoded) {
        add(item);
      }
    }
    return colors;
  }

  PaletteColor? _fromHex(String value) {
    var hex = value.trim().replaceFirst('#', '');
    if (hex.length == 3) {
      hex = hex.split('').map((c) => '$c$c').join();
    }
    if (hex.length < 6) return null;
    final r = int.tryParse(hex.substring(0, 2), radix: 16);
    final g = int.tryParse(hex.substring(2, 4), radix: 16);
    final b = int.tryParse(hex.substring(4, 6), radix: 16);
    if (r == null || g == null || b == null) return null;
    return PaletteColor(r, g, b);
  }

  Uint8List _writeJson(List<PaletteColor> colors, String name) {
    final data = <String, dynamic>{
      'name': name,
      'colors': colors.map((c) => c.toJson()).toList(),
    };
    return Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(data)),
    );
  }

  // ─────────────────────────── 字节工具 ───────────────────────────

  Uint8List _u16(int value) {
    final data = ByteData(2)..setUint16(0, value & 0xFFFF);
    return data.buffer.asUint8List();
  }

  Uint8List _u32(int value) {
    final data = ByteData(4)..setUint32(0, value & 0xFFFFFFFF);
    return data.buffer.asUint8List();
  }

  Uint8List _f32(double value) {
    final data = ByteData(4)..setFloat32(0, value);
    return data.buffer.asUint8List();
  }

  Uint8List _utf16Be(String value) {
    final units = value.codeUnits;
    final data = ByteData(units.length * 2);
    for (var i = 0; i < units.length; i++) {
      data.setUint16(i * 2, units[i]);
    }
    return data.buffer.asUint8List();
  }
}
