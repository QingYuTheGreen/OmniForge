/// 绣花引擎：DST / PES / JEF 绣花格式互转，以及 dst→png 预览、png/jpg→dst 位图转针迹。
///
/// 通用模型：[Stitch]（单位 0.1mm，int 坐标）与 [EmbroideryPattern]。
///
/// 各格式编码依据公开规范 / 开源实现（pyembroidery）实现：
/// - DST：512 字节头（LA:/ST:/CO: 等字段）+ 每针 3 字节（1/9/3/27/81 位移位域，
///   b2 最高位为跳针，0xC3 换色，0xF3 结束）。
/// - PEC（PES 的内嵌针迹段）：512 字节 PEC 头 + 针迹块；每坐标 1~2 字节，
///   短式 7bit 补码（-64..63），长式 12bit 补码 + bit7 长式标志 + bit4/bit5 跳针/剪线标志；
///   0xFE 0xB0 + 交替字节表示换色，0xFF 结束。PES v1 外壳 = `#PES0001` + PEC 偏移 + 精简头。
/// - JEF：116(0x74) 字节头 + 色表 + 线型表 + 2 字节位移（dx, -dy 的 int8），
///   0x80 0x01=换色、0x80 0x02=跳针、0x80 0x10=结束。
///
/// 坐标约定：模型 y 轴向上（与 DST/JEF 文件一致），PEC 文件 y 轴方向相反（写入时取反）。
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../common/binary_io.dart';
import '../engine_utils.dart';
import '../i_engine.dart';

/// 针迹类型。
enum StitchType {
  /// 普通落针（会缝线）。
  stitch,

  /// 跳针（不缝线，只移动）。
  jump,

  /// 换色（针迹位置不变，仅切换线色）。
  colorChange,

  /// 剪线（部分格式支持；写出时忽略）。
  trim,
}

/// 一根针迹（或一条控制记录）。
class Stitch {
  const Stitch(this.x, this.y, {this.type = StitchType.stitch});

  /// 0.1mm 为单位的横坐标。
  final int x;

  /// 0.1mm 为单位的纵坐标（模型 y 轴向上）。
  final int y;

  final StitchType type;

  bool get isJump => type == StitchType.jump;

  @override
  String toString() => 'Stitch($x, $y, ${type.name})';
}

/// 绣花图案：名称 + 针迹序列 + 线色列表。
class EmbroideryPattern {
  EmbroideryPattern({
    this.name = '',
    List<Stitch>? stitches,
    List<int>? colors,
  })  : stitches = stitches ?? <Stitch>[],
        colors = colors ?? <int>[];

  String name;
  final List<Stitch> stitches;

  /// 线色（0xRRGGBB）。
  final List<int> colors;

  int get stitchCount => stitches.length;

  /// 可见针迹（不含跳针 / 换色 / 剪线）的包围盒，返回 [minX, minY, maxX, maxY]。
  List<int> bounds() {
    var minX = 0;
    var minY = 0;
    var maxX = 0;
    var maxY = 0;
    var has = false;
    for (final stitch in stitches) {
      if (stitch.type == StitchType.colorChange ||
          stitch.type == StitchType.trim) {
        continue;
      }
      if (!has) {
        minX = maxX = stitch.x;
        minY = maxY = stitch.y;
        has = true;
      } else {
        minX = math.min(minX, stitch.x);
        minY = math.min(minY, stitch.y);
        maxX = math.max(maxX, stitch.x);
        maxY = math.max(maxY, stitch.y);
      }
    }
    return [minX, minY, maxX, maxY];
  }
}

/// 绣花格式引擎。
class EmbroideryEngine extends SimpleEngine {
  const EmbroideryEngine();

  @override
  String get id => 'embroidery';

  /// 绣花二进制格式。
  static const Set<String> embroideryFormats = {'dst', 'pes', 'jef'};

  /// 位图输入格式（转 DST）。
  static const Set<String> rasterFormats = {'png', 'jpg', 'jpeg'};

  @override
  void validate(EngineContext context) {
    final source = detectSource(context);
    final target = context.targetFormat.toLowerCase();
    if (embroideryFormats.contains(source)) {
      if (target != 'png' && !embroideryFormats.contains(target)) {
        throw EngineException('绣花引擎不支持输出格式：$target');
      }
      return;
    }
    if (rasterFormats.contains(source)) {
      if (!embroideryFormats.contains(target)) {
        throw EngineException('图片转绣花仅支持输出 dst / pes / jef，收到：$target');
      }
      return;
    }
    throw EngineException('绣花引擎不支持输入格式：$source');
  }

