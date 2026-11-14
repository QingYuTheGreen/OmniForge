import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../engine_utils.dart';
import '../i_engine.dart';
import 'mesh_io.dart';

/// 网格引擎：OBJ / PLY / OFF / STL 互转（纯 Dart 解析与生成）。
class MeshEngine extends SimpleEngine {
  const MeshEngine();

  @override
  String get id => 'mesh';

  static const supported = {'obj', 'ply', 'off', 'stl'};

  @override
  Future<void> execute(EngineContext context) async {
    final mesh = readMesh(context.inputPath);
    if (mesh.vertices.isEmpty || mesh.faces.isEmpty) {
      throw const EngineException('网格文件为空或没有三角面');
    }
    final target = context.targetFormat.toLowerCase();
    switch (target) {
      case 'obj':
        await writeFileText(context.outputPath, writeObj(mesh));
      case 'ply':
        await writeFileText(context.outputPath, writePly(mesh));
      case 'off':
        await writeFileText(context.outputPath, writeOff(mesh));
      case 'stl':
        await writeFileBytes(context.outputPath, writeStl(mesh));
      default:
        throw EngineException('网格引擎不支持输出格式：$target');
    }
  }
}

/// 按扩展名读取任意受支持的网格文件。
MeshData readMesh(String path) {
  final extension = p.extension(path).replaceFirst('.', '').toLowerCase();
  final name = p.basenameWithoutExtension(path);
  final bytes = File(path).readAsBytesSync();
  switch (extension) {
    case 'obj':
      return parseObj(utf8.decode(bytes, allowMalformed: true), name: name);
    case 'ply':
      return parsePly(bytes, name: name);
    case 'off':
      return parseOff(utf8.decode(bytes, allowMalformed: true), name: name);
    case 'stl':
      return parseStl(bytes, name: name);
    case 'gltf':
    case 'glb':
      return parseGltf(path, bytes, name: name);
    default:
      throw EngineException('不支持读取该三维格式：$extension');
  }
}
