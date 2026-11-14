import 'dart:io';

import 'package:path/path.dart' as p;

import 'plugin_catalog.dart';
import 'plugin_manifest.dart';

/// 插件安装状态。
///
/// - [missing]：未安装（或库文件被删除 / 不可读），需要用户下载 / 导入；
/// - [installed]：平台库文件已就位且可读，可以 `DynamicLibrary.open`；
/// - [incompatible]：当前平台不在插件支持列表内（或文件存在但无法读取）。
enum PluginInstallState { missing, installed, incompatible }

/// 原生插件注册表：管理插件的安装目录、状态与文件路径。
///
/// 纯 Dart（dart:io + path），不 import Flutter。
/// [installDir] 由 UI 层通过 path_provider 提供：
/// - Android：`getApplicationSupportDirectory()`（如 /data/user/0/包名/files）
/// - iOS：`getApplicationSupportDirectory()`
/// - Windows / macOS / Linux：`getApplicationSupportDirectory()` 或 `getApplicationDocumentsDirectory()`
///
/// 插件实际落盘位置：`<installDir>/plugins/<pluginId>/<平台库文件名>`。
class NativePluginRegistry {
  NativePluginRegistry({
    required this.installDir,
    List<PluginManifest>? manifests,
    String? platform,
  })  : _manifests = List<PluginManifest>.unmodifiable(
          manifests ?? PluginCatalog.builtIn,
        ),
        platform = PluginManifest.normalizePlatform(
          platform ?? Platform.operatingSystem,
        ) {
    _manifestById = <String, PluginManifest>{
      for (final manifest in _manifests) manifest.id: manifest,
    };
  }

  /// 应用可写数据根目录（UI 层注入）。
  final Directory installDir;

  /// 当前平台（规范化后的小写名）。
  final String platform;

  final List<PluginManifest> _manifests;
  late final Map<String, PluginManifest> _manifestById;

  /// 全部插件清单。
  List<PluginManifest> get manifests => _manifests;

  /// 插件安装目录：`<installDir>/plugins/<id>`。
  Directory pluginDir(String id) =>
      Directory(p.join(installDir.path, 'plugins', id));

  /// 按插件 id 取清单（未知 id 返回 null）。
  PluginManifest? manifestForId(String id) => _manifestById[id];

  /// 按引擎 id 取插件清单（无对应插件返回 null）。
  PluginManifest? manifestForEngine(String engineId) {
    for (final manifest in _manifests) {
      if (manifest.engineIds.contains(engineId)) return manifest;
    }
    return null;
  }

  /// 插件平台库文件的完整路径（未安装时也返回路径，便于安装时写入）。
  String libraryPathOf(String id) {
    final manifest = _manifestById[id];
    if (manifest == null) {
      throw ArgumentError.value(id, 'id', '未知插件');
    }
    return p.join(pluginDir(id).path, manifest.libraryFileName(platform));
  }

  /// 插件平台库文件路径；未安装 / 不可读时返回 null。
  String? pathOf(String id) {
    if (stateOf(id) != PluginInstallState.installed) return null;
    return libraryPathOf(id);
  }

  /// 插件当前安装状态。
  PluginInstallState stateOf(String id) {
    final manifest = _manifestById[id];
    if (manifest == null) return PluginInstallState.missing;
    if (!manifest.supportsPlatform(platform)) {
      return PluginInstallState.incompatible;
    }
    final file = File(libraryPathOf(id));
    if (!file.existsSync()) return PluginInstallState.missing;
    // 存在但打不开（权限 / 损坏 / 是目录）视为不兼容，提示用户重新导入。
    try {
      final handle = file.openSync();
      handle.closeSync();
    } on FileSystemException {
      return PluginInstallState.incompatible;
    }
    return PluginInstallState.installed;
  }

  /// 安装插件：把 [libFile] 原子拷贝到插件目录。
  ///
  /// 先写同目录临时文件再 rename，避免下载中断留下半个库文件。
  /// 非法 id / 平台不支持 / 源文件缺失时抛 [ArgumentError] 或 [FileSystemException]。
  Future<void> install(String id, File libFile) async {
    final manifest = _manifestById[id];
    if (manifest == null) {
      throw ArgumentError.value(id, 'id', '未知插件');
    }
    if (!manifest.supportsPlatform(platform)) {
      throw ArgumentError.value(
        platform,
        'platform',
        '插件 ${manifest.name} 不支持当前平台',
      );
    }
    if (!await libFile.exists()) {
      throw FileSystemException('插件库文件不存在', libFile.path);
    }
    if (await libFile.length() == 0) {
      throw ArgumentError.value(libFile.path, 'libFile', '插件库文件为空');
    }

    final directory = pluginDir(id);
    await directory.create(recursive: true);
    final target = File(libraryPathOf(id));
    final temporary = File('${target.path}.tmp');

    try {
      await libFile.copy(temporary.path);
      if (await target.exists()) {
        await target.delete();
      }
      await temporary.rename(target.path);
    } finally {
      if (await temporary.exists()) {
        await temporary.delete();
      }
    }
  }

  /// 卸载插件：删除插件目录（不存在时静默返回）。
  Future<void> uninstall(String id) async {
    final directory = pluginDir(id);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}