  @override
  Future<void> execute(EngineContext context) async {
    final bytes = await readFileBytes(context.inputPath);
    final source = detectSource(context);
    final target = context.targetFormat.toLowerCase();
    final name = inputStem(context);

    if (embroideryFormats.contains(source)) {
      final pattern = decodePattern(bytes, source);
      if (pattern.stitches.isEmpty) {
        throw const EngineException('输入绣花文件里没有针迹');
      }
      if (target == 'png') {
        final scale = doubleParam(context, 'scale', 2.0).clamp(0.05, 100.0);
        final margin = intParam(context, 'margin', 6).clamp(0, 500);
        final background = stringParam(context, 'background', '#ffffff');
        final color = stringParam(context, 'color', '#1e88e5');
        final png = renderPreviewPng(
          pattern,
          scale: scale,
          margin: margin,
          background: background,
          color: color,
        );
        await writeFileBytes(context.outputPath, png);
        return;
      }
      final decoded = decodePattern(bytes, source);
      final output = encodePattern(decoded, target, name: name);
      await writeFileBytes(context.outputPath, output);
      return;
    }

    // 位图 → 绣花
    final image = img.decodeImage(bytes);
    if (image == null) {
      throw const EngineException('无法解码输入图片');
    }
    final pattern = fromImage(
      image,
      name: name,
      threshold: intParam(context, 'threshold', 128).clamp(0, 255),
      maxStitches: intParam(context, 'max_stitches', 20000).clamp(16, 500000),
    );
    if (pattern.stitches.isEmpty) {
      throw const EngineException('阈值化后没有可缝的像素（图片可能是纯白）');
    }
    final output = encodePattern(pattern, target, name: name);
    await writeFileBytes(context.outputPath, output);
  }

  /// 输入格式判断：sourceFormat > 扩展名。
  static String detectSource(EngineContext context) {
    final declared = context.sourceFormat.toLowerCase();
    if (declared == 'jpg' || declared == 'jpeg') return 'jpg';
    if (embroideryFormats.contains(declared)) return declared;
    final ext = inputExtension(context);
    return ext == 'jpeg' ? 'jpg' : ext;
  }

  // ═══════════════════════════ 通用编解码入口 ═══════════════════════════

  /// 按格式解码为 [EmbroideryPattern]。
  static EmbroideryPattern decodePattern(Uint8List bytes, String format) {
    switch (format.toLowerCase()) {
      case 'dst':
        return decodeDst(bytes);
      case 'pes':
        return decodePes(bytes);
      case 'jef':
        return decodeJef(bytes);
      default:
        throw EngineException('不支持读取的绣花格式：$format');
    }
  }

  /// 按格式编码 [EmbroideryPattern]。
  static Uint8List encodePattern(
    EmbroideryPattern pattern,
    String format, {
    String? name,
  }) {
    final copy = EmbroideryPattern(
      name: name ?? pattern.name,
      stitches: pattern.stitches,
      colors: pattern.colors.isEmpty ? <int>[0x000000] : pattern.colors,
    );
    switch (format.toLowerCase()) {
      case 'dst':
        return encodeDst(copy);
      case 'pes':
        return encodePes(copy);
      case 'jef':
        return encodeJef(copy);
      default:
        throw EngineException('不支持写出的绣花格式：$format');
    }
  }

  // ═══════════════════════════ DST ═══════════════════════════

  /// 读取 DST（512 字节头 + 3 字节/针记录，0x00 0x00 0xF3 结束）。
  static EmbroideryPattern decodeDst(Uint8List bytes) {
    const headerSize = 512;
    if (bytes.length < headerSize + 3) {
      throw const EngineException('DST 文件过短，至少需要 515 字节');
    }
    final pattern = EmbroideryPattern(name: _dstReadLabel(bytes));

    var x = 0;
    var y = 0;
    for (var offset = headerSize; offset + 3 <= bytes.length; offset += 3) {
      final b0 = bytes[offset];
      final b1 = bytes[offset + 1];
      final b2 = bytes[offset + 2];
      if (b2 == 0xF3) break; // 结束标记
      if (b2 == 0xC3) {
        pattern.stitches.add(Stitch(x, y, type: StitchType.colorChange));
        continue;
      }
      var dx = 0;
      var dy = 0;
      if (b0 & 0x01 != 0) dx += 1;
      if (b0 & 0x02 != 0) dx -= 1;
      if (b0 & 0x04 != 0) dx += 9;
      if (b0 & 0x08 != 0) dx -= 9;
      if (b1 & 0x01 != 0) dx += 3;
      if (b1 & 0x02 != 0) dx -= 3;
      if (b1 & 0x04 != 0) dx += 27;
      if (b1 & 0x08 != 0) dx -= 27;
      if (b2 & 0x04 != 0) dx += 81;
      if (b2 & 0x08 != 0) dx -= 81;

      if (b0 & 0x40 != 0) dy += 1;
      if (b0 & 0x80 != 0) dy -= 1;
      if (b0 & 0x10 != 0) dy += 9;
      if (b0 & 0x20 != 0) dy -= 9;
      if (b1 & 0x40 != 0) dy += 3;
      if (b1 & 0x80 != 0) dy -= 3;
      if (b1 & 0x10 != 0) dy += 27;
      if (b1 & 0x20 != 0) dy -= 27;
      if (b2 & 0x10 != 0) dy += 81;
      if (b2 & 0x20 != 0) dy -= 81;

      x += dx;
      y += dy;
      final isJump = (b2 & 0x80) != 0;
      pattern.stitches.add(
        Stitch(x, y, type: isJump ? StitchType.jump : StitchType.stitch),
      );
    }
    return pattern;
  }

