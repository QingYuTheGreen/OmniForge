import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../engine_utils.dart';
import '../i_engine.dart';

/// 调色板色卡引擎：ase / aco / gpl / json 调色板 → PNG 色卡网格。
///
/// 只读调色板，不改动 color_engine 的互转逻辑；本引擎自带四种格式的最小解析。
///
/// 必选参数：
/// - `columns`    int    每行色块数，默认 8
/// - `cell`       int    色块边长像素，默认 96
/// - `background` String 背景色 hex，默认 `#202020`
class PaletteImageEngine extends SimpleEngine {
  const PaletteImageEngine();

  @override
  String get id => 'palette_image';

  static const double _gap = 8;

  @override
  Future<void> execute(EngineContext context) async {
    final bytes = await readFileBytes(context.inputPath);
    final ext = inputExtension(context);
    final format = _detectFormat(ext, bytes);
    final entries = switch (format) {
      'ase' => _parseAse(bytes),
      'aco' => _parseAco(bytes),
      'gpl' => _parseGpl(utf8.decode(bytes, allowMalformed: true)),
      'json' => _parseJson(utf8.decode(bytes, allowMalformed: true)),
      _ => throw EngineException('不支持的调色板输入格式：$ext'),
    };
    if (entries.isEmpty) {
      throw const EngineException('没有从调色板文件里解析到任何颜色');
    }

    final columns = intParam(context, 'columns', 8).clamp(1, 32);
    final cell = intParam(context, 'cell', 96).clamp(16, 512);
    final background =
        _parseHex(stringParam(context, 'background', '#202020'), 0x202020);

    final rows = (entries.length + columns - 1) ~/ columns;
    final font = cell >= 72 ? img.arial24 : img.arial14;
    final textHeight = font.lineHeight <= 0 ? 16 : font.lineHeight;
    const textPadding = 6;

    final gap = _gap.round();
    final width =
        (gap + columns * (cell + gap)).clamp(cell + gap * 2, 8192);
    final rowHeight = cell + textPadding + textHeight + gap;
    final height = gap + rows * rowHeight;

    final image = img.Image(width: width, height: height, numChannels: 3);
    img.fill(image, color: _rgb(background));

    // 文字颜色按背景亮度取黑/白，保证可读。
    final bgLuminance =
        0.299 * ((background >> 16) & 0xFF) +
            0.587 * ((background >> 8) & 0xFF) +
            0.114 * (background & 0xFF);
    final textColor = bgLuminance > 140
        ? img.ColorRgb8(0, 0, 0)
        : img.ColorRgb8(240, 240, 240);

    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final col = i % columns;
      final row = i ~/ columns;
      final x = gap + col * (cell + gap);
      final y = gap + row * rowHeight;

      img.fillRect(
        image,
        x1: x,
        y1: y,
        x2: x + cell - 1,
        y2: y + cell - 1,
        color: _rgb(entry),
      );

      final label = '#${entry.toRadixString(16).padLeft(6, '0').toUpperCase()}';
      img.drawString(
        image,
        label,
        font: font,
        x: x + 4,
        y: y + cell + textPadding,
        color: textColor,
      );
    }

