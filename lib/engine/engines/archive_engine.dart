
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../engine_utils.dart';
import '../i_engine.dart';

/// 压缩包引擎：zip / tar / tar.gz 互转；rar / 7z 需要插件。
class ArchiveEngine extends SimpleEngine {
  const ArchiveEngine();

  @override
  String get id => 'archive';

  static const supported = {'zip', 'tar', 'tar_gz', 'tgz', 'gzip', 'gz'};

  @override
  void validate(EngineContext context) {
    final source = _sourceKind(context.inputPath);
    if (source == 'rar' || source == 'seven_z' || source == '7z') {
      throw PluginRequiredException(source, 12);
    }
  }

  @override
  Future<void> execute(EngineContext context) async {
    final archive = await _readArchive(context.inputPath);
    final target = _targetKind(context.targetFormat.toLowerCase());
    switch (target) {
      case 'zip':
        await writeFileBytes(
          context.outputPath,
          ZipEncoder().encode(archive),
        );
      case 'tar':
        await writeFileBytes(context.outputPath, TarEncoder().encode(archive));
      case 'tar_gz':
        await writeFileBytes(
          context.outputPath,
          GZipEncoder().encode(TarEncoder().encode(archive)),
        );
      default:
        throw EngineException('压缩包引擎不支持输出格式：${context.targetFormat}');
    }
  }

  String _sourceKind(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.tar.gz') || lower.endsWith('.tgz')) return 'tar_gz';
    return p.extension(lower).replaceFirst('.', '');
  }

  String _targetKind(String target) {
    switch (target) {
      case 'tar.gz':
      case 'targz':
      case 'tgz':
      case 'gzip':
      case 'gz':
        return 'tar_gz';
      case '7z':
      case 'seven_z':
      case 'rar':
        throw PluginRequiredException(target, target == 'rar' ? 18 : 12);
      default:
        return target;
    }
  }

  Future<Archive> _readArchive(String path) async {
    final kind = _sourceKind(path);
    final bytes = await readFileBytes(path);
    switch (kind) {
      case 'zip':
        return ZipDecoder().decodeBytes(bytes);
      case 'tar':
        return TarDecoder().decodeBytes(bytes);
      case 'tar_gz':
        final decompressed = GZipDecoder().decodeBytes(bytes);
        return TarDecoder().decodeBytes(decompressed);
      case 'gzip' || 'gz':
        final decompressed = GZipDecoder().decodeBytes(bytes);
        final name = p.basenameWithoutExtension(path);
        return Archive()
          ..addFile(ArchiveFile(name, decompressed.length, decompressed));
      default:
        throw PluginRequiredException(kind, 12);
    }
  }
}
