import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../engine_utils.dart';

/// 三维网格数据：顶点 + 三角面（索引）。
class MeshData {
  MeshData({required this.vertices, required this.faces, this.name = 'mesh'});

  final List<Vec3> vertices;
  final List<List<int>> faces;
  final String name;

  /// 去掉未被面引用的顶点，并统一为逆时针三角面。
  MeshData normalized() {
    final remap = <int, int>{};
    final newVertices = <Vec3>[];
    final newFaces = <List<int>>[];
    for (final face in faces) {
      final mapped = <int>[];
      for (final index in face) {
        if (index < 0 || index >= vertices.length) continue;
        final target = remap.putIfAbsent(index, () {
          newVertices.add(vertices[index]);
          return newVertices.length - 1;
        });
        mapped.add(target);
      }
      for (var i = 2; i < mapped.length; i++) {
        newFaces.add([mapped[0], mapped[i - 1], mapped[i]]);
      }
    }
    return MeshData(vertices: newVertices, faces: newFaces, name: name);
  }

  int get triangleCount => faces.length;
}

class Vec3 {
  const Vec3(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  bool get isFinite => x.isFinite && y.isFinite && z.isFinite;

  @override
  String toString() => '($x, $y, $z)';
}

// ─────────────────────────── OBJ ───────────────────────────

MeshData parseObj(String text, {String name = 'mesh'}) {
  final vertices = <Vec3>[];
  final faces = <List<int>>[];
  for (final rawLine in const LineSplitter().convert(text)) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final parts = line.split(RegExp(r'\s+'));
    switch (parts.first) {
      case 'v':
        if (parts.length >= 4) {
          vertices.add(
            Vec3(
              double.tryParse(parts[1]) ?? 0,
              double.tryParse(parts[2]) ?? 0,
              double.tryParse(parts[3]) ?? 0,
            ),
          );
        }
      case 'f':
        final face = <int>[];
        for (final token in parts.skip(1)) {
          final raw = token.split('/').first;
          var index = int.tryParse(raw);
          if (index == null) continue;
          if (index < 0) index = vertices.length + index;
          else index -= 1;
          if (index >= 0 && index < vertices.length) face.add(index);
        }
        if (face.length >= 3) faces.add(face);
    }
  }
  return MeshData(vertices: vertices, faces: faces, name: name);
}

String writeObj(MeshData mesh) {
  final buffer = StringBuffer('# OmniForge\n');
  for (final v in mesh.vertices) {
    buffer.writeln('v ${_fmt(v.x)} ${_fmt(v.y)} ${_fmt(v.z)}');
  }
  for (final face in mesh.faces) {
    buffer.writeln('f ${face.map((i) => i + 1).join(' ')}');
  }
  return buffer.toString();
}

// ─────────────────────────── PLY ───────────────────────────