  /// 写出 DST。
  static Uint8List encodeDst(EmbroideryPattern pattern) {
    final header = Uint8List(512)..fillRange(0, 512, 0x20);
    final name = _dstSafeLabel(pattern.name);
    var offset = 0;
    void writeText(String text) {
      for (var i = 0; i < text.length && offset < header.length; i++) {
        header[offset++] = text.codeUnitAt(i) & 0xFF;
      }
    }

    writeText('LA:$name\r');
    writeText('ST:${pattern.stitchCount.toString().padLeft(7)}\r');
    writeText('CO:${math.max(1, pattern.colors.length).toString().padLeft(3)}\r');
    final bounds = pattern.bounds();
    writeText('+X:${bounds[2].abs().toString().padLeft(5)}\r');
    writeText('-X:${bounds[0].abs().toString().padLeft(5)}\r');
    writeText('+Y:${bounds[3].abs().toString().padLeft(5)}\r');
    writeText('-Y:${bounds[1].abs().toString().padLeft(5)}\r');
    // 固定的附加头字段，保持与常见 DST 写出器一致
    writeText('AX:+${0.toString().padLeft(5)}\r');
    writeText('AY:+${0.toString().padLeft(5)}\r');
    writeText('MX:+${0.toString().padLeft(5)}\r');
    writeText('MY:+${0.toString().padLeft(5)}\r');
    writeText('PD:${'******'}\r');
    if (offset < header.length) header[offset++] = 0x1A;

    final writer = ByteWriter()..bytes(header);
    var xx = 0;
    var yy = 0;
    for (final stitch in pattern.stitches) {
      if (stitch.type == StitchType.trim) continue;
      if (stitch.type == StitchType.colorChange) {
        writer
          ..u8(0)
          ..u8(0)
          ..u8(0xC3);
        continue;
      }
      _writeDstMove(
        writer,
        stitch.x - xx,
        stitch.y - yy,
        jump: stitch.isJump,
      );
      xx = stitch.x;
      yy = stitch.y;
    }
    writer
      ..u8(0)
      ..u8(0)
      ..u8(0xF3);
    return writer.toBytes();
  }

  /// 把一次位移拆成若干条 ≤121 的 DST 记录。
  static void _writeDstMove(
    ByteWriter writer,
    int dx,
    int dy, {
    required bool jump,
  }) {
    var remainingX = dx;
    var remainingY = dy;
    do {
      final stepX = remainingX.clamp(-121, 121);
      final stepY = remainingY.clamp(-121, 121);
      writer.bytes(_dstRecord(stepX, stepY, jump));
      remainingX -= stepX;
      remainingY -= stepY;
    } while (remainingX != 0 || remainingY != 0);
  }

  /// 单条 DST 记录编码（内部会按 DST 文件方向取反 y）。
  static List<int> _dstRecord(int dx, int dyModel, bool jump) {
    var x = dx;
    // DST 文件里 y 轴方向与模型相反（与主流写出器一致）
    var y = -dyModel;
    var b0 = 0;
    var b1 = 0;
    var b2 = 0;
    if (jump) b2 |= 0x80;
    b2 |= 0x03; // stitch/jump 记录标志

    if (x > 40) {
      b2 |= 0x04;
      x -= 81;
    }
    if (x < -40) {
      b2 |= 0x08;
      x += 81;
    }
    if (x > 13) {
      b1 |= 0x04;
      x -= 27;
    }
    if (x < -13) {
      b1 |= 0x08;
      x += 27;
    }
    if (x > 4) {
      b0 |= 0x04;
      x -= 9;
    }
    if (x < -4) {
      b0 |= 0x08;
      x += 9;
    }
    if (x > 1) {
      b1 |= 0x01;
      x -= 3;
    }
    if (x < -1) {
      b1 |= 0x02;
      x += 3;
    }
    if (x > 0) {
      b0 |= 0x01;
      x -= 1;
    }
    if (x < 0) {
      b0 |= 0x02;
      x += 1;
    }
    if (x != 0) {
      throw const EngineException('DST 单针位移超出范围');
    }

    if (y > 40) {
      b2 |= 0x20;
      y -= 81;
    }
    if (y < -40) {
      b2 |= 0x10;
      y += 81;
    }
    if (y > 13) {
      b1 |= 0x20;
      y -= 27;
    }
    if (y < -13) {
      b1 |= 0x10;
      y += 27;
    }
    if (y > 4) {
      b0 |= 0x20;
      y -= 9;
    }
    if (y < -4) {
      b0 |= 0x10;
      y += 9;
    }
    if (y > 1) {
      b1 |= 0x80;
      y -= 3;
    }
    if (y < -1) {
      b1 |= 0x40;
      y += 3;
    }
    if (y > 0) {
      b0 |= 0x80;
      y -= 1;
    }
    if (y < 0) {
      b0 |= 0x40;
      y += 1;
    }
    if (y != 0) {
      throw const EngineException('DST 单针位移超出范围');
    }
    return [b0, b1, b2];
  }

