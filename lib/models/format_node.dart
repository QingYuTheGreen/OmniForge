/// 格式节点数据模型
class FormatNode {
  final String id;
  final String name;

  /// 所属分类键（一个格式可跨类，如 pdf 属于 document / ebook / slides）
  final List<String> categories;
  final List<String> extensions;
  final List<String> acceptsFrom;
  final List<String> engines;
  final List<ParamDef> params;

  /// planned = 已登记未接入（空壳）；ready = 引擎可用
  final String status;

  /// 备注（如「本质是 zip」「接受任意文件输入」）
  final String? note;

  FormatNode({
    required this.id,
    required this.name,
    this.categories = const [],
    this.extensions = const [],
    this.acceptsFrom = const [],
    this.engines = const [],
    this.params = const [],
    this.status = 'planned',
    this.note,
  });

  /// 主分类（第一个），兼容旧调用
  String get category => categories.isEmpty ? '' : categories.first;

  /// 是否还只是空壳（引擎未接入）
  bool get isPlanned => status != 'ready';

  factory FormatNode.fromYaml(Map yaml) {
    final rawCats = yaml['categories'] as List?;
    final categories = rawCats != null
        ? List<String>.from(rawCats)
        : (yaml['category'] != null ? [yaml['category'].toString()] : <String>[]);
    return FormatNode(
      id: yaml['id']?.toString() ?? '',
      name: yaml['name']?.toString() ?? '',
      categories: categories.where((c) => c.isNotEmpty).toList(),
      extensions: List<String>.from(yaml['extensions'] ?? []),
      acceptsFrom: List<String>.from(yaml['accepts_from'] ?? []),
      engines: List<String>.from(yaml['engines'] ?? []),
      params: (yaml['params'] as List? ?? [])
          .map((p) => ParamDef.fromYaml(Map.from(p as Map)))
          .toList(),
      status: yaml['status']?.toString() ?? 'planned',
      note: yaml['note']?.toString(),
    );
  }
}

/// 分类（19 大类）
class FormatCategory {
  final String key;
  final String name;

  /// Material 图标名，UI 侧映射成 IconData
  final String icon;
  final int order;

  const FormatCategory({
    required this.key,
    required this.name,
    this.icon = 'insert_drive_file',
    this.order = 0,
  });

  factory FormatCategory.fromYaml(Map yaml) => FormatCategory(
        key: yaml['key']?.toString() ?? '',
        name: yaml['name']?.toString() ?? '',
        icon: yaml['icon']?.toString() ?? 'insert_drive_file',
        order: (yaml['order'] as num?)?.toInt() ?? 0,
      );
}

/// 转换链路规则
class FlowRule {
  final String name;
  final List<String> source;
  final List<String> target;
  final String engine;
  final List<ParamDef> params;

  FlowRule({
    required this.name,
    required this.source,
    required this.target,
    required this.engine,
    this.params = const [],
  });

  factory FlowRule.fromYaml(Map yaml) => FlowRule(
        name: yaml['name'] ?? '',
        source: List<String>.from(yaml['source'] ?? []),
        target: List<String>.from(yaml['target'] ?? []),
        engine: yaml['engine'] ?? '',
        params: (yaml['params'] as List? ?? [])
            .map((p) => ParamDef.fromYaml(Map.from(p as Map)))
            .toList(),
      );
}

/// 参数定义
class ParamDef {
  final String key;
  final ParamType type;
  final String label;
  final String defaultValue;
  final double? min;
  final double? max;
  final double? step;
  final List<String> options;

  ParamDef({
    required this.key,
    required this.type,
    required this.label,
    this.defaultValue = '',
    this.min,
    this.max,
    this.step,
    this.options = const [],
  });

  factory ParamDef.fromYaml(Map yaml) {
    final raw = (yaml['type'] ?? 'text').toString().toLowerCase();
    return ParamDef(
        key: yaml['key']?.toString() ?? '',
        type: _parseType(raw),
        label: yaml['label'] ?? '',
        defaultValue: yaml['default']?.toString() ?? '',
        min: (yaml['min'] as num?)?.toDouble(),
        max: (yaml['max'] as num?)?.toDouble(),
        step: (yaml['step'] as num?)?.toDouble(),
        options: List<String>.from(yaml['options'] ?? []),
    );
  }

  static ParamType _parseType(String raw) {
    switch (raw) {
      case 'slider':
        return ParamType.slider;
      case 'switch':
        return ParamType.switch$;
      case 'dropdown':
      case 'select':
        return ParamType.dropdown;
      default:
        return ParamType.text;
    }
  }
}

enum ParamType { slider, switch$, dropdown, text }
