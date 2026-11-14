/// 地理轨迹渲染引擎：把 gpx / kml / tcx / geojson 轨迹画成 SVG 或 PNG 图片。
///
/// 解析：自带最小解析器（gpx trkpt/wpt、kml coordinates、tcx Trackpoint、
/// geojson LineString/MultiLineString/Point），复用 [TrackPoint] 模型。
/// 投影：等距圆柱近似 x = lon, y = -lat，按 bbox 等比缩放到画布。
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:image/image.dart' as img;
import 'package:xml/xml.dart';

import '../engine_utils.dart';
import '../i_engine.dart';
import 'gps_engine.dart' show TrackPoint;

/// 轨迹渲染引擎。
class GeoRenderEngine extends SimpleEngine {
  const GeoRenderEngine();

  @override
  String get id => 'geo_render';

  /// 支持的输入格式。
  static const Set<String> inputs = {'gpx', 'kml', 'tcx', 'geojson'};

  /// 支持的输出格式。
  static const Set<String> outputs = {'svg', 'png'};

  @override
  void validate(EngineContext context) {
    final source = detectSource(context, null);
    if (!inputs.contains(source)) {
      throw EngineException('地理轨迹渲染不支持输入格式：$source');
    }
    final target = context.targetFormat.toLowerCase();
    if (!outputs.contains(target)) {
      throw EngineException('地理轨迹渲染不支持输出格式：$target');
    }
  }

  @override
  Future<void> execute(EngineContext context) async {
    final content = await readFileText(context.inputPath);
    final source = detectSource(context, content);
    final points = parseTrack(content, source);
    if (points.isEmpty) {
      throw const EngineException('没有从输入文件里解析到轨迹点');
    }

    final width = intParam(context, 'width', 1200).clamp(16, 10000);
    final height = intParam(context, 'height', 800).clamp(16, 10000);
    final padding = intParam(context, 'padding', 60).clamp(0, 1000);
    final color = _parseHexColor(stringParam(context, 'color', '#2e7d32'));
    final background =
        _parseHexColor(stringParam(context, 'background', '#ffffff'));
    final stroke = doubleParam(context, 'stroke', 3).clamp(0.5, 200.0);
    final dots = boolParam(context, 'dots', true);

    final projection = _Projection.fromPoints(
      points,
      width: width,
      height: height,
      padding: padding,
    );

    final target = context.targetFormat.toLowerCase();
    switch (target) {
      case 'svg':
        final svg = _renderSvg(
          projection: projection,
          points: points,
          width: width,
          height: height,
          color: color,
          background: background,
          stroke: stroke,
          dots: dots,
        );
        await writeFileText(context.outputPath, svg);
      case 'png':
        final bytes = _renderPng(
          projection: projection,
          points: points,
          width: width,
          height: height,
          color: color,
          background: background,
          stroke: stroke,
          dots: dots,
        );
        await writeFileBytes(context.outputPath, bytes);
      default:
        throw EngineException('地理轨迹渲染不支持输出格式：$target');
    }
  }

  /// 判断输入格式：优先扩展名，其次内容特征。
  static String detectSource(EngineContext context, String? content) {
    final declared = context.sourceFormat.toLowerCase();
    if (inputs.contains(declared)) return declared;
    final ext = inputExtension(context);
    if (inputs.contains(ext)) return ext;
    if (content != null) {
      final head = content.trimLeft();
      if (head.startsWith('{') || head.startsWith('[')) return 'geojson';
      if (head.contains('<gpx')) return 'gpx';
      if (head.contains('<kml')) return 'kml';
      if (head.contains('<TrainingCenterDatabase')) return 'tcx';
    }
    return ext.isEmpty ? 'gpx' : ext;
  }

  /// 解析轨迹点（公开静态方法，便于自检脚本直接复用）。
  static List<TrackPoint> parseTrack(String content, String source) {
    try {
      return switch (source) {
        'gpx' => _parseGpx(content),
        'kml' => _parseKml(content),
        'tcx' => _parseTcx(content),
        'geojson' => _parseGeoJson(content),
        _ => throw EngineException('不支持的地理轨迹格式：$source'),
      };
    } on XmlException catch (error) {
      throw EngineException('XML 解析失败：${error.message}');
    } on FormatException catch (error) {
      throw EngineException('轨迹文件解析失败：${error.message}');
    }
  }

  // ─────────────────────────── 解析 ───────────────────────────

  static List<TrackPoint> _parseGpx(String content) {
    final points = <TrackPoint>[];
    final document = XmlDocument.parse(content);
    for (final node in document.descendantElements) {
      if (node.localName != 'trkpt' && node.localName != 'wpt') continue;
      final lat = double.tryParse(node.getAttribute('lat') ?? '');
      final lon = double.tryParse(node.getAttribute('lon') ?? '');
      if (lat == null || lon == null) continue;
      double? elevation;
      DateTime? time;
      for (final child in node.childElements) {
        switch (child.localName) {
          case 'ele':
            elevation = double.tryParse(child.innerText.trim());
          case 'time':
            time = DateTime.tryParse(child.innerText.trim());
        }
      }
      points.add(TrackPoint(
        latitude: lat,
        longitude: lon,
        elevation: elevation,
        time: time,
      ));
    }
    return points;
  }