MeshData parsePly(Uint8List bytes, {String name = 'mesh'}) {
  // 头部是 ASCII，找到 end_header\n
  var headerEnd = -1;
  for (var i = 0; i + 10 <= bytes.length; i++) {
    if (bytes[i] == 0x65 &&
        String.fromCharCodes(bytes.sublist(i, i + 10)) == 'end_header') {
      headerEnd = i + 10;
      while (headerEnd < bytes.length &&
          (bytes[headerEnd] == 0x0A || bytes[headerEnd] == 0x0D)) {
        headerEnd++;
      }
      break;
    }
  }
  if (headerEnd < 0) {
    throw const EngineException('PLY 头部缺失');
  }
  final header = String.fromCharCodes(bytes.sublist(0, headerEnd));
  final vertexCount = _plyCount(header, 'vertex');
  final faceCount = _plyCount(header, 'face');
  final binary = header.contains('format binary_little_endian');
  final vertices = <Vec3>[];
  final faces = <List<int>>[];

  if (binary) {
    final data = ByteData.sublistView(bytes);
    var offset = headerEnd;
    for (var i = 0; i < vertexCount; i++) {
      if (offset + 12 > bytes.length) break;
      vertices.add(
        Vec3(
          data.getFloat32(offset, Endian.little),
          data.getFloat32(offset + 4, Endian.little),
          data.getFloat32(offset + 8, Endian.little),
        ),
      );
      offset += 12;
    }
    for (var i = 0; i < faceCount; i++) {
      if (offset >= bytes.length) break;
      final count = bytes[offset];
      offset += 1;
      final face = <int>[];
      for (var j = 0; j < count; j++) {
        if (offset + 4 > bytes.length) break;
        face.add(data.getInt32(offset, Endian.little));
        offset += 4;
      }
      if (face.length >= 3) faces.add(face);
    }
  } else {
    final lines = const LineSplitter()
        .convert(String.fromCharCodes(bytes.sublist(headerEnd)));
    var index = 0;
    for (var i = 0; i < vertexCount && index < lines.length; i++, index++) {
      final parts = lines[index].trim().split(RegExp(r'\s+'));
      if (parts.length < 3) {
        i--;
        continue;
      }
      vertices.add(
        Vec3(
          double.tryParse(parts[0]) ?? 0,
          double.tryParse(parts[1]) ?? 0,
          double.tryParse(parts[2]) ?? 0,
        ),
      );
    }
    for (var i = 0; i < faceCount && index < lines.length; i++, index++) {
      final parts = lines[index].trim().split(RegExp(r'\s+'));
      final count = int.tryParse(parts.first) ?? 0;
      final face = <int>[];
      for (var j = 1; j <= count && j < parts.length; j++) {
        final v = int.tryParse(parts[j]);
        if (v != null) face.add(v);
      }
      if (face.length >= 3) faces.add(face);
    }
  }
  return MeshData(vertices: vertices, faces: faces, name: name);
}

int _plyCount(String header, String element) {
  final match = RegExp('element $element (\\d+)').firstMatch(header);
  return match == null ? 0 : int.tryParse(match.group(1)!) ?? 0;
}

String writePly(MeshData mesh) {
  final buffer = StringBuffer()
    ..writeln('ply')
    ..writeln('format ascii 1.0')
    ..writeln('comment Generated by OmniForge')
    ..writeln('element vertex ${mesh.vertices.length}')
    ..writeln('property float x')
    ..writeln('property float y')
    ..writeln('property float z')
    ..writeln('element face ${mesh.faces.length}')
    ..writeln('property list uchar int vertex_indices')
    ..writeln('end_header');
  for (final v in mesh.vertices) {
    buffer.writeln('${_fmt(v.x)} ${_fmt(v.y)} ${_fmt(v.z)}');
  }
  for (final face in mesh.faces) {
    buffer.writeln('${face.length} ${face.join(' ')}');
  }
  return buffer.toString();
}

// ─────────────────────────── OFF ───────────────────────────

MeshData parseOff(String text, {String name = 'mesh'}) {
  final lines = const LineSplitter()
      .convert(text)
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !l.startsWith('#'))
      .toList();
  if (lines.isEmpty) throw const EngineException('OFF 文件为空');
  var cursor = 0;
  var header = lines[cursor++];
  if (header.startsWith('OFF')) {
    header = header.substring(3);
  } else if (header.startsWith('COFF') || header.startsWith('NOFF')) {
    throw const EngineException('暂不支持带颜色的 OFF 文件');
  }
  final counts = header.trim().isEmpty
      ? lines[cursor++].split(RegExp(r'\s+'))
      : header.split(RegExp(r'\s+'));
  final vertexCount = int.tryParse(counts[0]) ?? 0;
  final faceCount = int.tryParse(counts[1]) ?? 0;
  final vertices = <Vec3>[];
  for (var i = 0; i < vertexCount && cursor < lines.length; i++, cursor++) {
    final parts = lines[cursor].split(RegExp(r'\s+'));
    if (parts.length < 3) break;
    vertices.add(
      Vec3(
        double.tryParse(parts[0]) ?? 0,
        double.tryParse(parts[1]) ?? 0,
        double.tryParse(parts[2]) ?? 0,
      ),
    );
  }
  final faces = <List<int>>[];
  for (var i = 0; i < faceCount && cursor < lines.length; i++, cursor++) {
    final parts = lines[cursor].split(RegExp(r'\s+'));
    final count = int.tryParse(parts.first) ?? 0;
    final face = <int>[];
    for (var j = 1; j <= count && j < parts.length; j++) {
      final v = int.tryParse(parts[j]);
      if (v != null && v < vertices.length) face.add(v);
    }
    if (face.length >= 3) faces.add(face);
  }
  return MeshData(vertices: vertices, faces: faces, name: name);
}