  static String _dstReadLabel(Uint8List bytes) {
    final header = String.fromCharCodes(bytes.sublist(0, 512));
    final laIndex = header.indexOf('LA:');
    if (laIndex >= 0 && laIndex + 19 <= header.length) {
      return header
          .substring(laIndex + 3, laIndex + 19)
          .replaceAll('\u0000', '')
          .trim();
    }
    return '';
  }

  static String _dstSafeLabel(String name) {
    final cleaned = name.replaceAll(RegExp(r'[^\x20-\x7E]'), '?');
    return cleaned.length > 16 ? cleaned.substring(0, 16) : cleaned.padRight(16);
  }

  // ═══════════════════════════ PEC / PES ═══════════════════════════

  static const int _pecHeaderSize = 512;

  /// PEC 默认调色板（仅用于把线色索引转成 RGB 展示）。
  static const List<int> _pecPalette = [
    0x000000, 0xFFFFFF, 0xE60000, 0x00A800, 0x0000E6, 0xFFD000, 0x800080,
    0x00A8A8, 0xFF7F7F, 0x7F0000, 0x007F00, 0x00007F, 0xFF7F00, 0x7F007F,
    0x00FF00, 0x7F7F7F,
  ];

  /// 读取 PES（v1 / v6 外壳均可：取 PEC 段偏移后按 PEC 结构解析）。
  static EmbroideryPattern decodePes(Uint8List bytes) {
    if (bytes.length < 16 || !_asciiEquals(bytes, 0, '#PES')) {
      throw const EngineException('不是有效的 PES 文件（缺少 #PES 魔数）');
    }
    var pecOffset = _u32le(bytes, 8);
    if (pecOffset < 8 || pecOffset + _pecHeaderSize + 16 > bytes.length) {
      pecOffset = _findAscii(bytes, 'LA:', 8);
    }
    if (pecOffset < 0 || pecOffset + _pecHeaderSize + 16 > bytes.length) {
      throw const EngineException('PES 文件里找不到 PEC 针迹段');
    }
    return _decodePec(bytes, pecOffset);
  }

  /// 写出最小可用的 PES v1：`#PES0001` + PEC 偏移 + 精简头 + PEC 段。
  static Uint8List encodePes(EmbroideryPattern pattern) {
    final writer = ByteWriter();
    writer.ascii('#PES0001');
    const pecOffset = 22; // 8 魔数 + 4 偏移 + 6 头 + 4 = 22
    writer.u32le(pecOffset);
    // PES v1 头：scale / hoop / distinct blocks
    writer
      ..u16le(1)
      ..u16le(1)
      ..u16le(1)
      ..u16le(0xFFFF)
      ..u16le(0x0000);
    assert(writer.length == pecOffset);
    writer.bytes(_buildPecSection(pattern));
    return writer.toBytes();
  }

