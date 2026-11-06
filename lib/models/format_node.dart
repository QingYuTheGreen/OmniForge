/// 格式节点数据模型
class FormatNode {
  final String id;
  final String name;
  final String category;
  final List<String> extensions;
  final List<String> acceptsFrom;
  final List<String> engines;
  final List<ParamDef> params;

  FormatNode({
    required this.id,
    required this.name,
    required this.category,
    this.extensions = const [],
    this.acceptsFrom = const [],
    this.engines = const [],
    this.params = const [],
  });

  factory FormatNode.fromYaml(Map yaml) => FormatNode(
        id: yaml['id'] ?? '',
        name: yaml['name'] ?? '',
        category: yaml['category'] ?? '',
        extensions: List<String>.from(yaml['extensions'] ?? []),
        acceptsFrom: List<String>.from(yaml['accepts_from'] ?? []),
        engines: List<String>.from(yaml['engines'] ?? []),
        params: (yaml['params'] as List? ?? [])
            .map((p) => ParamDef.fromYaml(p))
            .toList(),
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
            .map((p) => ParamDef.fromYaml(p))
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

  factory ParamDef.fromYaml(Map yaml) => ParamDef(
        key: yaml['key'] ?? '',
        type: ParamType.values.firstWhere(
          (t) => t.name == (yaml['type'] ?? 'text').toString().toUpperCase(),
          orElse: () => ParamType.text,
        ),
        label: yaml['label'] ?? '',
        defaultValue: yaml['default']?.toString() ?? '',
        min: (yaml['min'] as num?)?.toDouble(),
        max: (yaml['max'] as num?)?.toDouble(),
        step: (yaml['step'] as num?)?.toDouble(),
        options: List<String>.from(yaml['options'] ?? []),
      );
}

enum ParamType { slider, switch$, dropdown, text }