String writeOff(MeshData mesh) {
  final buffer = StringBuffer()
    ..writeln('OFF')
    ..writeln('${mesh.vertices.length} ${mesh.faces.length} 0');
  for (final v in mesh.vertices) {
    buffer.writeln('${_fmt(v.x)} ${_fmt(v.y)} ${_fmt(v.z)}');
  }
  for (final face in mesh.faces) {
    buffer.writeln('${face.length} ${face.join(' ')}');
  }
  return buffer.toString();
}

// ─────────────────────────── STL ───────────────────────────

MeshData parseStl(Uint8List bytes, {String name = 'mesh'}) {
  final isAscii = bytes.length < 84 ||
      String.fromCharCodes(bytes.sublist(0, 5)).trimLeft() == 'solid'
          ? _looksAsciiStl(bytes)
          : false;
  if (isAscii) {
    return _parseAsciiStl(String.fromCharCodes(bytes), name: name);
  }
  if (bytes.length < 84) throw const EngineException('STL 文件过短');
  final data = ByteData.sublistView(bytes);
  final count = data.getUint32(80, Endian.little);
  final vertices = <Vec3>[];
  final faces = <List<int>>[];
  var offset = 84;
  for (var i = 0; i < count; i++) {
    if (offset + 50 > bytes.length) break;
    offset += 12; // 法线
    final base = vertices.length;
    for (var j = 0; j < 3; j++) {
      vertices.add(
        Vec3(
          data.getFloat32(offset, Endian.little),
          data.getFloat32(offset + 4, Endian.little),
          data.getFloat32(offset + 8, Endian.little),
        ),
      );
      offset += 12;
    }
    faces.add([base, base + 1, base + 2]);
    offset += 2;
  }
  return MeshData(vertices: vertices, faces: faces, name: name);
}

bool _looksAsciiStl(Uint8List bytes) {
  if (bytes.length < 512) return true;
  final header = bytes.sublist(0, 512);
  final printable = header.where((b) => b == 0x0A || b == 0x0D || (b >= 32 && b < 127)).length;
  return printable > 480;
}

MeshData _parseAsciiStl(String text, {String name = 'mesh'}) {
  final vertices = <Vec3>[];
  final faces = <List<int>>[];
  final face = <int>[];
  for (final rawLine in const LineSplitter().convert(text)) {
    final line = rawLine.trim();
    if (!line.startsWith('vertex ')) continue;
    final parts = line.split(RegExp(r'\s+'));
    if (parts.length < 4) continue;
    vertices.add(
      Vec3(
        double.tryParse(parts[1]) ?? 0,
        double.tryParse(parts[2]) ?? 0,
        double.tryParse(parts[3]) ?? 0,
      ),
    );
    face.add(vertices.length - 1);
    if (face.length == 3) {
      faces.add(List.of(face));
      face.clear();
    }
  }
  return MeshData(vertices: vertices, faces: faces, name: name);
}

