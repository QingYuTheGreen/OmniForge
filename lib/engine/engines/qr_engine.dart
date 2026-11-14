import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;

import '../engine_utils.dart';
import '../i_engine.dart';

/// QR Code 引擎：任意文本/文件 → PNG 二维码。
///
/// 纯 Dart 实现 ISO/IEC 18004：字节模式、版本 1..10 自动选择、
/// 纠错级别 L/M/Q/H、8 种掩码按标准罚分择优、RS 纠错（GF(256)）、
/// 定位/定时/对齐/格式/版本信息全部标准绘制。
///
/// 必选参数：
/// - `size`   int    输出 PNG 边长像素，默认 512
/// - `margin` int    静区宽度（模块数），默认 4
/// - `ec`     String 纠错级别，默认 M（L/M/Q/H）
class QrEngine extends SimpleEngine {
  const QrEngine();

  @override
  String get id => 'qr';

  @override
  Future<void> execute(EngineContext context) async {
    final bytes = await readFileBytes(context.inputPath);
    var text = '';
    try {
      text = await readFileText(context.inputPath);
    } catch (_) {
      // 极端情况下按文件名哈希兜底，保证任意文件都能生成二维码。
      text = md5.convert(utf8.encode(context.inputPath)).toString();
    }
    if (text.trim().isEmpty) {
      // 空文件/纯二进制没有可读文本时，用内容哈希，避免生成空二维码。
      text = md5.convert(bytes).toString();
    }

    final ec = stringParam(context, 'ec', 'M').toUpperCase();
    if (!QrSymbol.ecLevels.contains(ec)) {
      throw EngineException('不支持的纠错级别：$ec（可选 L/M/Q/H）');
    }
    final size = intParam(context, 'size', 512).clamp(64, 4096);
    final margin = intParam(context, 'margin', 4).clamp(0, 16);

    final symbol = QrSymbol.encodeBytes(
      Uint8List.fromList(utf8.encode(text)),
      ec,
    );

    final png = _renderPng(symbol, size, margin);
    await writeFileBytes(context.outputPath, png);
  }

  Uint8List _renderPng(QrSymbol symbol, int size, int margin) {
    final image = img.Image(width: size, height: size, numChannels: 3);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));

    final totalModules = symbol.dimension + margin * 2;
    final scale = size / totalModules;
    final black = img.ColorRgb8(0, 0, 0);

    for (var row = 0; row < symbol.dimension; row++) {
      for (var col = 0; col < symbol.dimension; col++) {
        if (!symbol.modules[row][col]) continue;
        final x1 = ((col + margin) * scale).floor().clamp(0, size - 1);
        final y1 = ((row + margin) * scale).floor().clamp(0, size - 1);
        final x2 =
            (((col + margin + 1) * scale).ceil() - 1).clamp(x1, size - 1);
        final y2 =
            (((row + margin + 1) * scale).ceil() - 1).clamp(y1, size - 1);
        img.fillRect(image, x1: x1, y1: y1, x2: x2, y2: y2, color: black);
      }
    }
    return img.encodePng(image, level: 6);
  }
}

/// 一个已完成编码、掩码与格式信息都已写入的 QR 符号。
///
/// 公开出来便于工具链（tool/verify_art.dart）校验版本、掩码与功能图形。
class QrSymbol {
  QrSymbol._({
    required this.version,
    required this.ecLevel,
    required this.mask,
    required this.modules,
  });

  /// 版本号 1..40（本引擎只生成 1..10）。
  final int version;

  /// 纠错级别：L / M / Q / H。
  final String ecLevel;

  /// 选中的掩码编号 0..7。
  final int mask;

  /// 边长为 [dimension] 的模块矩阵，true = 黑。
  final List<List<bool>> modules;

  int get dimension => modules.length;

  static const List<String> ecLevels = ['L', 'M', 'Q', 'H'];

