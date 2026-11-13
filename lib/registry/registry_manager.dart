import 'package:flutter/services.dart' show rootBundle;
import 'package:yaml/yaml.dart';
import '../models/format_node.dart';

/// 全局注册中心（单例）
///
/// 启动时一次性加载 assets/formats.yaml，之后 UI 全部从这里取数据，
/// 不再维护第二份写死的类型 / 格式表。
class RegistryManager {
  static final RegistryManager _instance = RegistryManager._internal();
  factory RegistryManager() => _instance;
  RegistryManager._internal();

  List<FormatNode> _formats = [];
  List<FormatCategory> _categories = [];
  List<FlowRule> _flows = [];
  String _stage = 'shell';
  bool _initialized = false;

  bool get isInitialized => _initialized;

  /// 当前是否处于「空壳」阶段：格式已全量登记，转换引擎尚未接入
  bool get isShellStage => _stage == 'shell';

  /// 启动时加载 formats.yaml（可重复调用，只会真正加载一次）
  Future<void> initialize() async {
    if (_initialized) return;
    final yamlString = await rootBundle.loadString('assets/formats.yaml');
    final doc = loadYaml(yamlString) as Map;

    _stage = (doc['stage'] ?? 'shell').toString();

    _categories = (doc['categories'] as List? ?? [])
        .map((c) => FormatCategory.fromYaml(Map.from(c as Map)))
        .toList();

    _formats = (doc['formats'] as List? ?? [])
        .map((f) => FormatNode.fromYaml(Map.from(f as Map)))
        .where((f) => f.id.isNotEmpty)
        .toList();

    _flows = (doc['flows'] as List? ?? [])
        .map((f) => FlowRule.fromYaml(Map.from(f as Map)))
        .toList();

    _initialized = true;
  }

  List<FormatNode> getAllFormats() => List.unmodifiable(_formats);

  /// 全部分类，按 order 升序
  List<FormatCategory> getCategories() {
    final list = List<FormatCategory>.from(_categories);
    list.sort((a, b) => a.order.compareTo(b.order));
    return List.unmodifiable(list);
  }

  FormatCategory? getCategory(String key) {
    for (final c in _categories) {
      if (c.key == key) return c;
    }
    return null;
  }

  FormatNode? getFormatById(String id) {
    for (final f in _formats) {
      if (f.id == id) return f;
    }
    return null;
  }

  /// 某分类下的全部格式（跨类共享的格式会同时出现在多个分类里）
  List<FormatNode> getFormatsByCategory(String category) {
    return _formats.where((f) => f.categories.contains(category)).toList();
  }

  /// 按扩展名反查格式（不带点、小写）
  FormatNode? getFormatByExtension(String ext) {
    final e = ext.toLowerCase();
    for (final f in _formats) {
      for (final x in f.extensions) {
        if (x.startsWith('.') && x.substring(1) == e) return f;
      }
    }
    return null;
  }

  List<FlowRule> getAllFlows() => List.unmodifiable(_flows);
}