Uint8List writeStl(MeshData mesh) {
  final normalized = mesh.normalized();
  final data = ByteData(84 + normalized.faces.length * 50);
  final headerLength = 'OmniForge binary STL'.length;
  for (var i = 0; i < headerLength; i++) {
    data.setUint8(i, 'OmniForge binary STL'.codeUnitAt(i));
  }
  data.setUint32(80, normalized.faces.length, Endian.little);
  var offset = 84;
  for (final face in normalized.faces) {
    final a = normalized.vertices[face[0]];
    final b = normalized.vertices[face[1]];
    final c = normalized.vertices[face[2]];
    final normal = _faceNormal(a, b, c);
    data.setFloat32(offset, normal.x, Endian.little);
    data.setFloat32(offset + 4, normal.y, Endian.little);
    data.setFloat32(offset + 8, normal.z, Endian.little);
    offset += 12;
    for (final v in [a, b, c]) {
      data.setFloat32(offset, v.x, Endian.little);
      data.setFloat32(offset + 4, v.y, Endian.little);
      data.setFloat32(offset + 8, v.z, Endian.little);
      offset += 12;
    }
    data.setUint16(offset, 0, Endian.little);
    offset += 2;
  }
  return data.buffer.asUint8List();
}

Vec3 _faceNormal(Vec3 a, Vec3 b, Vec3 c) {
  final ux = b.x - a.x, uy = b.y - a.y, uz = b.z - a.z;
  final vx = c.x - a.x, vy = c.y - a.y, vz = c.z - a.z;
  final nx = uy * vz - uz * vy;
  final ny = uz * vx - ux * vz;
  final nz = ux * vy - uy * vx;
  final length = math.sqrt(nx * nx + ny * ny + nz * nz);
  if (length == 0) return const Vec3(0, 0, 0);
  return Vec3(nx / length, ny / length, nz / length);
}

// ─────────────────────────── glTF / GLB ───────────────────────────

MeshData parseGltf(String path, Uint8List bytes, {String name = 'mesh'}) {
  if (bytes.length >= 4 && String.fromCharCodes(bytes.sublist(0, 4)) == 'glTF') {
    return _parseGlb(bytes, path, name: name);
  }
  final json = jsonDecode(utf8.decode(bytes, allowMalformed: true));
  if (json is! Map) throw const EngineException('glTF JSON 解析失败');
  return _meshFromGltfJson(json.cast<String, dynamic>(), path, bytes, name);
}

MeshData _parseGlb(Uint8List bytes, String path, {String name = 'mesh'}) {
  final data = ByteData.sublistView(bytes);
  final length = data.getUint32(8, Endian.little);
  var offset = 12;
  Map<String, dynamic>? json;
  Uint8List? buffer;
  while (offset + 8 <= length && offset + 8 <= bytes.length) {
    final chunkLength = data.getUint32(offset, Endian.little);
    final chunkType = String.fromCharCodes(
      bytes.sublist(offset + 4, offset + 8),
    );
    final start = offset + 8;
    final end = (start + chunkLength).clamp(start, bytes.length);
    if (chunkType == 'JSON') {
      json = jsonDecode(utf8.decode(bytes.sublist(start, end),
              allowMalformed: true))
          as Map<String, dynamic>;
    } else if (chunkType == 'BIN\x00' || chunkType.startsWith('BIN')) {
      buffer = bytes.sublist(start, end);
    }
    offset = start + chunkLength;
  }
  if (json == null) throw const EngineException('GLB 缺少 JSON 块');
  return _meshFromGltfJson(json, path, buffer ?? Uint8List(0), name);
}

