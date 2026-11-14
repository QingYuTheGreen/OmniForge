import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../engine_utils.dart';
import '../i_engine.dart';

/// 位图 → SVG 真矢量引擎（纯 Dart）。
///
/// 处理流程：
/// 1. 用 `package:image` 解码位图，超大图先等比缩到长边 ≤ [max_size]；
/// 2. 中位切分（median cut）量化出 [colors] 种颜色；
/// 3. 每个像素按最近的调色板颜色重新着色；
/// 4. 沿像素栅格的有向边界边追踪出闭合轮廓环（外轮廓与内部空洞都保留）；
/// 5. 用 Douglas–Peucker 按 [tolerance] 简化轮廓；
/// 6. 按面积从大到小输出 `<path>`（同一颜色的所有环合成一个 path，
///    `fill-rule="evenodd"` 保证空洞正确镂空）。
class SvgVectorEngine extends SimpleEngine {
  const SvgVectorEngine();

  @override
  String get id => 'svg_vector';

  /// 轮廓总点数超过该值时提高简化容差，避免 SVG 体积失控。
  static const int _maxTotalPoints = 80000;

  /// 单个颜色的环数量/路径数量兜底上限。
  static const int _maxPaths = 12000;

  @override
  Future<void> execute(EngineContext context) async {
    final bytes = await readFileBytes(context.inputPath);
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const EngineException('无法解码输入图片');
    }

    final maxSize = intParam(context, 'max_size', 512).clamp(16, 4096);
    final colorCount = intParam(context, 'colors', 16).clamp(2, 64);
    final tolerance = doubleParam(context, 'tolerance', 1.5).clamp(0.1, 24.0);

    final image = _limitSize(decoded, maxSize);
    final width = image.width;
    final height = image.height;
    if (width <= 0 || height <= 0) {
      throw const EngineException('输入图片尺寸无效');
    }

    final palette = _quantize(image, colorCount);
    final indices = _mapToPalette(image, palette);
    final rawLoops = _traceLoops(indices, width, height, palette.length);

    var paths = <_SvgPath>[];
    var effectiveTolerance = tolerance;
    for (var attempt = 0; attempt < 6; attempt++) {
      paths = _simplifyPaths(rawLoops, palette, effectiveTolerance);
      if (paths.isEmpty) break;
      final points = paths.fold<int>(
        0,
        (sum, path) =>
            sum + path.loops.fold<int>(0, (n, loop) => n + loop.length ~/ 2),
      );
      if (points <= _maxTotalPoints || attempt == 5) break;
      effectiveTolerance *= 1.8;
    }

    // 按面积从大到小排序；面积极小的噪点已经在简化时被过滤。
    paths.sort((a, b) => b.area.compareTo(a.area));
    if (paths.length > _maxPaths) {
      paths = paths.sublist(0, _maxPaths);
    }
    final canvasArea = width * height.toDouble();
    if (paths.isEmpty) {
      // 退化兜底：整张图用一个矩形覆盖，保证输出仍是合法 SVG。
      paths = <_SvgPath>[
        _SvgPath(palette.first, canvasArea, <List<int>>[
          <int>[0, 0, width, 0, width, height, 0, height],
        ]),
      ];
    } else {
      // 面积覆盖不足时（例如强噪点/抖动图，绝大多数微小轮廓被当成噪点
      // 过滤掉），用出现频率最高的颜色补一层满幅背景，避免输出近乎空白。
      final covered = paths.fold<double>(0, (sum, path) => sum + path.area);
      if (covered < canvasArea * 0.6) {
        paths.insert(
          0,
          _SvgPath(palette.first, canvasArea, <List<int>>[
            <int>[0, 0, width, 0, width, height, 0, height],
          ]),
        );
      }
    }