  /// 字节模式编码；[maxVersion] 默认 10。
  static QrSymbol encodeBytes(
    List<int> data,
    String ecLevel, {
    int maxVersion = 10,
  }) {
    if (!ecLevels.contains(ecLevel)) {
      throw ArgumentError.value(ecLevel, 'ecLevel', '仅支持 L/M/Q/H');
    }
    _ensureGfTables();

    // 1. 选择能容纳数据的最小版本。
    var version = 0;
    for (var v = 1; v <= maxVersion; v++) {
      final dataCodewords = _dataCodewordCount(v, ecLevel);
      final headerBits = 4 + (v < 10 ? 8 : 16);
      if (headerBits + data.length * 8 <= dataCodewords * 8) {
        version = v;
        break;
      }
    }
    if (version == 0) {
      throw EngineException(
        '内容过长：${data.length} 字节，超出二维码版本 $maxVersion 在 '
        '$ecLevel 级下的容量',
      );
    }

    // 2. 数据位流：模式指示符 + 字符计数 + 字节数据 + 终止符 + 填充。
    final dataCodewords = _dataCodewordCount(version, ecLevel);
    final capacityBits = dataCodewords * 8;
    final bits = <int>[];

    void addBits(int value, int count) {
      for (var i = count - 1; i >= 0; i--) {
        bits.add((value >> i) & 1);
      }
    }

    addBits(0x04, 4); // 字节模式 0100
    addBits(data.length, version < 10 ? 8 : 16);
    for (final byte in data) {
      addBits(byte & 0xFF, 8);
    }
    final terminator = math.min(4, capacityBits - bits.length);
    addBits(0, terminator);
    while (bits.length % 8 != 0) {
      bits.add(0);
    }
    final codewords = <int>[];
    for (var i = 0; i < bits.length; i += 8) {
      var value = 0;
      for (var j = 0; j < 8; j++) {
        value = (value << 1) | bits[i + j];
      }
      codewords.add(value);
    }
    var padToggle = true;
    while (codewords.length < dataCodewords) {
      codewords.add(padToggle ? 0xEC : 0x11);
      padToggle = !padToggle;
    }

    // 3. 分块 + RS 纠错 + 交织。
    final structure = _blockStructure[version]![ecLevel]!;
    final ecPerBlock = structure[0];
    final dataBlocks = <List<int>>[];
    var offset = 0;
    for (var i = 0; i < structure[1]; i++) {
      final length = structure[2];
      dataBlocks.add(codewords.sublist(offset, offset + length));
      offset += length;
    }
    for (var i = 0; i < structure[3]; i++) {
      final length = structure[4];
      dataBlocks.add(codewords.sublist(offset, offset + length));
      offset += length;
    }
    final ecBlocks = <List<int>>[
      for (final block in dataBlocks) _rsRemainder(block, ecPerBlock),
    ];

    final interleaved = <int>[];
    final maxDataLength =
        dataBlocks.map((block) => block.length).reduce(math.max);
    for (var i = 0; i < maxDataLength; i++) {
      for (final block in dataBlocks) {
        if (i < block.length) interleaved.add(block[i]);
      }
    }
    for (var i = 0; i < ecPerBlock; i++) {
      for (final block in ecBlocks) {
        interleaved.add(block[i]);
      }
    }
    if (interleaved.length != _totalCodewords[version]) {
      throw StateError(
        '二维码码字数量异常：${interleaved.length} != '
        '${_totalCodewords[version]}',
      );
    }
    final dataStream = <int>[];
    for (final codeword in interleaved) {
      for (var i = 7; i >= 0; i--) {
        dataStream.add((codeword >> i) & 1);
      }
    }

    // 4. 绘制功能图形并写入数据位。
    final base = _buildBaseMatrix(version, dataStream);
    final isFunction = base.isFunction;

    // 5. 8 种掩码逐个评分，取罚分最小者。
    var bestMask = 0;
    var bestPenalty = -1;
    var bestModules = <List<bool>>[];
    for (var mask = 0; mask < 8; mask++) {
      final candidate = <List<bool>>[
        for (final row in base.modules) List<bool>.of(row),
      ];
      for (var row = 0; row < candidate.length; row++) {
        for (var col = 0; col < candidate.length; col++) {
          if (!isFunction[row][col] && _maskBit(mask, row, col)) {
            candidate[row][col] = !candidate[row][col];
          }
        }
      }
      _writeFormatInfo(candidate, ecLevel, mask);
      _writeVersionInfo(candidate, version);
      final penalty = _penalty(candidate);
      if (bestPenalty < 0 || penalty < bestPenalty) {
        bestPenalty = penalty;
        bestMask = mask;
        bestModules = candidate;
      }
    }

    return QrSymbol._(
      version: version,
      ecLevel: ecLevel,
      mask: bestMask,
      modules: bestModules,
    );
  }

  // ── 数据区域排布 ──────────────────────────────────────────────