MeshData _meshFromGltfJson(
  Map<String, dynamic> json,
  String sourcePath,
  Uint8List binaryChunk,
  String name,
) {
  final meshes = (json['meshes'] as List?) ?? const [];
  if (meshes.isEmpty) throw const EngineException('glTF 中没有网格数据');
  final buffers = (json['buffers'] as List?) ?? const [];
  final bufferViews = (json['bufferViews'] as List?) ?? const [];
  final accessors = (json['accessors'] as List?) ?? const [];

  Uint8List resolveBuffer(int index) {
    final buffer = buffers[index] as Map<String, dynamic>;
    final uri = buffer['uri'] as String?;
    if (uri == null || uri.isEmpty) {
      if (binaryChunk.isEmpty) throw const EngineException('glTF 缺少缓冲区数据');
      return binaryChunk;
    }
    if (uri.startsWith('data:')) {
      final comma = uri.indexOf(',');
      final payload = uri.substring(comma + 1);
      return base64Decode(payload);
    }
    // 外部 .bin：仅在同目录存在时读取
    final dir = sourcePath.contains('/')
        ? sourcePath.substring(0, sourcePath.lastIndexOf('/') + 1)
        : '';
    final file = _tryReadFile('$dir$uri');
    if (file == null) {
      throw const EngineException('glTF 引用了外部 .bin 文件，请选择自包含的 .glb');
    }
    return file;
  }

  Uint8List viewBytes(int accessorIndex) {
    final accessor = accessors[accessorIndex] as Map<String, dynamic>;
    final viewIndex = accessor['bufferView'] as int?;
    if (viewIndex == null) throw const EngineException('glTF accessor 无 bufferView');
    final view = bufferViews[viewIndex] as Map<String, dynamic>;
    final buffer = resolveBuffer(view['buffer'] as int);
    final viewOffset = (view['byteOffset'] as int?) ?? 0;
    final start = viewOffset + ((accessor['byteOffset'] as int?) ?? 0);
    final byteLength = (view['byteLength'] as int?) ?? (buffer.length - viewOffset);
    final end = (start + byteLength).clamp(start, buffer.length);
    return buffer.sublist(start, end);
  }

  List<double> readFloats(int accessorIndex) {
    final accessor = accessors[accessorIndex] as Map<String, dynamic>;
    final count = (accessor['count'] as int?) ?? 0;
    final type = (accessor['type'] as String?) ?? 'SCALAR';
    final components = switch (type) {
      'VEC2' => 2,
      'VEC3' => 3,
      'VEC4' => 4,
      'MAT4' => 16,
      _ => 1,
    };
    final bytes = viewBytes(accessorIndex);
    final data = ByteData.sublistView(bytes);
    final result = <double>[];
    final max = count * components;
    for (var i = 0; i < max && (i + 1) * 4 <= bytes.length; i++) {
      result.add(data.getFloat32(i * 4, Endian.little));
    }
    return result;
  }

  List<int> readIndices(int accessorIndex) {
    final accessor = accessors[accessorIndex] as Map<String, dynamic>;
    final count = (accessor['count'] as int?) ?? 0;
    final componentType = (accessor['componentType'] as int?) ?? 5123;
    final bytes = viewBytes(accessorIndex);
    final data = ByteData.sublistView(bytes);
    final result = <int>[];
    for (var i = 0; i < count; i++) {
      switch (componentType) {
        case 5121:
          if (i < bytes.length) result.add(data.getUint8(i));
        case 5123:
          if (i * 2 + 2 <= bytes.length) {
            result.add(data.getUint16(i * 2, Endian.little));
          }
        case 5125:
          if (i * 4 + 4 <= bytes.length) {
            result.add(data.getUint32(i * 4, Endian.little));
          }
      }
    }
    return result;
  }

  final vertices = <Vec3>[];
  final faces = <List<int>>[];
  final mesh = meshes.first as Map<String, dynamic>;
  final primitives = (mesh['primitives'] as List?) ?? const [];
  for (final primitiveRaw in primitives) {
    final primitive = primitiveRaw as Map<String, dynamic>;
    final attributes = (primitive['attributes'] as Map?) ?? const {};
    final positionAccessor = (attributes['POSITION'] as int?);
    if (positionAccessor == null) continue;
    final positions = readFloats(positionAccessor);
    final base = vertices.length;
    for (var i = 0; i + 2 < positions.length; i += 3) {
      vertices.add(Vec3(positions[i], positions[i + 1], positions[i + 2]));
    }
    final indicesRaw = primitive['indices'] as int?;
    if (indicesRaw == null) {
      for (var i = 0; i + 2 < positions.length ~/ 3; i += 3) {
        faces.add([base + i, base + i + 1, base + i + 2]);
      }
      continue;
    }
    final indices = readIndices(indicesRaw);
    final mode = (primitive['mode'] as int?) ?? 4;
    if (mode == 4) {
      for (var i = 0; i + 2 < indices.length; i += 3) {
        faces.add([base + indices[i], base + indices[i + 1], base + indices[i + 2]]);
      }
    } else if (mode == 5 || mode == 6) {
      for (var i = 0; i + 2 < indices.length; i++) {
        faces.add([
          base + indices[i],
          base + indices[i + 1],
          base + indices[i + 2],
        ]);
      }
    }
  }
  return MeshData(vertices: vertices, faces: faces, name: name);
}

