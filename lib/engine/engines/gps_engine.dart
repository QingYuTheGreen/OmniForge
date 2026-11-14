import 'dart:convert';

import 'package:xml/xml.dart';

import '../engine_utils.dart';
import '../i_engine.dart';

/// 一个轨迹点。
class TrackPoint {
  final double latitude;
  final double longitude;
  final double? elevation;
  final DateTime? time;

  const TrackPoint({
    required this.latitude,
    required this.longitude,
    this.elevation,
    this.time,
  });
}

/// GPS 轨迹引擎：gpx / kml / tcx / geojson 互转（纯 Dart XML/JSON）。
class GpsEngine extends SimpleEngine {
  const GpsEngine();

  @override
  String get id => 'gps';

  @override
  Future<void> execute(EngineContext context) async {
    final content = await readFileText(context.inputPath);
    final source = _detectSource(context, content);
    final points = _parse(source, content);
    if (points.isEmpty) {
      throw const EngineException('没有从输入文件里解析到轨迹点');
    }
    final name = stringParam(context, 'name', inputStem(context));
    final target = context.targetFormat.toLowerCase();
    final text = switch (target) {
      'gpx' => _writeGpx(points, name),
      'kml' => _writeKml(points, name),
      'tcx' => _writeTcx(points, name),
      'geojson' => _writeGeoJson(points, name),
      _ => throw EngineException('GPS 引擎不支持输出格式：$target'),
    };
    await writeFileText(context.outputPath, text);
  }

  String _detectSource(EngineContext context, String content) {
    final ext = inputExtension(context);
    if (ext == 'gpx') return 'gpx';
    if (ext == 'kml') return 'kml';
    if (ext == 'tcx') return 'tcx';
    if (ext == 'geojson' || content.trimLeft().startsWith('{')) return 'geojson';
    final head = content.trimLeft();
    if (head.startsWith('<gpx') || head.contains('<gpx')) return 'gpx';
    if (head.contains('<kml')) return 'kml';
    if (head.contains('<TrainingCenterDatabase')) return 'tcx';
    return 'geojson';
  }

  List<TrackPoint> _parse(String source, String content) {
    return switch (source) {
      'gpx' => _parseGpx(content),
      'kml' => _parseKml(content),
      'tcx' => _parseTcx(content),
      _ => _parseGeoJson(content),
    };
  }

  List<TrackPoint> _parseGpx(String content) {
    final points = <TrackPoint>[];
    final document = XmlDocument.parse(content);
    for (final node in document.descendantElements) {
      if (node.localName != 'trkpt' && node.localName != 'wpt') continue;
      final lat = double.tryParse(node.getAttribute('lat') ?? '');
      final lon = double.tryParse(node.getAttribute('lon') ?? '');
      if (lat == null || lon == null) continue;
      double? ele;
      DateTime? time;
      for (final child in node.childElements) {
        if (child.localName == 'ele') {
          ele = double.tryParse(child.innerText.trim());
        } else if (child.localName == 'time') {
          time = DateTime.tryParse(child.innerText.trim());
        }
      }
      points.add(TrackPoint(
        latitude: lat,
        longitude: lon,
        elevation: ele,
        time: time,
      ));
    }
    return points;
  }

  List<TrackPoint> _parseKml(String content) {
    final points = <TrackPoint>[];
    final document = XmlDocument.parse(content);
    for (final node in document.descendantElements) {
      if (node.localName != 'coordinates') continue;
      for (final tuple in node.innerText.trim().split(RegExp(r'\s+'))) {
        final parts = tuple.split(',');
        if (parts.length < 2) continue;
        final lon = double.tryParse(parts[0].trim());
        final lat = double.tryParse(parts[1].trim());
        if (lat == null || lon == null) continue;
        final ele = parts.length > 2 ? double.tryParse(parts[2].trim()) : null;
        points.add(TrackPoint(latitude: lat, longitude: lon, elevation: ele));
      }
    }
    return points;
  }

  List<TrackPoint> _parseTcx(String content) {
    final points = <TrackPoint>[];
    final document = XmlDocument.parse(content);
    for (final node in document.descendantElements) {
      if (node.localName != 'Trackpoint') continue;
      double? lat;
      double? lon;
      double? ele;
      DateTime? time;
      for (final child in node.descendantElements) {
        switch (child.localName) {
          case 'LatitudeDegrees':
            lat = double.tryParse(child.innerText.trim());
          case 'LongitudeDegrees':
            lon = double.tryParse(child.innerText.trim());
          case 'AltitudeMeters':
            ele = double.tryParse(child.innerText.trim());
          case 'Time':
            time = DateTime.tryParse(child.innerText.trim());
        }
      }
      if (lat == null || lon == null) continue;
      points.add(TrackPoint(
        latitude: lat,
        longitude: lon,
        elevation: ele,
        time: time,
      ));
    }
    return points;
  }

