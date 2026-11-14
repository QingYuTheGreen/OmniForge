/// 原生转换插件：清单模型。
///
/// 一个插件 = 一份清单（描述信息）+ 一个平台相关的动态库文件。
/// 清单不依赖 Flutter / dart:io，可被 UI、注册表、引擎共用。
class PluginManifest {
  /// 插件唯一 id（也用作目录名），例如 `ocr`。
  final String id;

  /// 展示名称，例如 `OCR 文字识别`。
  final String name;

  /// 面向用户的说明，例如「图片 → txt，RapidOCR 原生推理」。
  final String description;

  /// 安装包/插件体积（MB），用于下载确认框展示。
  final int sizeMb;

  /// 支持平台（小写，规范化后）：android/ios/windows/macos/linux/ohos。
  final List<String> platforms;

  /// 该插件负责实现的引擎 id，例如 `['ocr']`。
  final List<String> engineIds;

  /// 库文件基名（不含 `lib` 前缀与扩展名），例如 `omniforge_ocr`。
  /// 平台相关的完整文件名由 [libraryFileName] 生成。
  final String fileName;

  /// 原生库导出的转换入口符号，默认 `omniforge_convert`。
  final String symbol;

  /// 附加说明（后端、模型、许可证等），键值对直接展示给用户。
  final Map<String, String> notes;

  const PluginManifest({
    required this.id,
    required this.name,
    required this.description,
    required this.sizeMb,
    required this.platforms,
    required this.engineIds,
    required this.fileName,
    this.symbol = 'omniforge_convert',
    this.notes = const {},
  })  : assert(id != '', '插件 id 不能为空'),
        assert(sizeMb > 0, '插件体积必须大于 0'),
        assert(fileName != '', '库文件基名不能为空');

  /// 从 Map（JSON / YAML / 下载的服务端清单）构造。
  ///
  /// 缺少必填字段或取值非法时抛 [FormatException]。
  factory PluginManifest.fromMap(Map<dynamic, dynamic> map) {
    final id = _requiredString(map, 'id');
    final sizeMb =
        _requiredPositiveInt(map, 'sizeMb', aliases: const ['size_mb']);
    final platforms = _stringList(map['platforms']);
    if (platforms.isEmpty) {
      throw const FormatException('插件 platforms 不能为空');
    }
    final engineIds = _stringList(map['engineIds'] ?? map['engine_ids']);
    if (engineIds.isEmpty) {
      throw const FormatException('插件 engineIds 不能为空');
    }
    final fileName = (map['fileName'] ?? map['file_name'])?.toString().trim();
    final symbol = (map['symbol'] ?? 'omniforge_convert').toString().trim();

    return PluginManifest(
      id: id,
      name: (map['name'] ?? id).toString().trim(),
      description: (map['description'] ?? '').toString().trim(),
      sizeMb: sizeMb,
      platforms: List<String>.unmodifiable(
          platforms.map(PluginManifest.normalizePlatform)),
      engineIds: List<String>.unmodifiable(engineIds),
      fileName:
          (fileName == null || fileName.isEmpty) ? 'omniforge_$id' : fileName,
      symbol: symbol.isEmpty ? 'omniforge_convert' : symbol,
      notes: _stringMap(map['notes']),
    );
  }

  /// 指定平台应使用的库文件名：
  /// - android / linux / ohos → `libomniforge_<id>.so`
  /// - windows → `omniforge_<id>.dll`
  /// - ios / macos → `libomniforge_<id>.dylib`
  ///
  /// 未知平台按 ELF 约定（`.so`）处理。
  String libraryFileName(String platform) {
    final normalized = normalizePlatform(platform);
    final String extension;
    final String prefix;
    switch (normalized) {
      case 'windows':
        extension = 'dll';
        prefix = '';
        break;
      case 'macos':
      case 'ios':
        extension = 'dylib';
        prefix = 'lib';
        break;
      default:
        extension = 'so';
        prefix = 'lib';
    }
    return '$prefix$fileName.$extension';
  }

  /// 是否支持指定平台（大小写、`mac`/`darwin` 等别名均已归一化）。
  bool supportsPlatform(String platform) {
    final normalized = normalizePlatform(platform);
    return platforms.any((item) => normalizePlatform(item) == normalized);
  }

  /// 平台名归一化：`mac`/`osx`/`darwin` → `macos`，`win`/`win32` → `windows`。
  static String normalizePlatform(String platform) {
    final value = platform.trim().toLowerCase();
    switch (value) {
      case 'mac':
      case 'osx':
      case 'darwin':
        return 'macos';
      case 'win':
      case 'win32':
        return 'windows';
      default:
        return value;
    }
  }

  /// 序列化回 Map（便于缓存 / 上报）。
  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'name': name,
        'description': description,
        'sizeMb': sizeMb,
        'platforms': platforms,
        'engineIds': engineIds,
        'fileName': fileName,
        'symbol': symbol,
        'notes': notes,
      };

  @override
  String toString() => 'PluginManifest($id, ${sizeMb}MB, $platforms)';
}

String _requiredString(Map<dynamic, dynamic> map, String key) {
  final value = map[key]?.toString().trim() ?? '';
  if (value.isEmpty) {
    throw FormatException('插件清单缺少必填字段 $key');
  }
  return value;
}

int _requiredPositiveInt(
  Map<dynamic, dynamic> map,
  String key, {
  List<String> aliases = const [],
}) {
  Object? raw = map[key];
  for (final alias in aliases) {
    raw ??= map[alias];
  }
  final value = raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
  if (value == null || value <= 0) {
    throw FormatException('插件清单字段 $key 必须是大于 0 的整数');
  }
  return value;
}

List<String> _stringList(Object? raw) {
  if (raw == null) return const [];
  final items = raw is List ? raw : raw.toString().split(',');
  return items
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

Map<String, String> _stringMap(Object? raw) {
  if (raw is Map) {
    return Map<String, String>.unmodifiable(<String, String>{
      for (final entry in raw.entries)
        entry.key.toString(): entry.value.toString(),
    });
  }
  return const {};
}
