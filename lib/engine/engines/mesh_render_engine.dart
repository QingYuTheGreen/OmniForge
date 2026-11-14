import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../engine_utils.dart';
import '../i_engine.dart';
import 'mesh_engine.dart';
import 'mesh_io.dart';

/// 3D 网格 → 位图引擎：用纯 Dart 软件光栅化把 obj/ply/off/stl/gltf/glb
/// 渲染为 png / jpg（正交投影 + z-buffer + Flat/Lambert 着色）。
class MeshRenderEngine extends SimpleEngine {
  const MeshRenderEngine();

  @override
  String get id => 'render3d';

  /// 三角面数量上限：超过后直接拒绝，避免离线设备内存/耗时失控。
  static const int _maxTriangles = 2000000;

  /// 模型在画面里占的最大比例（留边）。
  static const double _viewportFill = 0.88;

  /// 渲染缓冲区单边上限（超采样后也不超过该值）。
  static const int _maxRenderSide = 4096;

  static final Vec3 _light = _normalize(const Vec3(-0.4, -0.7, 1.0));

  static const double _ambient = 0.28;

  @override
  Future<void> execute(EngineContext context) async {
    final target = context.targetFormat.toLowerCase();
    if (target != 'png' && target != 'jpg' && target != 'jpeg') {
      throw const EngineException('render3d 仅支持 png/jpg 输出');
    }

    final width = intParam(context, 'width', 800).clamp(64, 4096).toInt();
    final height = intParam(context, 'height', 600).clamp(64, 4096).toInt();
    final supersample = boolParam(context, 'supersample', true) &&
        width * 2 <= _maxRenderSide &&
        height * 2 <= _maxRenderSide;

    final mesh = readMesh(context.inputPath).normalized();
    if (mesh.vertices.isEmpty || mesh.faces.isEmpty) {
      throw const EngineException('网格文件为空或没有三角面');
    }
    if (mesh.faces.length > _maxTriangles) {
      throw const EngineException('模型面数过多');
    }

    final background = _parseColor(
      stringParam(context, 'background', '#ffffff'),
      (255, 255, 255),
    );
    final baseColor = _parseColor(
      stringParam(context, 'color', '#4a90d9'),
      (0x4a, 0x90, 0xd9),
    );

    final scaleFactor = supersample ? 2 : 1;
    final canvasWidth = width * scaleFactor;
    final canvasHeight = height * scaleFactor;

    final rotated = _rotateVertices(mesh, context);
    final projected = _project(rotated, canvasWidth, canvasHeight);
    final raster = _Raster(canvasWidth, canvasHeight, background);
    raster.depthBias = math.max(1e-9,
        (projected.maxZ - projected.minZ) * 2e-3);
    raster.drawTriangles(
      projected.vertices,
      mesh.faces,
      _shadeFaces(rotated, mesh.faces, baseColor),
    );
    if (boolParam(context, 'wireframe', false)) {
      raster.drawWireframe(projected.vertices, mesh.faces, baseColor);
    }

    var image = raster.toImage();
    if (supersample) {
      image = img.copyResize(
        image,
        width: width,
        height: height,
        interpolation: img.Interpolation.average,
      );
    }

    final bytes = target == 'png'
        ? img.encodePng(image, level: 6)
        : img.encodeJpg(image, quality: 90);
    await writeFileBytes(context.outputPath, bytes);
  }

  // ───────────────────────── 几何变换 ─────────────────────────

  /// 平移到包围盒中心后按 rot_y、rot_x 旋转（角度制）。
  List<Vec3> _rotateVertices(MeshData mesh, EngineContext context) {
    var minX = double.infinity;
    var minY = double.infinity;
    var minZ = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    var maxZ = -double.infinity;
    for (final v in mesh.vertices) {
      if (!v.isFinite) continue;
      minX = math.min(minX, v.x);
      minY = math.min(minY, v.y);
      minZ = math.min(minZ, v.z);
      maxX = math.max(maxX, v.x);
      maxY = math.max(maxY, v.y);
      maxZ = math.max(maxZ, v.z);
    }
    if (!minX.isFinite) {
      minX = 0;
      minY = 0;
      minZ = 0;
      maxX = 0;
      maxY = 0;
      maxZ = 0;
    }
    final cx = (minX + maxX) / 2;
    final cy = (minY + maxY) / 2;
    final cz = (minZ + maxZ) / 2;

    final rx = doubleParam(context, 'rot_x', 25) * math.pi / 180;
    final ry = doubleParam(context, 'rot_y', 30) * math.pi / 180;
    final cosX = math.cos(rx), sinX = math.sin(rx);
    final cosY = math.cos(ry), sinY = math.sin(ry);

    final result = <Vec3>[];
    for (final v in mesh.vertices) {
      if (!v.isFinite) {
        result.add(const Vec3(0, 0, 0));
        continue;
      }
      final x0 = v.x - cx;
      final y0 = v.y - cy;
      final z0 = v.z - cz;
      // 绕 Y 轴
      final x1 = x0 * cosY + z0 * sinY;
      final z1 = -x0 * sinY + z0 * cosY;
      // 绕 X 轴
      final y2 = y0 * cosX - z1 * sinX;
      final z2 = y0 * sinX + z1 * cosX;
      result.add(Vec3(x1, y2, z2));
    }
    return result;
  }

