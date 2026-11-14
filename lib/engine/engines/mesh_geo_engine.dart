import 'dart:convert';
import 'dart:math' as math;

import '../engine_utils.dart';
import '../i_engine.dart';
import 'mesh_engine.dart';

/// 3D 网格 → GeoJSON 引擎：把模型投影到 XY 平面的「占地轮廓/俯视投影」
/// 以凸包 Polygon + 质心 Point 的形式输出（坐标为模型局部坐标，非地理坐标）。
class MeshGeoEngine extends SimpleEngine {
  const MeshGeoEngine();

  @override
  String get id => 'mesh_geo';

  @override
  Future<void> execute(EngineContext context) async {
    final target = context.targetFormat.toLowerCase();
    if (target != 'geo_json') {
      throw const EngineException('mesh_geo 仅支持 geo_json 输出');
    }

    final mesh = readMesh(context.inputPath);
    if (mesh.vertices.isEmpty) {
      throw const EngineException('网格文件为空或没有顶点');
    }

    // 绕 Y 轴旋转后投影到 XY 平面（rot_y 为 0 时即忽略 Z 的俯视投影）。
    final ry = doubleParam(context, 'rot_y', 0) * math.pi / 180;
    final cosY = math.cos(ry), sinY = math.sin(ry);
    final points = <(double, double)>[];
    for (final v in mesh.vertices) {
      if (!v.isFinite) continue;
      final x = v.x * cosY + v.z * sinY;
      points.add((x, v.y));
    }
    if (points.length < 3) {
      throw const EngineException('模型顶点过少，无法生成轮廓');
    }

    final hull = _convexHull(points);
    if (hull.length < 3) {
      throw const EngineException('模型投影过于退化，无法生成轮廓多边形');
    }

    final ring = <List<double>>[
      for (final point in hull) [_round6(point.$1), _round6(point.$2)],
    ];
    // 外环闭合
    ring.add(List<double>.of(ring.first));

    final centroid = _polygonCentroid(hull);
    final name = stringParam(context, 'name', inputStem(context));
    const description = '占地轮廓 / 俯视投影（模型局部坐标，非地理坐标）';

    final document = <String, dynamic>{
      'type': 'FeatureCollection',
      'properties': {
        'name': name,
        'source': 'mesh',
        'description': description,
        'distortion': '忽略 Z 或按 rot_y 旋转后投影到 XY 平面',
      },
      'features': <Map<String, dynamic>>[
        {
          'type': 'Feature',
          'properties': {
            'name': name,
            'source': 'mesh',
            'kind': 'footprint',
            'description': description,
          },
          'geometry': {
            'type': 'Polygon',
            'coordinates': [ring],
          },
        },
        {
          'type': 'Feature',
          'properties': {
            'name': '$name centroid',
            'source': 'mesh',
            'kind': 'centroid',
            'description': description,
          },
          'geometry': {
            'type': 'Point',
            'coordinates': [_round6(centroid.$1), _round6(centroid.$2)],
          },
        },
      ],
    };

    final text = const JsonEncoder.withIndent('  ').convert(document);
    await writeFileText(context.outputPath, text);
  }

  /// Andrew 单调链凸包，返回逆时针（CCW）顶点序列，自动去重共线点。
  List<(double, double)> _convexHull(List<(double, double)> input) {
    final points = List<(double, double)>.of(input);
    points.sort((a, b) {
      final byX = a.$1.compareTo(b.$1);
      return byX != 0 ? byX : a.$2.compareTo(b.$2);
    });

    double cross(
      (double, double) o,
      (double, double) a,
      (double, double) b,
    ) =>
        (a.$1 - o.$1) * (b.$2 - o.$2) - (a.$2 - o.$2) * (b.$1 - o.$1);

    final lower = <(double, double)>[];
    for (final point in points) {
      while (lower.length >= 2 &&
          cross(lower[lower.length - 2], lower.last, point) <= 0) {
        lower.removeLast();
      }
      lower.add(point);
    }
    final upper = <(double, double)>[];
    for (final point in points.reversed) {
      while (upper.length >= 2 &&
          cross(upper[upper.length - 2], upper.last, point) <= 0) {
        upper.removeLast();
      }
      upper.add(point);
    }
    lower.removeLast();
    upper.removeLast();
    return <(double, double)>[...lower, ...upper];
  }

  /// 多边形面积质心；面积为 0 时退回顶点平均值。
  (double, double) _polygonCentroid(List<(double, double)> hull) {
    var area = 0.0;
    var cx = 0.0;
    var cy = 0.0;
    for (var i = 0; i < hull.length; i++) {
      final p = hull[i];
      final q = hull[(i + 1) % hull.length];
      final factor = p.$1 * q.$2 - q.$1 * p.$2;
      area += factor;
      cx += (p.$1 + q.$1) * factor;
      cy += (p.$2 + q.$2) * factor;
    }
    area /= 2;
    if (area.abs() < 1e-12) {
      var sx = 0.0;
      var sy = 0.0;
      for (final point in hull) {
        sx += point.$1;
        sy += point.$2;
      }
      return (sx / hull.length, sy / hull.length);
    }
    return (cx / (6 * area), cy / (6 * area));
  }
}

double _round6(double value) {
  if (!value.isFinite) return 0;
  final rounded = (value * 1000000).round() / 1000000;
  return rounded == 0 ? 0 : rounded;
}