    await writeFileBytes(context.outputPath, img.encodePng(image, level: 6));
  }

  // ─────────────────────────── 格式识别 ───────────────────────────

  String _detectFormat(String ext, Uint8List bytes) {
    if (ext == 'ase' || ext == 'aco' || ext == 'gpl' || ext == 'json') {
      return ext;
    }
    if (bytes.length >= 4 &&
        String.fromCharCodes(bytes.sublist(0, 4)) == 'ASEF') {
      return 'ase';
    }
    final head = utf8
        .decode(bytes.sublist(0, math.min(bytes.length, 64)),
            allowMalformed: true)
        .trimLeft();
    if (head.startsWith('{') || head.startsWith('[')) return 'json';
    if (head.startsWith('GIMP Palette') || head.startsWith('#')) return 'gpl';
    if (bytes.length >= 4) {
      final version = (bytes[0] << 8) | bytes[1];
      if (version == 1 || version == 2) return 'aco';
    }
    return ext;
  }

  // ─────────────────────────── ASE ───────────────────────────

  List<int> _parseAse(Uint8List bytes) {
    if (bytes.length < 12) return const [];
    final data = ByteData.sublistView(bytes);
    if (String.fromCharCodes(bytes.sublist(0, 4)) != 'ASEF') {
      throw const EngineException('不是有效的 ASE 调色板文件');
    }
    final blockCount = data.getUint32(8);
    var offset = 12;
    final colors = <int>[];
    for (var i = 0; i < blockCount && offset + 6 <= bytes.length; i++) {
      final type = data.getUint16(offset);
      final length = data.getUint32(offset + 2);
      final blockStart = offset + 6;
      final blockEnd = blockStart + length;
      if (blockEnd > bytes.length) break;
      if (type == 0x0001) {
        final color = _aseColor(data, blockStart, blockEnd);
        if (color != null) colors.add(color);
      }
      offset = blockEnd;
    }
    return colors;
  }

  int? _aseColor(ByteData data, int blockStart, int blockEnd) {
    final nameLength = data.getUint16(blockStart);
    var cursor = blockStart + 2 + nameLength * 2;
    if (cursor + 4 > blockEnd) return null;
    final model = String.fromCharCodes(
      Uint8List.fromList([
        data.getUint8(cursor),
        data.getUint8(cursor + 1),
        data.getUint8(cursor + 2),
        data.getUint8(cursor + 3),
      ]),
    );
    cursor += 4;
    if (model == 'RGB ' && cursor + 12 <= blockEnd) {
      final r = _float01(data, cursor);
      final g = _float01(data, cursor + 4);
      final b = _float01(data, cursor + 8);
      return (_channel(r) << 16) | (_channel(g) << 8) | _channel(b);
    }
    if (model == 'Gray' && cursor + 4 <= blockEnd) {
      final gray = _channel(_float01(data, cursor));
      return (gray << 16) | (gray << 8) | gray;
    }
    if (model == 'CMYK' && cursor + 16 <= blockEnd) {
      final c = _float01(data, cursor);
      final m = _float01(data, cursor + 4);
      final y = _float01(data, cursor + 8);
      final k = _float01(data, cursor + 12);
      final r = _channel((1 - c) * (1 - k));
      final g = _channel((1 - m) * (1 - k));
      final b = _channel((1 - y) * (1 - k));
      return (r << 16) | (g << 8) | b;
    }
    return null;
  }

  double _float01(ByteData data, int offset) =>
      data.getFloat32(offset).clamp(0.0, 1.0);

  int _channel(double value) => (value * 255).round().clamp(0, 255);

  // ─────────────────────────── ACO ───────────────────────────

  List<int> _parseAco(Uint8List bytes) {
    if (bytes.length < 4) return const [];
    final data = ByteData.sublistView(bytes);
    final version = data.getUint16(0);
    if (version != 1 && version != 2) {
      throw const EngineException('不是有效的 ACO 调色板文件');
    }
    final count = data.getUint16(2);
    var offset = 4;
    final colors = <int>[];
    for (var i = 0; i < count && offset + 10 <= bytes.length; i++) {
      final space = data.getUint16(offset);
      if (space == 0) {
        final r = data.getUint16(offset + 2) & 0xFF;
        final g = data.getUint16(offset + 4) & 0xFF;
        final b = data.getUint16(offset + 6) & 0xFF;
        colors.add((r << 16) | (g << 8) | b);
      } else if (space == 8) {
        final l = data.getUint16(offset + 2) / 100.0;
        final a = (data.getUint16(offset + 4) - 128) / 128.0;
        final b = (data.getUint16(offset + 6) - 128) / 128.0;
        colors.add(_labToRgb(l * 100, a * 128, b * 128));
      }
      offset += 10;
    }
    return colors;
  }

  int _labToRgb(double l, double a, double b) {
    final fy = (l + 16) / 116;
    final fx = a / 500 + fy;
    final fz = fy - b / 200;
    double inverse(double t) {
      final cube = t * t * t;
      return cube > 0.008856 ? cube : (t - 16 / 116) / 7.787;
    }

    final x = 0.95047 * inverse(fx);
    final y = inverse(fy);
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

    return (channel(rr) << 16) | (channel(gg) << 8) | channel(bb);
  }

  // ─────────────────────────── GPL ───────────────────────────

  List<int> _parseGpl(String content) {
    final colors = <int>[];
    for (final rawLine in content.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length < 3) continue;
      final r = int.tryParse(parts[0]);
      final g = int.tryParse(parts[1]);
      final b = int.tryParse(parts[2]);
      if (r == null || g == null || b == null) continue;
      colors.add(
        (r.clamp(0, 255) << 16) | (g.clamp(0, 255) << 8) | b.clamp(0, 255),
      );
    }
    return colors;
  }

  // ─────────────────────────── JSON ───────────────────────────

  List<int> _parseJson(String content) {
    final decoded = jsonDecode(content);
    final colors = <int>[];

    void add(Object? node) {
      if (node is String) {
        final color = _fromHex(node);
        if (color != null) colors.add(color);
      } else if (node is Map) {
        final hex = node['hex'] ?? node['color'] ?? node['value'];
        if (hex is String) {
          final color = _fromHex(hex);
          if (color != null) colors.add(color);
          return;
        }
        final rgb = node['rgb'];
        if (rgb is List && rgb.length >= 3) {
          final r = (rgb[0] as num).toInt().clamp(0, 255);
          final g = (rgb[1] as num).toInt().clamp(0, 255);
          final b = (rgb[2] as num).toInt().clamp(0, 255);
          colors.add((r << 16) | (g << 8) | b);
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

  int? _fromHex(String value) {
    var hex = value.trim().replaceFirst('#', '');
    if (hex.length == 3) {
      hex = hex.split('').map((c) => '$c$c').join();
    }
    if (hex.length < 6) return null;
    final r = int.tryParse(hex.substring(0, 2), radix: 16);
    final g = int.tryParse(hex.substring(2, 4), radix: 16);
    final b = int.tryParse(hex.substring(4, 6), radix: 16);
    if (r == null || g == null || b == null) return null;
    return (r << 16) | (g << 8) | b;
  }

  // ─────────────────────────── 工具 ───────────────────────────

  static int _parseHex(String value, int fallback) {
    var text = value.trim().replaceFirst('#', '');
    if (text.length == 3) {
      text = text.split('').map((c) => '$c$c').join();
    }
    if (text.length != 6) return fallback;
    return int.tryParse(text, radix: 16) ?? fallback;
  }

  static img.ColorRgb8 _rgb(int value) => img.ColorRgb8(
        (value >> 16) & 0xFF,
        (value >> 8) & 0xFF,
        value & 0xFF,
      );
}