  /// 正交投影到屏幕坐标（y 轴翻转），并按视口缩放居中。
  _Projection _project(List<Vec3> rotated, int width, int height) {
    var minX = double.infinity;
    var minY = double.infinity;
    var minZ = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    var maxZ = -double.infinity;
    for (final v in rotated) {
      minX = math.min(minX, v.x);
      minY = math.min(minY, v.y);
      minZ = math.min(minZ, v.z);
      maxX = math.max(maxX, v.x);
      maxY = math.max(maxY, v.y);
      maxZ = math.max(maxZ, v.z);
    }
    final spanX = maxX - minX;
    final spanY = maxY - minY;
    var scaleX = width * _viewportFill / (spanX > 1e-12 ? spanX : 1);
    var scaleY = height * _viewportFill / (spanY > 1e-12 ? spanY : 1);
    var scale = math.min(scaleX, scaleY);
    if (!scale.isFinite || scale <= 0) {
      scale = 1;
      scaleX = 1;
      scaleY = 1;
    }
    final midX = (minX + maxX) / 2;
    final midY = (minY + maxY) / 2;
    final vertices = <_ScreenVertex>[
      for (final v in rotated)
        _ScreenVertex(
          width / 2 + (v.x - midX) * scale,
          height / 2 - (v.y - midY) * scale,
          v.z,
        ),
    ];
    return _Projection(
      vertices,
      minZ.isFinite ? minZ : 0,
      maxZ.isFinite ? maxZ : 0,
    );
  }

  /// 逐面 Flat/Lambert 着色：环境光 + 固定方向光的漫反射。
  List<(int, int, int)> _shadeFaces(
    List<Vec3> rotated,
    List<List<int>> faces,
    (int, int, int) base,
  ) {
    final colors = <(int, int, int)>[];
    for (final face in faces) {
      if (face.length < 3) {
        colors.add(base);
        continue;
      }
      final a = rotated[face[0]];
      final b = rotated[face[1]];
      final c = rotated[face[2]];
      final normal = _normalize(_cross(_sub(b, a), _sub(c, a)));
      // 双面光照：面的绕序不一致时也不会全黑。
      final lambert = _ambient +
          (1 - _ambient) *
              (normal.x * _light.x + normal.y * _light.y + normal.z * _light.z)
                  .abs();
      final intensity = lambert.clamp(0.0, 1.0);
      colors.add((
        (base.$1 * intensity).round().clamp(0, 255).toInt(),
        (base.$2 * intensity).round().clamp(0, 255).toInt(),
        (base.$3 * intensity).round().clamp(0, 255).toInt(),
      ));
    }
    return colors;
  }
}

// ───────────────────────── 光栅化 ─────────────────────────

class _ScreenVertex {
  const _ScreenVertex(this.x, this.y, this.z);

  final double x;
  final double y;

  /// 视图空间深度（越大越靠近相机）。
  final double z;
}

class _Projection {
  const _Projection(this.vertices, this.minZ, this.maxZ);

  final List<_ScreenVertex> vertices;
  final double minZ;
  final double maxZ;
}

/// 软件光栅器：RGB 像素缓冲 + z-buffer。
class _Raster {
  _Raster(this.width, this.height, (int, int, int) background)
      : pixels = Uint8List(width * height * 3),
        depth = Float64List(width * height) {
    for (var i = 0; i < depth.length; i++) {
      depth[i] = double.negativeInfinity;
    }
    final (r, g, b) = background;
    for (var i = 0; i < pixels.length; i += 3) {
      pixels[i] = r;
      pixels[i + 1] = g;
      pixels[i + 2] = b;
    }
  }

  final int width;
  final int height;
  final Uint8List pixels;
  final Float64List depth;

  /// 线框覆盖时的深度偏移，避免被同一三角形的填充面挡住。
  double depthBias = 1e-9;

  void drawTriangles(
    List<_ScreenVertex> vertices,
    List<List<int>> faces,
    List<(int, int, int)> colors,
  ) {
    for (var i = 0; i < faces.length; i++) {
      final face = faces[i];
      if (face.length < 3 || i >= colors.length) continue;
      _fillTriangle(
        vertices[face[0]],
        vertices[face[1]],
        vertices[face[2]],
        colors[i],
      );
    }
  }