  /// 构建完整 PEC 段：512 字节 PEC 头 + 针迹块。
  static Uint8List _buildPecSection(EmbroideryPattern pattern) {
    final name = _dstSafeLabel(pattern.name);
    final header = Uint8List(_pecHeaderSize)..fillRange(0, _pecHeaderSize, 0x20);
    final label = 'LA:$name\r';
    for (var i = 0; i < label.length && i < header.length; i++) {
      header[i] = label.codeUnitAt(i) & 0xFF;
    }
    // 12 个空格（22..33 已由 0x20 填充），0xFF 0x00 分隔
    header[32] = 0xFF;
    header[33] = 0x00;
    header[34] = 0x06; // PEC 缩略图行字节数 48/8
    header[35] = 0x26; // PEC 缩略图高度 38
    // 36..47 保留空格，48..59 保留空格
    final colorCount = pattern.colors.isEmpty ? 1 : pattern.colors.length;
    header[60] = (colorCount - 1) & 0xFF;
    for (var i = 0; i < colorCount && 61 + i < header.length; i++) {
      header[61 + i] = i & 0xFF;
    }

    final stitchWriter = ByteWriter();
    _writePecStitches(stitchWriter, pattern);
    final stitchBytes = stitchWriter.toBytes();

    final bounds = pattern.bounds();
    final width = (bounds[2] - bounds[0]).abs().clamp(0, 0xFFFF);
    final height = (bounds[3] - bounds[1]).abs().clamp(0, 0xFFFF);

    final block = ByteWriter()
      ..u16le(0) // 固定前导
      ..u8(0) // 3 字节块长度占位
      ..u8(0)
      ..u8(0)
      ..u8(0x31)
      ..u8(0xFF)
      ..u8(0xF0)
      ..u16le(width)
      ..u16le(height)
      ..u16le(0x1E0)
      ..u16le(0x1B0)
      ..bytes(stitchBytes);
    final blockBytes = block.toBytes();
    // 回填 3 字节块长度（与主流写出器一致：整块长度，含开头 2 字节）
    final blockLength = blockBytes.length;
    blockBytes[2] = blockLength & 0xFF;
    blockBytes[3] = (blockLength >> 8) & 0xFF;
    blockBytes[4] = (blockLength >> 16) & 0xFF;

    final out = BytesBuilder(copy: false)
      ..add(header)
      ..add(blockBytes);
    return out.toBytes();
  }

  /// 解析 PEC 段（[pecOffset] 指向 "LA:"）。
  static EmbroideryPattern _decodePec(Uint8List bytes, int pecOffset) {
    final pattern = EmbroideryPattern();
    final la = pecOffset;
    if (la + 19 <= bytes.length) {
      pattern.name = String.fromCharCodes(bytes.sublist(la + 3, la + 19))
          .replaceAll('\u0000', '')
          .trim();
    }
    // 线色索引
    final colorBase = la + 60;
    if (colorBase + 1 <= bytes.length) {
      final declared = (bytes[colorBase] & 0xFF) + 1;
      final count = declared.clamp(1, 64);
      for (var i = 0; i < count && colorBase + 1 + i < bytes.length; i++) {
        final index = bytes[colorBase + 1 + i] & 0xFF;
        pattern.colors.add(
          index < _pecPalette.length
              ? _pecPalette[index]
              : _pecPalette[index % _pecPalette.length],
        );
      }
    }

    final blockStart = la + _pecHeaderSize;
    if (blockStart + 16 > bytes.length) {
      throw const EngineException('PEC 针迹块不完整');
    }
    final stitchStart = blockStart + 16; // 2+3+3+2+2+2+2
    var blockLength = _u24le(bytes, blockStart + 2);
    if (blockLength <= 16) blockLength = bytes.length - blockStart;
    final limitedEnd =
        math.min(bytes.length, math.min(blockStart + blockLength, bytes.length));

    var x = 0;
    var y = 0;
    var offset = stitchStart;
    var lastWasJump = false;
    while (offset < limitedEnd) {
      final first = bytes[offset];
      if (first == 0xFF) break;
      if (first == 0xFE &&
          offset + 1 < limitedEnd &&
          bytes[offset + 1] == 0xB0) {
        // 换色记录后跟一个交替字节
        offset += 3;
        pattern.stitches.add(Stitch(x, y, type: StitchType.colorChange));
        continue;
      }
      final dxResult = _readPecValue(bytes, offset, limitedEnd);
      if (dxResult == null) break;
      offset = dxResult.next;
      final dyResult = _readPecValue(bytes, offset, limitedEnd);
      if (dyResult == null) break;
      offset = dyResult.next;

      x += dxResult.value;
      y += dyResult.value;
      final jump = (dxResult.flags & 0x10) != 0;
      final trim = (dxResult.flags & 0x20) != 0;
      // 写出器在跳针后可能补一条零位移"落针锚点"，读回时忽略
      if (!jump &&
          !trim &&
          lastWasJump &&
          dxResult.value == 0 &&
          dyResult.value == 0) {
        lastWasJump = false;
        continue;
      }
      lastWasJump = jump;
      if (trim && !jump && dxResult.value == 0 && dyResult.value == 0) {
        pattern.stitches.add(Stitch(x, y, type: StitchType.trim));
        continue;
      }
      pattern.stitches.add(
        Stitch(x, y, type: jump ? StitchType.jump : StitchType.stitch),
      );
    }
    return pattern;
  }

  /// 读一个 PEC 坐标值；返回 null 表示数据不足。
  static ({int value, int flags, int next})? _readPecValue(
    Uint8List bytes,
    int offset,
    int end,
  ) {
    if (offset >= end) return null;
    final b0 = bytes[offset];
    if (b0 & 0x80 == 0) {
      var value = b0 & 0x7F;
      if (value >= 0x40) value -= 0x80;
      return (value: value, flags: 0, next: offset + 1);
    }
    if (offset + 1 >= end) return null;
    final b1 = bytes[offset + 1];
    var value = ((b0 & 0x0F) << 8) | b1;
    if (value >= 0x800) value -= 0x1000;
    return (value: value, flags: b0 & 0x30, next: offset + 2);
  }