  static _BaseMatrix _buildBaseMatrix(int version, List<int> dataBits) {
    final size = version * 4 + 17;
    final modules = List.generate(size, (_) => List<bool>.filled(size, false));
    final isFunction =
        List.generate(size, (_) => List<bool>.filled(size, false));

    void set(int row, int col, bool dark) {
      modules[row][col] = dark;
      isFunction[row][col] = true;
    }

    // 定位图形 + 分隔符（三个角）。
    for (final origin in [
      [0, 0],
      [0, size - 7],
      [size - 7, 0],
    ]) {
      final top = origin[0];
      final left = origin[1];
      for (var dy = -1; dy <= 7; dy++) {
        for (var dx = -1; dx <= 7; dx++) {
          final row = top + dy;
          final col = left + dx;
          if (row < 0 || row >= size || col < 0 || col >= size) continue;
          final inFinder = dy >= 0 && dy <= 6 && dx >= 0 && dx <= 6;
          final dark = inFinder &&
              (dy == 0 ||
                  dy == 6 ||
                  dx == 0 ||
                  dx == 6 ||
                  (dy >= 2 && dy <= 4 && dx >= 2 && dx <= 4));
          set(row, col, dark);
        }
      }
    }

    // 定时图形。
    for (var i = 8; i < size - 8; i++) {
      set(6, i, i.isEven);
      set(i, 6, i.isEven);
    }

    // 对齐图形（版本 2+），跳过与定位图形重叠的三个角。
    final positions = _alignmentPositions[version] ?? const <int>[];
    final last = positions.isEmpty ? -1 : positions.last;
    for (final row in positions) {
      for (final col in positions) {
        final overlapsFinder = (row == 6 && col == 6) ||
            (row == 6 && col == last) ||
            (row == last && col == 6);
        if (overlapsFinder) continue;
        for (var dy = -2; dy <= 2; dy++) {
          for (var dx = -2; dx <= 2; dx++) {
            final dark = math.max(dy.abs(), dx.abs()) != 1;
            set(row + dy, col + dx, dark);
          }
        }
      }
    }

    // 固定黑模块。
    set(size - 8, 8, true);

    // 预留格式信息区域（先占位为白，稍后写入真值）。
    for (var i = 0; i <= 8; i++) {
      if (!isFunction[8][i]) set(8, i, false);
      if (!isFunction[i][8]) set(i, 8, false);
    }
    for (var i = 0; i < 8; i++) {
      if (!isFunction[8][size - 1 - i]) set(8, size - 1 - i, false);
      if (!isFunction[size - 1 - i][8]) set(size - 1 - i, 8, false);
    }

    // 版本信息区域（版本 7+）。
    if (version >= 7) {
      for (var i = 0; i < 18; i++) {
        final a = size - 11 + i % 3;
        final b = i ~/ 3;
        set(b, a, false);
        set(a, b, false);
      }
    }

    // 数据位之字形填充：从右到左两列一组，遇第 6 列跳过。
    var bitIndex = 0;
    var upward = true;
    for (var right = size - 1; right >= 1; right -= 2) {
      if (right == 6) right = 5;
      for (var vert = 0; vert < size; vert++) {
        final row = upward ? size - 1 - vert : vert;
        for (var j = 0; j < 2; j++) {
          final col = right - j;
          if (isFunction[row][col]) continue;
          final dark =
              bitIndex < dataBits.length && dataBits[bitIndex] == 1;
          modules[row][col] = dark;
          bitIndex++;
        }
      }
      upward = !upward;
    }
    if (bitIndex < dataBits.length) {
      throw StateError('数据位未完全写入：$bitIndex / ${dataBits.length}');
    }

    return _BaseMatrix(modules, isFunction);
  }

  // ── 掩码 / 格式信息 / 版本信息 ───────────────────────────────

  static bool _maskBit(int mask, int row, int col) => switch (mask) {
        0 => (row + col).isEven,
        1 => row.isEven,
        2 => col % 3 == 0,
        3 => (row + col) % 3 == 0,
        4 => (row ~/ 2 + col ~/ 3).isEven,
        5 => (row * col) % 2 + (row * col) % 3 == 0,
        6 => ((row * col) % 2 + (row * col) % 3).isEven,
        _ => ((row + col) % 2 + (row * col) % 3).isEven,
      };

  static void _writeFormatInfo(
    List<List<bool>> modules,
    String ecLevel,
    int mask,
  ) {
    final size = modules.length;
    final ecBits = _ecFormatBits[ecLevel]!;
    final data = (ecBits << 3) | mask;
    var remainder = data;
    for (var i = 0; i < 10; i++) {
      remainder = (remainder << 1) ^ (((remainder >> 9) & 1) * 0x537);
    }
    final format = ((data << 10) | remainder) ^ 0x5412;

    bool bit(int index) => ((format >> index) & 1) == 1;

    // 第一份：定位图形周围（坐标 = (x 列, y 行的转置对应)）。
    for (var i = 0; i <= 5; i++) {
      modules[i][8] = bit(i);
    }
    modules[7][8] = bit(6);
    modules[8][8] = bit(7);
    modules[8][7] = bit(8);
    for (var i = 9; i < 15; i++) {
      modules[8][14 - i] = bit(i);
    }
    // 第二份：右上 / 左下。
    for (var i = 0; i < 8; i++) {
      modules[8][size - 1 - i] = bit(i);
    }
    for (var i = 8; i < 15; i++) {
      modules[size - 15 + i][8] = bit(i);
    }
    modules[size - 8][8] = true; // 固定黑模块
  }