  void _fillTriangle(
    _ScreenVertex a,
    _ScreenVertex b,
    _ScreenVertex c,
    (int, int, int) color,
  ) {
    final area = (b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y);
    if (area.abs() < 1e-12) return;
    final minX = math.max(
      0,
      math.min(a.x, math.min(b.x, c.x)).floor(),
    );
    final maxX = math.min(
      width - 1,
      math.max(a.x, math.max(b.x, c.x)).ceil(),
    );
    final minY = math.max(
      0,
      math.min(a.y, math.min(b.y, c.y)).floor(),
    );
    final maxY = math.min(
      height - 1,
      math.max(a.y, math.max(b.y, c.y)).ceil(),
    );
    if (minX > maxX || minY > maxY) return;

    final invArea = 1 / area;
    final (r, g, bl) = color;
    for (var y = minY; y <= maxY; y++) {
      final py = y + 0.5;
      final rowOffset = y * width;
      for (var x = minX; x <= maxX; x++) {
        final px = x + 0.5;
        final w0 =
            (c.x - b.x) * (py - b.y) - (c.y - b.y) * (px - b.x);
        final w1 =
            (a.x - c.x) * (py - c.y) - (a.y - c.y) * (px - c.x);
        final w2 =
            (b.x - a.x) * (py - a.y) - (b.y - a.y) * (px - a.x);
        if (area > 0) {
          if (w0 < 0 || w1 < 0 || w2 < 0) continue;
        } else {
          if (w0 > 0 || w1 > 0 || w2 > 0) continue;
        }
        final l0 = w0 * invArea;
        final l1 = w1 * invArea;
        final l2 = w2 * invArea;
        final z = l0 * a.z + l1 * b.z + l2 * c.z;
        final index = rowOffset + x;
        if (z <= depth[index]) continue;
        depth[index] = z;
        final offset = index * 3;
        pixels[offset] = r;
        pixels[offset + 1] = g;
        pixels[offset + 2] = bl;
      }
    }
  }

  void drawWireframe(
    List<_ScreenVertex> vertices,
    List<List<int>> faces,
    (int, int, int) base,
  ) {
    final color = (
      (base.$1 * 0.18).round().clamp(0, 255).toInt(),
      (base.$2 * 0.18).round().clamp(0, 255).toInt(),
      (base.$3 * 0.18).round().clamp(0, 255).toInt(),
    );
    for (final face in faces) {
      if (face.length < 2) continue;
      for (var i = 0; i < face.length; i++) {
        _drawEdge(
          vertices[face[i]],
          vertices[face[(i + 1) % face.length]],
          color,
        );
      }
    }
  }

  void _drawEdge(
    _ScreenVertex a,
    _ScreenVertex b,
    (int, int, int) color,
  ) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final steps = math.max(dx.abs(), dy.abs()).ceil();
    if (steps <= 0) return;
    final stepX = dx / steps;
    final stepY = dy / steps;
    final stepZ = (b.z - a.z) / steps;
    var x = a.x;
    var y = a.y;
    var z = a.z;
    for (var s = 0; s <= steps; s++) {
      final px = x.floor();
      final py = y.floor();
      if (px >= 0 && px < width && py >= 0 && py < height) {
        final index = py * width + px;
        if (z + depthBias >= depth[index]) {
          final offset = index * 3;
          pixels[offset] = color.$1;
          pixels[offset + 1] = color.$2;
          pixels[offset + 2] = color.$3;
        }
      }
      x += stepX;
      y += stepY;
      z += stepZ;
    }
  }

  img.Image toImage() => img.Image.fromBytes(
        width: width,
        height: height,
        bytes: pixels.buffer,
        numChannels: 3,
      );
}

// ───────────────────────── 小工具 ─────────────────────────

(int, int, int) _parseColor(String text, (int, int, int) fallback) {
  var hex = text.trim();
  if (hex.startsWith('#')) hex = hex.substring(1);
  if (hex.length == 3) {
    hex = hex.split('').map((c) => '$c$c').join();
  }
  if (hex.length != 6) return fallback;
  final value = int.tryParse(hex, radix: 16);
  if (value == null) return fallback;
  return ((value >> 16) & 0xff, (value >> 8) & 0xff, value & 0xff);
}

Vec3 _sub(Vec3 a, Vec3 b) => Vec3(a.x - b.x, a.y - b.y, a.z - b.z);

Vec3 _cross(Vec3 a, Vec3 b) => Vec3(
      a.y * b.z - a.z * b.y,
      a.z * b.x - a.x * b.z,
      a.x * b.y - a.y * b.x,
    );

Vec3 _normalize(Vec3 v) {
  final length = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
  if (length == 0 || !length.isFinite) return const Vec3(0, 0, 0);
  return Vec3(v.x / length, v.y / length, v.z / length);
}