  static void _writePecValue(
    ByteWriter writer,
    int value, {
    bool long = false,
    int flag = 0,
  }) {
    if (!long && value > -64 && value < 63) {
      writer.u8(value & 0x7F);
      return;
    }
    var packed = value & 0x0FFF;
    packed |= 0x8000;
    packed |= (flag & 0x30) << 8;
    writer
      ..u8((packed >> 8) & 0xFF)
      ..u8(packed & 0xFF);
  }

  static void _writePecStitches(ByteWriter writer, EmbroideryPattern pattern) {
    var xx = 0;
    var yy = 0;
    var jumping = true;
    var colorTwo = true;
    for (final stitch in pattern.stitches) {
      if (stitch.type == StitchType.trim) continue;
      final dx = stitch.x - xx;
      final dy = stitch.y - yy;
      xx = stitch.x;
      yy = stitch.y;
      switch (stitch.type) {
        case StitchType.stitch:
          if (jumping) {
            if (dx != 0 && dy != 0) {
              _writePecValue(writer, 0, long: true);
              _writePecValue(writer, 0, long: true);
            }
            jumping = false;
          }
          _writePecValue(writer, dx, long: true);
          _writePecValue(writer, dy, long: true);
        case StitchType.jump:
          jumping = true;
          _writePecValue(writer, dx, long: true, flag: 0x10);
          _writePecValue(writer, dy, long: true, flag: 0x10);
        case StitchType.colorChange:
          if (jumping) {
            _writePecValue(writer, 0, long: true);
            _writePecValue(writer, 0, long: true);
            jumping = false;
          }
          writer
            ..u8(0xFE)
            ..u8(0xB0)
            ..u8(colorTwo ? 0x02 : 0x01);
          colorTwo = !colorTwo;
        case StitchType.trim:
          break;
      }
    }
    writer.u8(0xFF);
  }

  // ═══════════════════════════ JEF ═══════════════════════════

  static const int _jefHeaderSize = 0x74;

  /// 读取 JEF（116 字节头 + 色表/线型表 + 2 字节位移）。
  static EmbroideryPattern decodeJef(Uint8List bytes) {
    if (bytes.length < _jefHeaderSize + 2) {
      throw const EngineException('JEF 文件过短');
    }
    var stitchOffset = _u32le(bytes, 0);
    if (stitchOffset < _jefHeaderSize || stitchOffset >= bytes.length) {
      stitchOffset = _jefHeaderSize;
    }
    final colorCount = _u32le(bytes, 24).clamp(0, 4096);
    final pattern = EmbroideryPattern(name: '');
    // 色表位于 0x74，每色 u32（Janome 线号），此处按索引映射到默认色
    const paletteBase = _jefHeaderSize;
    for (var i = 0; i < colorCount; i++) {
      final at = paletteBase + i * 4;
      var color = 0x7F7F7F;
      if (at + 4 <= bytes.length) {
        final index = _u32le(bytes, at);
        color = _pecPalette[index % _pecPalette.length];
      }
      pattern.colors.add(color);
    }

    var x = 0;
    var y = 0;
    var offset = stitchOffset;
    var guard = 0;
    while (offset < bytes.length && guard < 20000000) {
      guard++;
      final b0 = bytes[offset];
      if (b0 == 0x80) {
        if (offset + 1 >= bytes.length) break;
        final command = bytes[offset + 1];
        if (command == 0x10) break; // END
        if (command == 0x01 || command == 0x02) {
          if (offset + 3 >= bytes.length) break;
          final dx = _int8(bytes[offset + 2]);
          final dy = bytes[offset + 3];
          offset += 4;
          x += dx;
          y -= dy; // JEF 文件里 y 位移取反存储
          pattern.stitches.add(Stitch(
            x,
            y,
            type: command == 0x01 ? StitchType.colorChange : StitchType.jump,
          ));
          continue;
        }
        // 未知命令：跳过 2 字节
        offset += 2;
        continue;
      }
      if (offset + 1 >= bytes.length) break;
      final dx = _int8(b0);
      final dy = bytes[offset + 1];
      offset += 2;
      x += dx;
      y -= dy;
      pattern.stitches.add(Stitch(x, y));
    }
    return pattern;
  }