  static List<TrackPoint> _parseKml(String content) {
    final points = <TrackPoint>[];
    final document = XmlDocument.parse(content);
    for (final node in document.descendantElements) {
      if (node.localName != 'coordinates') continue;
      for (final tuple in node.innerText.trim().split(RegExp(r'\s+'))) {
        if (tuple.isEmpty) continue;
        final parts = tuple.split(',');
        if (parts.length < 2) continue;
        final lon = double.tryParse(parts[0].trim());
        final lat = double.tryParse(parts[1].trim());
        if (lat == null || lon == null) continue;
        points.add(TrackPoint(
          latitude: lat,
          longitude: lon,
          elevation: parts.length > 2 ? double.tryParse(parts[2].trim()) : null,
        ));
      }
    }
    return points;
  }

  static List<TrackPoint> _parseTcx(String content) {
    final points = <TrackPoint>[];
    final document = XmlDocument.parse(content);
    for (final node in document.descendantElements) {
      if (node.localName != 'Trackpoint') continue;
      double? lat;
      double? lon;
      double? elevation;
      DateTime? time;
      for (final child in node.descendantElements) {
        switch (child.localName) {
          case 'LatitudeDegrees':
            lat = double.tryParse(child.innerText.trim());
          case 'LongitudeDegrees':
            lon = double.tryParse(child.innerText.trim());
          case 'AltitudeMeters':
            elevation = double.tryParse(child.innerText.trim());
          case 'Time':
            time = DateTime.tryParse(child.innerText.trim());
        }
      }
      if (lat == null || lon == null) continue;
      points.add(TrackPoint(
        latitude: lat,
        longitude: lon,
        elevation: elevation,
        time: time,
      ));
    }
    return points;
  }

  static List<TrackPoint> _parseGeoJson(String content) {
    final points = <TrackPoint>[];
    void visit(Object? node) {
      if (node is Map) {
        final type = node['type'];
        if (type == 'FeatureCollection' && node['features'] is List) {
          for (final feature in node['features'] as List) {
            visit(feature);
          }
          return;
        }
        if (type == 'Feature' && node['geometry'] != null) {
          visit(node['geometry']);
          return;
        }
        if (type == 'GeometryCollection' && node['geometries'] is List) {
          for (final geometry in node['geometries'] as List) {
            visit(geometry);
          }
          return;
        }
        final coordinates = node['coordinates'];
        if (coordinates is List) {
          _collectCoordinates(coordinates, points);
        }
      } else if (node is List) {
        for (final child in node) {
          visit(child);
        }
      }
    }

    visit(jsonDecode(content));
    return points;
  }

  static void _collectCoordinates(List<dynamic> node, List<TrackPoint> points) {
    if (node.isEmpty) return;
    if (node.first is num && node.length >= 2) {
      final lon = (node[0] as num).toDouble();
      final lat = (node[1] as num).toDouble();
      final elevation =
          node.length > 2 && node[2] is num ? (node[2] as num).toDouble() : null;
      points.add(
          TrackPoint(latitude: lat, longitude: lon, elevation: elevation));
      return;
    }
    for (final child in node) {
      if (child is List) _collectCoordinates(child, points);
    }
  }

  // ─────────────────────────── 投影 ───────────────────────────

  static _CanvasPoint _project(
    _Projection projection,
    TrackPoint point,
  ) =>
      _CanvasPoint(
        projection.offsetX + (point.longitude - projection.minLon) *
            projection.scale,
        projection.offsetY + (projection.maxLat - point.latitude) *
            projection.scale,
      );

  static String _renderSvg({
    required _Projection projection,
    required List<TrackPoint> points,
    required int width,
    required int height,
    required int color,
    required int background,
    required double stroke,
    required bool dots,
  }) {
    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<svg xmlns="http://www.w3.org/2000/svg" '
          'width="$width" height="$height" viewBox="0 0 $width $height">')
      ..writeln('  <rect x="0" y="0" width="$width" height="$height" '
          'fill="${_hexString(background)}"/>');

    final path = StringBuffer();
    for (var i = 0; i < points.length; i++) {
      final projected = _project(projection, points[i]);
      path
        ..write(i == 0 ? 'M' : ' L')
        ..write('${_fmt(projected.x)},${_fmt(projected.y)}');
    }
    buffer.writeln('  <path d="${path.toString()}" fill="none" '
        'stroke="${_hexString(color)}" stroke-width="${_fmt(stroke)}" '
        'stroke-linecap="round" stroke-linejoin="round"/>');

