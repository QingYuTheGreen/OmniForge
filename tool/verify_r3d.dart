// OmniForge r3d 自测脚本：验证 MeshRenderEngine 与 MeshGeoEngine。
//
// 运行：/opt/dart/dart-sdk/bin/dart run tool/verify_r3d.dart
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:omniforge/engine/engines/mesh_geo_engine.dart';
import 'package:omniforge/engine/engines/mesh_render_engine.dart';
import 'package:omniforge/engine/i_engine.dart';

/// 手工生成一个中心在原点、边长 2 的立方体（四边形面，由引擎自行三角化）。
const String _cubeObj = '''
# OmniForge r3d verification cube
v -1 -1 -1
v 1 -1 -1
v 1 1 -1
v -1 1 -1
v -1 -1 1
v 1 -1 1
v 1 1 1
v -1 1 1
f 1 4 3 2
f 5 6 7 8
f 1 5 8 4
f 2 3 7 6
f 1 2 6 5
f 4 8 7 3
''';

Future<void> main() async {
  final tempDir = Directory.systemTemp.createTempSync('omniforge_r3d_');
  try {
    await _runChecks(tempDir);
    print('\n全部检查通过 ✓');
  } catch (error, stack) {
    stderr.writeln('验证失败：$error');
    stderr.writeln(stack);
    exitCode = 1;
  } finally {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }
  if (exitCode != 0) {
    exit(exitCode);
  }
}