  /// 写出 JEF。
  static Uint8List encodeJef(EmbroideryPattern pattern) {
    final colorCount = math.max(1, pattern.colors.length);
    final bounds = pattern.bounds();
    final designWidth = bounds[2] - bounds[0];
    final designHeight = bounds[3] - bounds[1];
    final halfWidth = (designWidth / 2).round();
    final halfHeight = (designHeight / 2).round();

    // 统计记录个数：每针 1 条、跳针/换色 2 条（命令 + 位移）、结束 1 条
    var pointCount = 1;
    for (final stitch in pattern.stitches) {
      switch (stitch.type) {
        case StitchType.stitch:
          pointCount += 1;
        case StitchType.jump:
        case StitchType.colorChange:
          pointCount += 2;
        case StitchType.trim:
          break;
      }
    }

    final stitchOffset = _jefHeaderSize + colorCount * 8;
    final writer = ByteWriter()
      ..u32le(stitchOffset)
      ..u32le(0x14)
      ..ascii('20260101000000')
      ..u8(0)
      ..u8(0)
      ..u32le(colorCount)
      ..u32le(pointCount)
      ..u32le(_jefHoopSize(designWidth, designHeight))
      ..u32le(halfWidth)
      ..u32le(halfHeight)
      ..u32le(halfWidth)
      ..u32le(halfHeight);
    // 4 组绣花框边距，每组 4 个 u32
    final edges = <List<int>>[
      [550 - halfWidth, 550 - halfHeight, 550 - halfWidth, 550 - halfHeight],
      [250 - halfWidth, 250 - halfHeight, 250 - halfWidth, 250 - halfHeight],
      [700 - halfWidth, 1000 - halfHeight, 700 - halfWidth, 1000 - halfHeight],
      [700 - halfWidth, 1000 - halfHeight, 700 - halfWidth, 1000 - halfHeight],
    ];
    for (final group in edges) {
      if (group.every((value) => value >= 0)) {
        for (final value in group) {
          writer.u32le(value);
        }
      } else {
        for (var i = 0; i < 4; i++) {
          writer.u32le(0xFFFFFFFF);
        }
      }
    }
    assert(writer.length == _jefHeaderSize);
    // 色表（Janome 线号；这里按索引顺序近似）
    for (var i = 0; i < colorCount; i++) {
      writer.u32le(i);
    }
    for (var i = 0; i < colorCount; i++) {
      writer.u32le(0x0D);
    }

    var xx = 0;
    var yy = 0;
    void writeCommand(int command, int dx, int dy) {
      writer
        ..u8(0x80)
        ..u8(command)
        ..u8(dx & 0xFF)
        ..u8((-dy) & 0xFF);
    }

    for (final stitch in pattern.stitches) {
      final dx = (stitch.x - xx).clamp(-127, 127);
      final dy = (stitch.y - yy).clamp(-127, 127);
      xx = stitch.x;
      yy = stitch.y;
      switch (stitch.type) {
        case StitchType.stitch:
          writer
            ..u8(dx & 0xFF)
            ..u8((-dy) & 0xFF);
        case StitchType.jump:
          writeCommand(0x02, dx, dy);
        case StitchType.colorChange:
          writeCommand(0x01, dx, dy);
        case StitchType.trim:
          break;
      }
    }
    writer
      ..u8(0x80)
      ..u8(0x10);
    return writer.toBytes();
  }

  static int _jefHoopSize(int width, int height) {
    if (width < 500 && height < 500) return 1;
    if (width < 1260 && height < 1100) return 3;
    if (width < 1400 && height < 2000) return 2;
    if (width < 2000 && height < 2000) return 4;
    return 0;
  }

  // ═══════════════════════════ 位图 → 针迹 ═══════════════════════════

  /// 把位图转成蛇形填充针迹（1 像素 ≈ 0.1mm）。
  static EmbroideryPattern fromImage(
    img.Image image, {
    String name = '',
    int threshold = 128,
    int maxStitches = 20000,
  }) {
    if (image.width <= 0 || image.height <= 0) {
      throw const EngineException('输入图片尺寸为 0');
    }
    final pixelCount = image.width * image.height;
    var step = 1;
    if (pixelCount > maxStitches) {
      step = math.max(1, math.sqrt(pixelCount / maxStitches).ceil());
    }
    var width = image.width ~/ step;
    var height = image.height ~/ step;
    final resized = step == 1
        ? image
        : img.copyResize(
            image,
            width: math.max(1, width),
            height: math.max(1, height),
            interpolation: img.Interpolation.average,
          );
    width = resized.width;
    height = resized.height;

    final pattern = EmbroideryPattern(name: name, colors: <int>[0x000000]);
    int? lastX;
    int? lastY;
    for (var row = 0; row < height; row++) {
      final leftToRight = row.isEven;
      for (var column = 0; column < width; column++) {
        final x = leftToRight ? column : width - 1 - column;
        final pixel = resized.getPixel(x, row);
        final luminance =
            0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
        if (luminance >= threshold) continue;
        // 模型 y 轴向上：图像第 0 行对应最高 y
        final modelY = height - row;
        if (lastX == null || lastY == null) {
          pattern.stitches.add(Stitch(x, modelY, type: StitchType.jump));
        } else if (lastX != x || lastY != modelY) {
          final distance = (x - lastX).abs() + (modelY - lastY).abs();
          if (distance > 1) {
            pattern.stitches.add(Stitch(x, modelY, type: StitchType.jump));
          }
        }
        pattern.stitches.add(Stitch(x, modelY));
        lastX = x;
        lastY = modelY;
      }
    }
    return pattern;
  }