Uint8List? _tryReadFile(String path) {
  try {
    final file = File(path);
    if (file.existsSync()) return file.readAsBytesSync();
  } catch (_) {}
  return null;
}

String writeGltfJson(MeshData mesh) {
  final normalized = mesh.normalized();
  final positions = BytesBuilder();
  for (final v in normalized.vertices) {
    final data = ByteData(12);
    data.setFloat32(0, v.x, Endian.little);
    data.setFloat32(4, v.y, Endian.little);
    data.setFloat32(8, v.z, Endian.little);
    positions.add(data.buffer.asUint8List());
  }
  final indices = BytesBuilder();
  for (final face in normalized.faces) {
    final data = ByteData(12);
    data.setUint32(0, face[0], Endian.little);
    data.setUint32(4, face[1], Endian.little);
    data.setUint32(8, face[2], Endian.little);
    indices.add(data.buffer.asUint8List());
  }
  final positionBytes = positions.toBytes();
  final indexBytes = indices.toBytes();
  final buffer = BytesBuilder()
    ..add(positionBytes)
    ..add(indexBytes);
  final total = positionBytes.length + indexBytes.length;

  final json = {
    'asset': {'version': '2.0', 'generator': 'OmniForge'},
    'scene': 0,
    'scenes': [
      {
        'nodes': [0],
      },
    ],
    'nodes': [
      {'mesh': 0, 'name': mesh.name},
    ],
    'meshes': [
      {
        'name': mesh.name,
        'primitives': [
          {
            'attributes': {'POSITION': 0},
            'indices': 1,
            'mode': 4,
          },
        ],
      },
    ],
    'buffers': [
      {
        'byteLength': total,
        'uri':
            'data:application/octet-stream;base64,${base64Encode(buffer.toBytes())}',
      },
    ],
    'bufferViews': [
      {'buffer': 0, 'byteOffset': 0, 'byteLength': positionBytes.length, 'target': 34962},
      {
        'buffer': 0,
        'byteOffset': positionBytes.length,
        'byteLength': indexBytes.length,
        'target': 34963,
      },
    ],
    'accessors': [
      {
        'bufferView': 0,
        'componentType': 5126,
        'count': normalized.vertices.length,
        'type': 'VEC3',
        'min': _bounds(normalized).$1,
        'max': _bounds(normalized).$2,
      },
      {
        'bufferView': 1,
        'componentType': 5125,
        'count': normalized.faces.length * 3,
        'type': 'SCALAR',
      },
    ],
  };
  return const JsonEncoder.withIndent('  ').convert(json);
}

(List<double>, List<double>) _bounds(MeshData mesh) {
  if (mesh.vertices.isEmpty) return ([0, 0, 0], [0, 0, 0]);
  var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
  var maxX = -double.infinity, maxY = -double.infinity, maxZ = -double.infinity;
  for (final v in mesh.vertices) {
    if (v.x < minX) minX = v.x;
    if (v.y < minY) minY = v.y;
    if (v.z < minZ) minZ = v.z;
    if (v.x > maxX) maxX = v.x;
    if (v.y > maxY) maxY = v.y;
    if (v.z > maxZ) maxZ = v.z;
  }
  return (
    [minX, minY, minZ],
    [maxX, maxY, maxZ],
  );
}

