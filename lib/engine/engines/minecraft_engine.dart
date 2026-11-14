import 'dart:convert';

import 'package:archive/archive.dart';

import '../engine_utils.dart';
import '../i_engine.dart';

/// Minecraft 存档 / 资源包引擎：mcworld / mcpack（基岩版）与
/// mcworld_java / mcpack_java（Java 版）都是 zip 容器，可互相重打包，
/// 普通 zip 也能转为对应的 Minecraft 包。
class MinecraftEngine extends SimpleEngine {
  const MinecraftEngine();

  @override
  String get id => 'minecraft';

  static const supported = {
    'mcworld',
    'mcpack',
    'mcworld_java',
    'mcpack_java',
    'zip',
  };

  @override
  Future<void> execute(EngineContext context) async {
    final bytes = await readFileBytes(context.inputPath);
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const EngineException('Minecraft 包必须是 zip 容器');
    }
    final target = context.targetFormat.toLowerCase();
    if (!supported.contains(target)) {
      throw EngineException('不支持的 Minecraft 目标格式：$target');
    }

    final files = archive.files.where((f) => f.isFile).toList();
    if (files.isEmpty) {
      throw const EngineException('压缩包为空');
    }

    final output = Archive();
    final prefix = _prefixOf(target);
    for (final file in files) {
      final name = _stripKnownPrefix(file.name);
      final targetName = prefix.isEmpty ? name : '$prefix/$name';
      final content = file.content as List<int>;
      output.addFile(ArchiveFile(targetName, content.length, content));
    }
    if (prefix == 'behavior_packs' || prefix == 'resource_packs') {
      _ensureManifest(output, prefix);
    }
    final encoded = ZipEncoder().encode(output);
    await writeFileBytes(context.outputPath, encoded);
  }

  String _prefixOf(String target) {
    switch (target) {
      case 'mcpack':
        return 'resource_packs';
      case 'mcpack_java':
        return 'resource_packs';
      case 'mcworld':
      case 'mcworld_java':
      case 'zip':
        return '';
      default:
        return '';
    }
  }

  String _stripKnownPrefix(String name) {
    final normalized = name.replaceAll('\\', '/');
    for (final prefix in ['resource_packs/', 'behavior_packs/']) {
      if (normalized.startsWith(prefix)) {
        return normalized.substring(prefix.length);
      }
    }
    return normalized;
  }

  void _ensureManifest(Archive archive, String folder) {
    final manifest = {
      'format_version': 2,
      'header': {
        'name': 'OmniForge Converted Pack',
        'description': '由 OmniForge 转换生成',
        'uuid': _stableUuid(folder),
        'version': [1, 0, 0],
        'min_engine_version': [1, 20, 0],
      },
      'modules': [
        {
          'type': folder == 'resource_packs' ? 'resources' : 'data',
          'uuid': _stableUuid('$folder-module'),
          'version': [1, 0, 0],
        },
      ],
    };
    final json = JsonEncoder.withIndent('  ').convert(manifest);
    final bytes = json.codeUnits;
    archive.addFile(
      ArchiveFile('manifest.json', bytes.length, bytes),
    );
  }

  String _stableUuid(String seed) {
    var hash = 0;
    for (final unit in seed.codeUnits) {
      hash = (hash * 31 + unit) & 0xFFFFFFFF;
    }
    final hex = hash.toRadixString(16).padLeft(8, '0');
    return '${hex.substring(0, 8)}-0000-4000-8000-$hex${hex.substring(0, 4)}';
  }
}