  // ═══════════════════════════ dst → png 预览 ═══════════════════════════

  /// 把绣花图案渲染成 PNG 预览（跳针不画线，自动居中）。
  static Uint8List renderPreviewPng(
    EmbroideryPattern pattern, {
    double scale = 2.0,
    int margin = 6,
    String background = '#ffffff',
    String color = '#1e88e5',
  }) {
    final bounds = pattern.bounds();
    final spanX = bounds[2] - bounds[0];
    final spanY = bounds[3] - bounds[1];
    // scale = 每毫米像素数；模型单位 0.1mm → 每单位 scale/10 像素
    final pixelsPerUnit = math.max(0.005, scale / 10.0);
    var width = (spanX * pixelsPerUnit).ceil() + margin * 2;
    var height = (spanY * pixelsPerUnit).ceil() + margin * 2;
    width = width.clamp(16, 20000);
    height = height.clamp(16, 20000);
    if (spanX == 0) width = math.max(width, 16);
    if (spanY == 0) height = math.max(height, 16);

    final image = img.Image(width: width, height: height, numChannels: 3);
    final backgroundRgb = _parseHexColor(background, 0xFFFFFF);
    img.fill(
      image,
      color: img.ColorRgb8(
        (backgroundRgb >> 16) & 0xFF,
        (backgroundRgb >> 8) & 0xFF,
        backgroundRgb & 0xFF,
      ),
    );
    final lineRgb = _parseHexColor(color, 0x1E88E5);
    final lineColor = img.ColorRgb8(
      (lineRgb >> 16) & 0xFF,
      (lineRgb >> 8) & 0xFF,
      lineRgb & 0xFF,
    );

    int screenX(int modelX) =>
        margin + ((modelX - bounds[0]) * pixelsPerUnit).round();
    // 模型 y 向上 → 屏幕 y 向下
    int screenY(int modelY) =>
        margin + ((bounds[3] - modelY) * pixelsPerUnit).round();

    Stitch? previousDrawable;
    for (final stitch in pattern.stitches) {
      if (stitch.type == StitchType.colorChange ||
          stitch.type == StitchType.trim) {
        continue;
      }
      if (stitch.type == StitchType.jump) {
        // 跳针不画线，但会改变"上一落针位置"
        previousDrawable = stitch;
        continue;
      }
      if (previousDrawable != null &&
          previousDrawable.type == StitchType.stitch) {
        img.drawLine(
          image,
          x1: screenX(previousDrawable.x),
          y1: screenY(previousDrawable.y),
          x2: screenX(stitch.x),
          y2: screenY(stitch.y),
          color: lineColor,
          thickness: 1,
          antialias: true,
        );
      }
      previousDrawable = stitch;
    }
    return img.encodePng(image, level: 6);
  }

  // ═══════════════════════════ 小工具 ═══════════════════════════

  static int _parseHexColor(String text, int fallback) {
    var value = text.trim();
    if (value.startsWith('#')) value = value.substring(1);
    if (value.length == 3) {
      value = value.split('').map((c) => '$c$c').join();
    }
    if (value.length == 8) value = value.substring(2);
    return int.tryParse(value, radix: 16) ?? fallback;
  }

  static int _int8(int byte) => byte >= 0x80 ? byte - 0x100 : byte;

  static bool _asciiEquals(Uint8List bytes, int offset, String text) {
    if (offset + text.length > bytes.length) return false;
    for (var i = 0; i < text.length; i++) {
      if (bytes[offset + i] != text.codeUnitAt(i)) return false;
    }
    return true;
  }

  static int _u32le(Uint8List bytes, int offset) {
    if (offset + 4 > bytes.length) return 0;
    return (bytes[offset] |
            (bytes[offset + 1] << 8) |
            (bytes[offset + 2] << 16) |
            (bytes[offset + 3] << 24)) &
        0xFFFFFFFF;
  }

  static int _u24le(Uint8List bytes, int offset) {
    if (offset + 3 > bytes.length) return 0;
    return bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16);
  }

  static int _findAscii(Uint8List bytes, String needle, int start) {
    for (var i = start; i + needle.length <= bytes.length; i++) {
      if (_asciiEquals(bytes, i, needle)) return i;
    }
    return -1;
  }
}