  static void _writeVersionInfo(List<List<bool>> modules, int version) {
    if (version < 7) return;
    final size = modules.length;
    var remainder = version;
    for (var i = 0; i < 12; i++) {
      remainder = (remainder << 1) ^ (((remainder >> 11) & 1) * 0x1F25);
    }
    final info = (version << 12) | remainder;
    for (var i = 0; i < 18; i++) {
      final bit = ((info >> i) & 1) == 1;
      final a = size - 11 + i % 3;
      final b = i ~/ 3;
      modules[b][a] = bit;
      modules[a][b] = bit;
    }
  }

  // ── 罚分 ─────────────────────────────────────────────────────

  static int _penalty(List<List<bool>> modules) {
    final size = modules.length;
    var penalty = 0;

    // 规则 1：行/列连续同色 run >= 5。
    for (var i = 0; i < size; i++) {
      var run = 1;
      for (var j = 1; j < size; j++) {
        if (modules[i][j] == modules[i][j - 1]) {
          run++;
        } else {
          if (run >= 5) penalty += 3 + (run - 5);
          run = 1;
        }
      }
      if (run >= 5) penalty += 3 + (run - 5);

      run = 1;
      for (var j = 1; j < size; j++) {
        if (modules[j][i] == modules[j - 1][i]) {
          run++;
        } else {
          if (run >= 5) penalty += 3 + (run - 5);
          run = 1;
        }
      }
      if (run >= 5) penalty += 3 + (run - 5);
    }

    // 规则 2：2×2 同色块。
    for (var row = 0; row < size - 1; row++) {
      for (var col = 0; col < size - 1; col++) {
        final color = modules[row][col];
        if (modules[row][col + 1] == color &&
            modules[row + 1][col] == color &&
            modules[row + 1][col + 1] == color) {
          penalty += 3;
        }
      }
    }

    // 规则 3：1:1:3:1:1 类定位图形。
    const patternA = [1, 0, 1, 1, 1, 0, 1, 0, 0, 0, 0];
    const patternB = [0, 0, 0, 0, 1, 0, 1, 1, 1, 0, 1];
    for (var i = 0; i < size; i++) {
      for (var j = 0; j + 11 <= size; j++) {
        var matchA = true;
        var matchB = true;
        var matchAc = true;
        var matchBc = true;
        for (var k = 0; k < 11; k++) {
          final rowColor = modules[i][j + k] ? 1 : 0;
          final colColor = modules[j + k][i] ? 1 : 0;
          if (rowColor != patternA[k]) matchA = false;
          if (rowColor != patternB[k]) matchB = false;
          if (colColor != patternA[k]) matchAc = false;
          if (colColor != patternB[k]) matchBc = false;
        }
        if (matchA) penalty += 40;
        if (matchB) penalty += 40;
        if (matchAc) penalty += 40;
        if (matchBc) penalty += 40;
      }
    }

    // 规则 4：黑模块占比偏离 50%。
    var dark = 0;
    for (final row in modules) {
      for (final value in row) {
        if (value) dark++;
      }
    }
    final total = size * size;
    final k = ((dark * 20 - total * 10).abs()) ~/ total;
    penalty += k * 10;

    return penalty;
  }

  // ── GF(256) / Reed-Solomon ───────────────────────────────────

  static final List<int> _gfExp = List<int>.filled(512, 0);
  static final List<int> _gfLog = List<int>.filled(256, 0);
  static bool _gfReady = false;

  static void _ensureGfTables() {
    if (_gfReady) return;
    var x = 1;
    for (var i = 0; i < 255; i++) {
      _gfExp[i] = x;
      _gfLog[x] = i;
      x <<= 1;
      if (x & 0x100 != 0) x ^= 0x11D;
    }
    for (var i = 255; i < 512; i++) {
      _gfExp[i] = _gfExp[i - 255];
    }
    _gfReady = true;
  }

  static int _gfMul(int a, int b) {
    if (a == 0 || b == 0) return 0;
    return _gfExp[_gfLog[a] + _gfLog[b]];
  }