Uint8List writeGlb(MeshData mesh) {
  final normalized = mesh.normalized();
  final positions = BytesBuilder();
  for (final v in normalized.vertices) {
    final data = ByteData(12);
    data.setFloat32(0, v.x, Endian.little);
    data.setFloat32(4, v.y, Endian.little);
    data.setFloat32(8, v.z, Endian.little);
    positions.add(data.buffer.asUint8List());
  }
  final indices = BytesBuilder();
  for (final face in normalized.faces) {
    final data = ByteData(12);
    data.setUint32(0, face[0], Endian.little);
    data.setUint32(4, face[1], Endian.little);
    data.setUint32(8, face[2], Endian.little);
    indices.add(data.buffer.asUint8List());
  }
  final positionBytes = positions.toBytes();
  final indexBytes = indices.toBytes();
  final binBuffer = BytesBuilder()
    ..add(positionBytes)
    ..add(indexBytes);
  var bin = binBuffer.toBytes();
  while (bin.length % 4 != 0) {
    bin = Uint8List.fromList([...bin, 0]);
  }
  final json = {
    'asset': {'version': '2.0', 'generator': 'OmniForge'},
    'scene': 0,
    'scenes': [
      {
        'nodes': [0],
      },
    ],
    'nodes': [
      {'mesh': 0, 'name': mesh.name},
    ],
    'meshes': [
      {
        'name': mesh.name,
        'primitives': [
          {
            'attributes': {'POSITION': 0},
            'indices': 1,
            'mode': 4,
          },
        ],
      },
    ],
    'buffers': [
      {'byteLength': bin.length},
    ],
    'bufferViews': [
      {'buffer': 0, 'byteOffset': 0, 'byteLength': positionBytes.length, 'target': 34962},
      {
        'buffer': 0,
        'byteOffset': positionBytes.length,
        'byteLength': indexBytes.length,
        'target': 34963,
      },
    ],
    'accessors': [
      {
        'bufferView': 0,
        'componentType': 5126,
        'count': normalized.vertices.length,
        'type': 'VEC3',
        'min': [0, 0, 0],
        'max': [0, 0, 0],
      },
      {
        'bufferView': 1,
        'componentType': 5125,
        'count': normalized.faces.length * 3,
        'type': 'SCALAR',
      },
    ],
  };
  final jsonBytes = utf8.encode(jsonEncode(json));
  final paddedJson = _pad(jsonBytes);
  final total = 12 + 8 + paddedJson.length + 8 + bin.length;
  final out = ByteData(total);
  // header
  final header = 'glTF';
  for (var i = 0; i < 4; i++) {
    out.setUint8(i, header.codeUnitAt(i));
  }
  out.setUint32(4, 2, Endian.little);
  out.setUint32(8, total, Endian.little);
  var offset = 12;
  out.setUint32(offset, paddedJson.length, Endian.little);
  for (var i = 0; i < 4; i++) {
    out.setUint8(offset + 4 + i, 'JSON'.codeUnitAt(i));
  }
  offset += 8;
  final jsonOut = out.buffer.asUint8List();
  jsonOut.setRange(offset, offset + paddedJson.length, paddedJson);
  offset += paddedJson.length;
  out.setUint32(offset, bin.length, Endian.little);
  for (var i = 0; i < 4; i++) {
    out.setUint8(offset + 4 + i, 'BIN\u0000'.codeUnitAt(i));
  }
  offset += 8;
  jsonOut.setRange(offset, offset + bin.length, bin);
  return jsonOut;
}

Uint8List _pad(List<int> bytes) {
  final remainder = bytes.length % 4;
  if (remainder == 0) return Uint8List.fromList(bytes);
  return Uint8List.fromList([...bytes, ...List.filled(4 - remainder, 0x20)]);
}

String _fmt(double value) {
  if (value == value.roundToDouble() && value.abs() < 1e15) {
    return value.toInt().toString();
  }
  return value.toStringAsFixed(6);
}