Future<void> _runChecks(Directory tempDir) async {
  final cubePath = '${tempDir.path}/cube.obj';
  await File(cubePath).writeAsString(_cubeObj);

  // ── 1. PNG（默认参数：800x600，2x 超采样）──
  final pngPath = '${tempDir.path}/cube.png';
  await _runEngine(
    const MeshRenderEngine(),
    EngineContext(
      inputPath: cubePath,
      outputPath: pngPath,
      targetFormat: 'png',
      params: const {'width': 800, 'height': 600},
    ),
  );
  final pngBytes = await File(pngPath).readAsBytes();
  _check(pngBytes.length > 1024, 'PNG 文件过小：${pngBytes.length} 字节');
  final pngImage = img.decodeImage(pngBytes);
  _check(pngImage != null, 'PNG 解码失败');
  final png = pngImage!;
  _check(png.width == 800, 'PNG 宽度应为 800，实际 ${png.width}');
  _check(png.height == 600, 'PNG 高度应为 600，实际 ${png.height}');
  final pngRatio = _nonBackgroundRatio(png, (255, 255, 255));
  _check(pngRatio > 0.05, 'PNG 非背景像素占比过低：$pngRatio');
  print('[render3d] png  ${png.width}x${png.height}  '
      '${pngBytes.length} 字节  非背景占比 ${(pngRatio * 100).toStringAsFixed(2)}%');

  // ── 2. JPG（自定义尺寸 / 旋转 / 颜色）──
  final jpgPath = '${tempDir.path}/cube.jpg';
  await _runEngine(
    const MeshRenderEngine(),
    EngineContext(
      inputPath: cubePath,
      outputPath: jpgPath,
      targetFormat: 'jpg',
      params: const {
        'width': 640,
        'height': 480,
        'rot_x': 25,
        'rot_y': 30,
        'background': '#f2f4f8',
        'color': '#cc6633',
      },
    ),
  );
  final jpgBytes = await File(jpgPath).readAsBytes();
  _check(jpgBytes.length > 1024, 'JPG 文件过小：${jpgBytes.length} 字节');
  final jpgImage = img.decodeImage(jpgBytes);
  _check(jpgImage != null, 'JPG 解码失败');
  final jpg = jpgImage!;
  _check(jpg.width == 640, 'JPG 宽度应为 640，实际 ${jpg.width}');
  _check(jpg.height == 480, 'JPG 高度应为 480，实际 ${jpg.height}');
  final jpgRatio = _nonBackgroundRatio(jpg, (0xf2, 0xf4, 0xf8), tolerance: 18);
  _check(jpgRatio > 0.05, 'JPG 非背景像素占比过低：$jpgRatio');
  print('[render3d] jpg  ${jpg.width}x${jpg.height}  '
      '${jpgBytes.length} 字节  非背景占比 ${(jpgRatio * 100).toStringAsFixed(2)}%');

  // ── 3. 线框模式（确保参数可用、不崩溃）──
  final wirePath = '${tempDir.path}/cube_wire.png';
  await _runEngine(
    const MeshRenderEngine(),
    EngineContext(
      inputPath: cubePath,
      outputPath: wirePath,
      targetFormat: 'png',
      params: const {'width': 320, 'height': 240, 'wireframe': true},
    ),
  );
  final wireImage = img.decodeImage(await File(wirePath).readAsBytes());
  _check(wireImage != null, '线框 PNG 解码失败');
  _check(wireImage!.width == 320 && wireImage.height == 240,
      '线框 PNG 尺寸错误');

  // ── 4. GeoJSON 轮廓 ──
  final geoPath = '${tempDir.path}/cube.geo.json';
  await _runEngine(
    const MeshGeoEngine(),
    EngineContext(
      inputPath: cubePath,
      outputPath: geoPath,
      targetFormat: 'geo_json',
      params: const {'name': 'cube'},
    ),
  );
  final geoText = await File(geoPath).readAsString();
  final decoded = jsonDecode(geoText);
  _check(decoded is Map<String, dynamic>, 'GeoJSON 顶层不是对象');
  final collection = decoded! as Map<String, dynamic>;
  _check(collection['type'] == 'FeatureCollection',
      'GeoJSON type 应为 FeatureCollection');
  final features = collection['features'];
  _check(features is List && features.length == 2,
      'GeoJSON features 应包含 Polygon 与 Point 两个 Feature');
  final featureList = features! as List;

  final polygonFeature = featureList[0] as Map<String, dynamic>;
  final polygonGeometry = polygonFeature['geometry'] as Map<String, dynamic>;
  _check(polygonGeometry['type'] == 'Polygon', '第一个 Feature 应为 Polygon');
  final rings = polygonGeometry['coordinates'] as List;
  final ring = (rings.first as List).cast<List>();
  _check(ring.length >= 4, 'Polygon 外环至少需要 4 个点（≥3 个顶点 + 闭合）');
  final first = ring.first;
  final last = ring.last;
  _check(first[0] == last[0] && first[1] == last[1], 'Polygon 外环未闭合');
  final uniqueCount =
      ring.take(ring.length - 1).map((p) => '${p[0]},${p[1]}').toSet().length;
  _check(uniqueCount >= 3, 'Polygon 顶点去重后不足 3 个');
  var signedArea = 0.0;
  for (var i = 0; i < ring.length - 1; i++) {
    final a = ring[i];
    final b = ring[i + 1];
    signedArea += (a[0] as num) * (b[1] as num) - (b[0] as num) * (a[1] as num);
  }
  signedArea /= 2;
  _check(signedArea > 0, 'Polygon 外环应为逆时针（面积为正），实际面积 $signedArea');

  final pointFeature = featureList[1] as Map<String, dynamic>;
  final pointGeometry = pointFeature['geometry'] as Map<String, dynamic>;
  _check(pointGeometry['type'] == 'Point', '第二个 Feature 应为 Point');
  final point = pointGeometry['coordinates'] as List;
  _check(point.length == 2, 'Point 坐标应为 [x, y]');
  _check((point[0] as num).isFinite && (point[1] as num).isFinite,
      'Point 坐标不是有限数');

  print('[mesh_geo]  geo_json  ${geoText.length} 字符  '
      '外环 ${ring.length} 点（去重 $uniqueCount） '
      '面积 ${signedArea.toStringAsFixed(6)}  '
      '质心 (${point[0]}, ${point[1]})');
}

Future<void> _runEngine(IEngine engine, EngineContext context) async {
  var succeeded = false;
  await for (final event in engine.convert(context)) {
    if (event is Success) succeeded = true;
    if (event is Error) {
      throw StateError('引擎 ${engine.id} 转换失败：${event.message}');
    }
  }
  _check(succeeded, '引擎 ${engine.id} 未返回成功状态');
}

double _nonBackgroundRatio(
  img.Image image,
  (int, int, int) background, {
  int tolerance = 8,
}) {
  var count = 0;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final pixel = image.getPixel(x, y);
      if ((pixel.r - background.$1).abs() > tolerance ||
          (pixel.g - background.$2).abs() > tolerance ||
          (pixel.b - background.$3).abs() > tolerance) {
        count++;
      }
    }
  }
  return count / (image.width * image.height);
}

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}