  static List<int> _rsGenerator(int degree) {
    var poly = <int>[1];
    for (var i = 0; i < degree; i++) {
      final next = List<int>.filled(poly.length + 1, 0);
      for (var j = 0; j < poly.length; j++) {
        next[j] ^= poly[j];
        next[j + 1] ^= _gfMul(poly[j], _gfExp[i]);
      }
      poly = next;
    }
    return poly;
  }

  static List<int> _rsRemainder(List<int> data, int ecCount) {
    final generator = _rsGenerator(ecCount);
    final buffer = List<int>.filled(data.length + ecCount, 0);
    buffer.setRange(0, data.length, data);
    for (var i = 0; i < data.length; i++) {
      final coefficient = buffer[i];
      if (coefficient == 0) continue;
      for (var j = 1; j < generator.length; j++) {
        buffer[i + j] ^= _gfMul(generator[j], coefficient);
      }
    }
    return buffer.sublist(data.length);
  }

  // ── 标准常量表（仅版本 1..10）────────────────────────────────

  static const Map<String, int> _ecFormatBits = {
    'L': 1,
    'M': 0,
    'Q': 3,
    'H': 2,
  };

  /// 版本 → 空矩阵所需总数（数据码字 + 纠错码字）。
  static const Map<int, int> _totalCodewords = {
    1: 26,
    2: 44,
    3: 70,
    4: 100,
    5: 134,
    6: 172,
    7: 196,
    8: 242,
    9: 292,
    10: 346,
  };

  /// 版本 → 纠错级别 → [ecPerBlock, group1Blocks, group1Data,
  /// group2Blocks, group2Data]。
  static const Map<int, Map<String, List<int>>> _blockStructure = {
    1: {
      'L': [7, 1, 19, 0, 0],
      'M': [10, 1, 16, 0, 0],
      'Q': [13, 1, 13, 0, 0],
      'H': [17, 1, 9, 0, 0],
    },
    2: {
      'L': [10, 1, 34, 0, 0],
      'M': [16, 1, 28, 0, 0],
      'Q': [22, 1, 22, 0, 0],
      'H': [28, 1, 16, 0, 0],
    },
    3: {
      'L': [15, 1, 55, 0, 0],
      'M': [26, 1, 44, 0, 0],
      'Q': [18, 2, 17, 0, 0],
      'H': [22, 2, 13, 0, 0],
    },
    4: {
      'L': [20, 1, 80, 0, 0],
      'M': [18, 2, 32, 0, 0],
      'Q': [26, 2, 24, 0, 0],
      'H': [16, 4, 9, 0, 0],
    },
    5: {
      'L': [26, 1, 108, 0, 0],
      'M': [24, 2, 43, 0, 0],
      'Q': [18, 2, 15, 2, 16],
      'H': [22, 2, 11, 2, 12],
    },
    6: {
      'L': [18, 2, 68, 0, 0],
      'M': [16, 4, 27, 0, 0],
      'Q': [24, 4, 19, 0, 0],
      'H': [28, 4, 15, 0, 0],
    },
    7: {
      'L': [20, 2, 78, 0, 0],
      'M': [18, 4, 31, 0, 0],
      'Q': [18, 2, 14, 4, 15],
      'H': [26, 4, 13, 1, 14],
    },
    8: {
      'L': [24, 2, 97, 0, 0],
      'M': [22, 2, 38, 2, 39],
      'Q': [22, 4, 18, 2, 19],
      'H': [26, 4, 14, 2, 15],
    },
    9: {
      'L': [30, 2, 116, 0, 0],
      'M': [22, 3, 36, 2, 37],
      'Q': [20, 4, 16, 4, 17],
      'H': [24, 4, 12, 4, 13],
    },
    10: {
      'L': [18, 2, 68, 2, 69],
      'M': [26, 4, 43, 1, 44],
      'Q': [24, 6, 19, 2, 20],
      'H': [28, 6, 15, 2, 16],
    },
  };

  /// 版本 → 对齐图形中心坐标。
  static const Map<int, List<int>> _alignmentPositions = {
    2: [6, 18],
    3: [6, 22],
    4: [6, 26],
    5: [6, 30],
    6: [6, 34],
    7: [6, 22, 38],
    8: [6, 24, 42],
    9: [6, 26, 46],
    10: [6, 28, 50],
  };

  static int _dataCodewordCount(int version, String ecLevel) {
    final structure = _blockStructure[version]![ecLevel]!;
    return structure[1] * structure[2] + structure[3] * structure[4];
  }
}

class _BaseMatrix {
  _BaseMatrix(this.modules, this.isFunction);

  final List<List<bool>> modules;
  final List<List<bool>> isFunction;
}