    if (dots) {
      final start = _project(projection, points.first);
      final end = _project(projection, points.last);
      final radius = math.max(3.0, stroke * 1.8);
      buffer
        ..writeln('  <circle cx="${_fmt(start.x)}" cy="${_fmt(start.y)}" '
            'r="${_fmt(radius)}" fill="${_hexString(color)}"/>')
        ..writeln('  <circle cx="${_fmt(end.x)}" cy="${_fmt(end.y)}" '
            'r="${_fmt(radius)}" fill="#e53935"/>');
    }
    buffer.writeln('</svg>');
    return buffer.toString();
  }

  static List<int> _renderPng({
    required _Projection projection,
    required List<TrackPoint> points,
    required int width,
    required int height,
    required int color,
    required int background,
    required double stroke,
    required bool dots,
  }) {
    final image = img.Image(width: width, height: height, numChannels: 3);
    final bg = img.ColorRgb8(
      (background >> 16) & 0xFF,
      (background >> 8) & 0xFF,
      background & 0xFF,
    );
    img.fill(image, color: bg);

    final lineColor = img.ColorRgb8(
      (color >> 16) & 0xFF,
      (color >> 8) & 0xFF,
      color & 0xFF,
    );
    final thickness = math.max(1, stroke.round());

    _CanvasPoint? previous;
    for (final point in points) {
      final current = _project(projection, point);
      if (previous != null) {
        img.drawLine(
          image,
          x1: previous.x.round(),
          y1: previous.y.round(),
          x2: current.x.round(),
          y2: current.y.round(),
          color: lineColor,
          thickness: thickness,
          antialias: true,
        );
      }
      previous = current;
    }

    if (dots) {
      final radius = math.max(3, (stroke * 1.8).round());
      final start = _project(projection, points.first);
      final end = _project(projection, points.last);
      img.fillCircle(
        image,
        x: start.x.round(),
        y: start.y.round(),
        radius: radius,
        color: lineColor,
        antialias: true,
      );
      img.fillCircle(
        image,
        x: end.x.round(),
        y: end.y.round(),
        radius: radius,
        color: img.ColorRgb8(0xE5, 0x39, 0x35),
        antialias: true,
      );
    }

    return img.encodePng(image, level: 6);
  }

  static int _parseHexColor(String text) {
    var value = text.trim();
    if (value.startsWith('#')) value = value.substring(1);
    if (value.length == 3) {
      value = value.split('').map((c) => '$c$c').join();
    }
    if (value.length == 8) value = value.substring(2); // 忽略 alpha
    final parsed = int.tryParse(value, radix: 16);
    return parsed ?? 0x2E7D32;
  }

  static String _hexString(int color) {
    final rgb = (color & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
    return '#$rgb';
  }

  static String _fmt(double value) {
    if (value.abs() < 0.005) return '0';
    return value.toStringAsFixed(2);
  }
}

class _CanvasPoint {
  const _CanvasPoint(this.x, this.y);

  final double x;
  final double y;
}

/// 等距圆柱投影：经度 → x，纬度（取负）→ y，等比缩放并居中。
class _Projection {
  const _Projection({
    required this.minLon,
    required this.maxLat,
    required this.scale,
    required this.offsetX,
    required this.offsetY,
  });

  final double minLon;
  final double maxLat;
  final double scale;
  final double offsetX;
  final double offsetY;

  factory _Projection.fromPoints(
    List<TrackPoint> points, {
    required int width,
    required int height,
    required int padding,
  }) {
    var minLon = double.infinity;
    var maxLon = double.negativeInfinity;
    var minLat = double.infinity;
    var maxLat = double.negativeInfinity;
    for (final point in points) {
      minLon = math.min(minLon, point.longitude);
      maxLon = math.max(maxLon, point.longitude);
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
    }

    final availableWidth = math.max(1.0, width - padding * 2.0);
    final availableHeight = math.max(1.0, height - padding * 2.0);
    final spanX = maxLon - minLon;
    final spanY = maxLat - minLat;

    double scale;
    if (spanX <= 1e-12 && spanY <= 1e-12) {
      scale = math.min(availableWidth, availableHeight) / 2.0;
    } else if (spanX <= 1e-12) {
      scale = availableHeight / spanY;
    } else if (spanY <= 1e-12) {
      scale = availableWidth / spanX;
    } else {
      scale = math.min(availableWidth / spanX, availableHeight / spanY);
    }
    if (!scale.isFinite || scale <= 0) scale = 1;

    final drawnWidth = spanX * scale;
    final drawnHeight = spanY * scale;
    return _Projection(
      minLon: minLon,
      maxLat: maxLat,
      scale: scale,
      offsetX: (width - drawnWidth) / 2.0,
      offsetY: (height - drawnHeight) / 2.0,
    );
  }
}