  List<TrackPoint> _parseGeoJson(String content) {
    final points = <TrackPoint>[];
    final decoded = jsonDecode(content);
    void visit(Object? node) {
      if (node is Map) {
        if (node['type'] == 'FeatureCollection' && node['features'] is List) {
          for (final feature in node['features'] as List) {
            visit(feature);
          }
          return;
        }
        if (node['type'] == 'Feature' && node['geometry'] != null) {
          visit(node['geometry']);
          return;
        }
        if (node['type'] == 'GeometryCollection' && node['geometries'] is List) {
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

    visit(decoded);
    return points;
  }

  void _collectCoordinates(List<dynamic> node, List<TrackPoint> points) {
    if (node.isEmpty) return;
    if (node.first is num && node.length >= 2) {
      final lon = (node[0] as num).toDouble();
      final lat = (node[1] as num).toDouble();
      final ele = node.length > 2 && node[2] is num
          ? (node[2] as num).toDouble()
          : null;
      points.add(TrackPoint(latitude: lat, longitude: lon, elevation: ele));
      return;
    }
    for (final child in node) {
      if (child is List) _collectCoordinates(child, points);
    }
  }

  // ─────────────────────────── 输出 ───────────────────────────

  String _writeGpx(List<TrackPoint> points, String name) {
    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<gpx version="1.1" creator="OmniForge" '
          'xmlns="http://www.topografix.com/GPX/1/1">')
      ..writeln('  <trk>')
      ..writeln('    <name>${_escape(name)}</name>')
      ..writeln('    <trkseg>');
    for (final point in points) {
      buffer.write('      <trkpt lat="${point.latitude}" '
          'lon="${point.longitude}">');
      if (point.elevation != null) {
        buffer.write('<ele>${point.elevation}</ele>');
      }
      if (point.time != null) {
        buffer.write('<time>${point.time!.toUtc().toIso8601String()}</time>');
      }
      buffer.writeln('</trkpt>');
    }
    buffer
      ..writeln('    </trkseg>')
      ..writeln('  </trk>')
      ..writeln('</gpx>');
    return buffer.toString();
  }

  String _writeKml(List<TrackPoint> points, String name) {
    final coordinates = points
        .map((p) => '${p.longitude},${p.latitude}'
            '${p.elevation != null ? ',${p.elevation}' : ',0'}')
        .join(' ');
    return '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <name>${_escape(name)}</name>
    <Placemark>
      <name>${_escape(name)}</name>
      <LineString>
        <tessellate>1</tessellate>
        <coordinates>$coordinates</coordinates>
      </LineString>
    </Placemark>
  </Document>
</kml>
''';
  }

  String _writeTcx(List<TrackPoint> points, String name) {
    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<TrainingCenterDatabase '
          'xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">')
      ..writeln('  <Activities><Activity Sport="Other">')
      ..writeln('    <Id>${_escape(name)}</Id>')
      ..writeln('    <Lap StartTime="${points.first.time?.toUtc().toIso8601String() ?? DateTime.now().toUtc().toIso8601String()}">')
      ..writeln('      <Track>');
    for (final point in points) {
      buffer.writeln('        <Trackpoint>');
      if (point.time != null) {
        buffer.writeln(
            '          <Time>${point.time!.toUtc().toIso8601String()}</Time>');
      }
      buffer
        ..writeln('          <Position>')
        ..writeln('            <LatitudeDegrees>${point.latitude}'
            '</LatitudeDegrees>')
        ..writeln('            <LongitudeDegrees>${point.longitude}'
            '</LongitudeDegrees>')
        ..writeln('          </Position>');
      if (point.elevation != null) {
        buffer.writeln('          <AltitudeMeters>${point.elevation}'
            '</AltitudeMeters>');
      }
      buffer.writeln('        </Trackpoint>');
    }
    buffer
      ..writeln('      </Track>')
      ..writeln('    </Lap>')
      ..writeln('  </Activity></Activities>')
      ..writeln('</TrainingCenterDatabase>');
    return buffer.toString();
  }

  String _writeGeoJson(List<TrackPoint> points, String name) {
    final coordinates = points
        .map((p) => <num>[
              p.longitude,
              p.latitude,
              if (p.elevation != null) p.elevation!,
            ])
        .toList();
    final data = <String, dynamic>{
      'type': 'FeatureCollection',
      'name': name,
      'features': [
        {
          'type': 'Feature',
          'properties': <String, dynamic>{'name': name},
          'geometry': {
            'type': 'LineString',
            'coordinates': coordinates,
          },
        },
      ],
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