    final svg = _buildSvg(paths, width, height);
    await writeFileText(context.outputPath, svg);
  }

  // ─────────────────────────── 预处理 ───────────────────────────

  /// 限制长边尺寸，并把透明通道铺到白底上（保证量化结果不出现黑边）。
  img.Image _limitSize(img.Image image, int maxSize) {
    var result = image;
    final longest = math.max(image.width, image.height);
    if (longest > maxSize) {
      final scale = maxSize / longest;
      final width = math.max(1, (image.width * scale).round());
      final height = math.max(1, (image.height * scale).round());
      result = img.copyResize(
        image,
        width: width,
        height: height,
        interpolation: img.Interpolation.average,
      );
    }
    if (result.hasAlpha) {
      final canvas = img.Image(
        width: result.width,
        height: result.height,
        numChannels: 3,
      );
      img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
      img.compositeImage(canvas, result);
      result = canvas;
    }
    return result;
  }

  // ─────────────────────────── 颜色量化 ───────────────────────────

  /// 中位切分量化，返回按像素数量从多到少排列的 `0xRRGGBB` 颜色表。
  List<int> _quantize(img.Image image, int colorCount) {
    final bins = <int, _ColorBin>{};
    for (final pixel in image) {
      final r = _channel255(pixel.rNormalized);
      final g = _channel255(pixel.gNormalized);
      final b = _channel255(pixel.bNormalized);
      final key = ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3);
      var bin = bins[key];
      if (bin == null) {
        bin = _ColorBin(r >> 3, g >> 3, b >> 3);
        bins[key] = bin;
      }
      bin
        ..count += 1
        ..sumR += r
        ..sumG += g
        ..sumB += b;
    }

    final boxes = <List<_ColorBin>>[bins.values.toList(growable: false)];
    while (boxes.length < colorCount) {
      var bestIndex = -1;
      var bestScore = -1.0;
      for (var i = 0; i < boxes.length; i++) {
        final box = boxes[i];
        if (box.length < 2) continue;
        final range = _boxRange(box);
        if (range < 1) continue;
        final weight =
            box.fold<int>(0, (sum, bin) => sum + bin.count).toDouble();
        final score = range * math.sqrt(weight);
        if (score > bestScore) {
          bestScore = score;
          bestIndex = i;
        }
      }
      if (bestIndex < 0) break;
      final split = _splitBox(boxes[bestIndex]);
      if (split == null) break;
      boxes[bestIndex] = split[0];
      boxes.add(split[1]);
    }

    final weighted = <_WeightedColor>[
      for (final box in boxes) _averageColor(box),
    ]..sort((a, b) => b.weight.compareTo(a.weight));
    final palette = <int>[];
    for (final entry in weighted) {
      if (!palette.contains(entry.packed)) palette.add(entry.packed);
    }
    return palette.isEmpty ? const <int>[0x000000] : palette;
  }

  int _channel255(num normalized) =>
      (normalized * 255).round().clamp(0, 255);

  /// 盒子内三个通道中最大的取值范围。
  int _boxRange(List<_ColorBin> box) {
    var range = 0;
    for (var channel = 0; channel < 3; channel++) {
      var low = 32;
      var high = -1;
      for (final bin in box) {
        final value = bin.channel(channel);
        if (value < low) low = value;
        if (value > high) high = value;
      }
      if (high - low > range) range = high - low;
    }
    return range;
  }

  /// 沿取值范围最大的通道，按像素数量中位数切成两个盒子。
  List<List<_ColorBin>>? _splitBox(List<_ColorBin> box) {
    var splitChannel = -1;
    var bestRange = 0;
    for (var channel = 0; channel < 3; channel++) {
      var low = 32;
      var high = -1;
      for (final bin in box) {
        final value = bin.channel(channel);
        if (value < low) low = value;
        if (value > high) high = value;
      }
      if (high - low > bestRange) {
        bestRange = high - low;
        splitChannel = channel;
      }
    }
    if (splitChannel < 0 || bestRange < 1) return null;

    final sorted = List<_ColorBin>.from(box)
      ..sort((a, b) =>
          a.channel(splitChannel).compareTo(b.channel(splitChannel)));
    var total = 0;
    for (final bin in sorted) {
      total += bin.count;
    }
    var accumulated = 0;
    var splitAt = 0;
    for (var i = 0; i < sorted.length; i++) {
      accumulated += sorted[i].count;
      if (accumulated * 2 >= total) {
        splitAt = i;
        break;
      }
    }
    if (splitAt >= sorted.length - 1) splitAt = sorted.length - 2;
    if (splitAt < 0) return null;
    return <List<_ColorBin>>[
      sorted.sublist(0, splitAt + 1),
      sorted.sublist(splitAt + 1),
    ];
  }

  _WeightedColor _averageColor(List<_ColorBin> box) {
    var count = 0;
    var red = 0;
    var green = 0;
    var blue = 0;
    for (final bin in box) {
      count += bin.count;
      red += bin.sumR;
      green += bin.sumG;
      blue += bin.sumB;
    }
    if (count == 0) return const _WeightedColor(0, 0);
    final r = (red / count).round().clamp(0, 255);
    final g = (green / count).round().clamp(0, 255);
    final b = (blue / count).round().clamp(0, 255);
    return _WeightedColor((r << 16) | (g << 8) | b, count);
  }

  // ─────────────────────────── 像素着色 ───────────────────────────

  /// 每个像素映射到调色板下标（同一 5bit 桶只算一次，兼顾速度）。
  Uint8List _mapToPalette(img.Image image, List<int> palette) {
    final indices = Uint8List(image.width * image.height);
    final cache = <int, int>{};
    var i = 0;
    for (final pixel in image) {
      final r = _channel255(pixel.rNormalized);
      final g = _channel255(pixel.gNormalized);
      final b = _channel255(pixel.bNormalized);
      final key = ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3);
      var index = cache[key];
      if (index == null) {
        index = _nearestColor(palette, r, g, b);
        cache[key] = index;
      }
      indices[i++] = index;
    }
    return indices;
  }

  int _nearestColor(List<int> palette, int red, int green, int blue) {
    var best = 0;
    var bestDistance = 1 << 30;
    for (var i = 0; i < palette.length; i++) {
      final color = palette[i];
      final dr = ((color >> 16) & 0xFF) - red;
      final dg = ((color >> 8) & 0xFF) - green;
      final db = (color & 0xFF) - blue;
      final distance = dr * dr + dg * dg + db * db;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = i;
      }
    }
    return best;
  }

  // ─────────────────────────── 轮廓追踪 ───────────────────────────

  /// 对每种颜色构造“有向边界边”栅格，再追踪成闭合环。
  ///
  /// 顶点坐标范围是 `(0..width, 0..height)`，每个顶点最多 4 条出边。
  /// 低 4 位表示该方向存在边，高 4 位表示该方向已经走过。
  List<List<List<int>>> _traceLoops(
    Uint8List indices,
    int width,
    int height,
    int colorCount,
  ) {
    final stride = width + 1;
    final grids = List<Uint8List>.generate(
      colorCount,
      (_) => Uint8List(stride * (height + 1)),
    );

    for (var y = 0; y < height; y++) {
      final row = y * width;
      final base = y * stride;
      final nextBase = (y + 1) * stride;
      for (var x = 0; x < width; x++) {
        final color = indices[row + x];
        final grid = grids[color];
        // 上方边缘：tail=(x,y) → head=(x+1,y)，方向 0（右）
        if (y == 0 || indices[row - width + x] != color) {
          grid[base + x] |= 0x01;
        }
        // 右侧边缘：tail=(x+1,y) → head=(x+1,y+1)，方向 1（下）
        if (x == width - 1 || indices[row + x + 1] != color) {
          grid[base + x + 1] |= 0x02;
        }
        // 下方边缘：tail=(x+1,y+1) → head=(x,y+1)，方向 2（左）
        if (y == height - 1 || indices[row + width + x] != color) {
          grid[nextBase + x + 1] |= 0x04;
        }
        // 左侧边缘：tail=(x,y+1) → head=(x,y)，方向 3（上）
        if (x == 0 || indices[row + x - 1] != color) {
          grid[nextBase + x] |= 0x08;
        }
      }
    }

    return <List<List<int>>>[
      for (var color = 0; color < colorCount; color++)
        _traceGrid(grids[color], stride, width, height),
    ];
  }

  List<List<int>> _traceGrid(
    Uint8List grid,
    int stride,
    int width,
    int height,
  ) {
    final loops = <List<int>>[];
    final maxSteps = 4 * (width + 1) * (height + 1);

    for (var y = 0; y <= height; y++) {
      final base = y * stride;
      for (var x = 0; x <= width; x++) {
        final start = base + x;
        for (var direction = 0; direction < 4; direction++) {
          final present = 1 << direction;
          final used = present << 4;
          final flags = grid[start];
          if ((flags & present) == 0 || (flags & used) != 0) continue;

          final path = <int>[x, y];
          var cursorX = x;
          var cursorY = y;
          var cursorDirection = direction;
          var steps = 0;

          while (true) {
            // 标记当前方向这条边已走过（方向 d 的已走位在 bit d+4）。
            grid[cursorY * stride + cursorX] |= 1 << (cursorDirection + 4);
            switch (cursorDirection) {
              case 0:
                cursorX++;
                break;
              case 1:
                cursorY++;
                break;
              case 2:
                cursorX--;
                break;
              default:
                cursorY--;
                break;
            }
            // 回到起点说明闭合，起点已在 path 首位，不必重复写入。
            if (cursorX == x && cursorY == y) break;
            path
              ..add(cursorX)
              ..add(cursorY);

            final vertex = grid[cursorY * stride + cursorX];
            var next = -1;
            // 优先右转（保持区域在行进方向右侧），其次直行，最后左转。
            final preferred = <int>[
              (cursorDirection + 1) & 3,
              cursorDirection,
              (cursorDirection + 3) & 3,
            ];
            for (final candidate in preferred) {
              final bit = 1 << candidate;
              if ((vertex & bit) != 0 && (vertex & (bit << 4)) == 0) {
                next = candidate;
                break;
              }
            }
            if (next < 0) {
              for (var candidate = 0; candidate < 4; candidate++) {
                if (candidate == ((cursorDirection + 2) & 3)) continue;
                final bit = 1 << candidate;
                if ((vertex & bit) != 0 && (vertex & (bit << 4)) == 0) {
                  next = candidate;
                  break;
                }
              }
            }
            if (next < 0) break;
            cursorDirection = next;
            if (++steps > maxSteps) break;
          }

          if (path.length >= 6) loops.add(path);
        }
      }
    }
    return loops;
  }

  // ─────────────────────────── 轮廓简化 ───────────────────────────

  List<_SvgPath> _simplifyPaths(
    List<List<List<int>>> rawLoops,
    List<int> palette,
    double tolerance,
  ) {
    final paths = <_SvgPath>[];
    for (var color = 0; color < rawLoops.length; color++) {
      final loops = <List<int>>[];
      var totalArea = 0.0;
      for (final raw in rawLoops[color]) {
        final area = _polygonArea(raw);
        // 过滤极小的噪点区域（面积不足约 2.5 个像素）。
        if (area < 2.5) continue;
        final simplified = _simplifyClosed(raw, tolerance);
        if (simplified == null) continue;
        loops.add(simplified);
        totalArea += area;
      }
      if (loops.isEmpty) continue;
      paths.add(_SvgPath(palette[color], totalArea, loops));
    }
    return paths;
  }

  /// 鞋带公式求闭合多边形面积（像素²）。
  double _polygonArea(List<int> points) {
    final count = points.length ~/ 2;
    if (count < 3) return 0;
    var twiceArea = 0.0;
    for (var i = 0; i < count; i++) {
      final j = (i + 1) % count;
      twiceArea += points[i * 2] * points[j * 2 + 1] -
          points[j * 2] * points[i * 2 + 1];
    }
    return twiceArea.abs() / 2;
  }

  /// 闭合环的 Douglas–Peucker：在距起点最远的点处切成两条开链分别简化。
  List<int>? _simplifyClosed(List<int> points, double tolerance) {
    final count = points.length ~/ 2;
    if (count < 3) return null;
    final xs = List<int>.generate(count, (i) => points[i * 2]);
    final ys = List<int>.generate(count, (i) => points[i * 2 + 1]);

    final startX = xs[0];
    final startY = ys[0];
    var farthest = 1;
    var farthestDistance = -1;
    for (var i = 1; i < count; i++) {
      final dx = xs[i] - startX;
      final dy = ys[i] - startY;
      final distance = dx * dx + dy * dy;
      if (distance > farthestDistance) {
        farthestDistance = distance;
        farthest = i;
      }
    }
    if (farthest <= 0) return null;

    final arcA = <int>[for (var i = 0; i <= farthest; i++) i];
    final arcB = <int>[
      for (var i = farthest; i < count; i++) i,
      0,
    ];
    final keptA = _douglasPeucker(xs, ys, arcA, tolerance);
    final keptB = _douglasPeucker(xs, ys, arcB, tolerance);

    final result = <int>[...keptA];
    // keptB 首尾分别与 keptA 尾部/首部重合，去掉重复。
    for (var i = 1; i < keptB.length - 1; i++) {
      result.add(keptB[i]);
    }
    if (result.length < 3) return null;
    return <int>[
      for (final index in result) ...<int>[xs[index], ys[index]],
    ];
  }

  /// 迭代版 Douglas–Peucker（避免长轮廓递归过深）。
  List<int> _douglasPeucker(
    List<int> xs,
    List<int> ys,
    List<int> indices,
    double tolerance,
  ) {
    final keep = List<bool>.filled(indices.length, false);
    keep[0] = true;
    keep[indices.length - 1] = true;
    final toleranceSquared = tolerance * tolerance;
    final stack = <List<int>>[
      <int>[0, indices.length - 1],
    ];
    while (stack.isNotEmpty) {
      final range = stack.removeLast();
      final low = range[0];
      final high = range[1];
      if (high <= low + 1) continue;
      final ax = xs[indices[low]];
      final ay = ys[indices[low]];
      final bx = xs[indices[high]];
      final by = ys[indices[high]];
      var maxDistance = -1.0;
      var maxIndex = -1;
      for (var i = low + 1; i < high; i++) {
        final distance = _pointSegmentDistanceSquared(
          xs[indices[i]],
          ys[indices[i]],
          ax,
          ay,
          bx,
          by,
        );
        if (distance > maxDistance) {
          maxDistance = distance;
          maxIndex = i;
        }
      }
      if (maxDistance > toleranceSquared && maxIndex > low) {
        keep[maxIndex] = true;
        stack
          ..add(<int>[low, maxIndex])
          ..add(<int>[maxIndex, high]);
      }
    }
    return <int>[
      for (var i = 0; i < indices.length; i++)
        if (keep[i]) indices[i],
    ];
  }

  double _pointSegmentDistanceSquared(
    int px,
    int py,
    int ax,
    int ay,
    int bx,
    int by,
  ) {
    final dx = bx - ax;
    final dy = by - ay;
    final lengthSquared = dx * dx + dy * dy;
    if (lengthSquared == 0) {
      final ex = px - ax;
      final ey = py - ay;
      return (ex * ex + ey * ey).toDouble();
    }
    var t = ((px - ax) * dx + (py - ay) * dy) / lengthSquared;
    if (t < 0) t = 0;
    if (t > 1) t = 1;
    final nearestX = ax + dx * t;
    final nearestY = ay + dy * t;
    final ex = px - nearestX;
    final ey = py - nearestY;
    return ex * ex + ey * ey;
  }

  // ─────────────────────────── SVG 输出 ───────────────────────────

  String _buildSvg(List<_SvgPath> paths, int width, int height) {
    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln(
        '<svg xmlns="http://www.w3.org/2000/svg" '
        'width="$width" height="$height" viewBox="0 0 $width $height">',
      );
    for (final path in paths) {
      final data = StringBuffer();
      for (final loop in path.loops) {
        if (data.isNotEmpty) data.write(' ');
        data
          ..write('M${loop[0]} ${loop[1]}')
          ..write('L${loop[2]} ${loop[3]}');
        for (var i = 4; i < loop.length; i += 2) {
          data.write(' ${loop[i]} ${loop[i + 1]}');
        }
        data.write('Z');
      }
      final hex = path.color.toRadixString(16).padLeft(6, '0');
      buffer
        ..write('<path fill="#$hex" fill-rule="evenodd" d="')
        ..write(data.toString())
        ..writeln('"/>');
    }
    buffer.writeln('</svg>');
    return buffer.toString();
  }
}

/// 5bit 颜色直方图桶。
class _ColorBin {
  _ColorBin(this.r, this.g, this.b);

  final int r;
  final int g;
  final int b;
  int count = 0;
  int sumR = 0;
  int sumG = 0;
  int sumB = 0;

  int channel(int index) {
    switch (index) {
      case 0:
        return r;
      case 1:
        return g;
      default:
        return b;
    }
  }
}

/// 量化后的一种颜色及其覆盖的像素数。
class _WeightedColor {
  const _WeightedColor(this.packed, this.weight);

  final int packed;
  final int weight;
}

/// 一种颜色的 SVG 路径（可能包含外轮廓 + 空洞等多个子路径）。
class _SvgPath {
  _SvgPath(this.color, this.area, this.loops);

  final int color;
  final double area;
  final List<List<int>> loops;
}
