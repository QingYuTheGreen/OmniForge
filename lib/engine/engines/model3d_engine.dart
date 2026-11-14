import 'dart:convert';

import '../engine_utils.dart';
import '../i_engine.dart';
import 'mesh_engine.dart';
import 'mesh_io.dart';

/// 3D 模型引擎：OBJ / STL / PLY / OFF / GLTF / GLB 互转。
/// FBX 为专有二进制格式，需要插件。
class Model3DEngine extends SimpleEngine {
  const Model3DEngine();

  @override
  String get id => 'model3d';

  static const supported = {'obj', 'stl', 'ply', 'off', 'gltf', 'glb'};

  @override
  Future<void> execute(EngineContext context) async {
    final mesh = readMesh(context.inputPath);
    if (mesh.vertices.isEmpty) {
      throw const EngineException('模型中没有顶点数据');
    }
    final target = context.targetFormat.toLowerCase();
    switch (target) {
      case 'obj':
        await writeFileText(context.outputPath, writeObj(mesh));
      case 'stl':
        await writeFileBytes(context.outputPath, writeStl(mesh));
      case 'ply':
        await writeFileText(context.outputPath, writePly(mesh));
      case 'off':
        await writeFileText(context.outputPath, writeOff(mesh));
      case 'gltf':
        await writeFileBytes(
          context.outputPath,
          utf8.encode(writeGltfJson(mesh)),
        );
      case 'glb':
        await writeFileBytes(context.outputPath, writeGlb(mesh));
      default:
        throw EngineException(
          target == 'fbx'
              ? 'FBX 为专有二进制格式，需要安装 3D 插件后转换'
              : '3D 引擎不支持输出格式：$target',
        );
    }
  }
}
