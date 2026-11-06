import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:yaml/yaml.dart';
import '../models/format_node.dart';

/// 全局注册中心（单例）
class RegistryManager {
  static final RegistryManager _instance = RegistryManager._internal();
  factory RegistryManager() => _instance;
  RegistryManager._internal();

  List<FormatNode> _formats = [];
  List<FlowRule> _flows = [];

  /// 启动时加载 formats.yaml
  Future<void> initialize() async {
    final yamlString = await rootBundle.loadString('assets/formats.yaml');
    final doc = loadYaml(yamlString) as Map;

    _formats = (doc['formats'] as List? ?? [])
        .map((f) => FormatNode.fromYaml(Map.from(f as Map)))
        .toList();

    _flows = (doc['flows'] as List? ?? [])
        .map((f) => FlowRule.fromYaml(Map.from(f as Map)))
        .toList();
  }

  List<FormatNode> getAllFormats() => List.unmodifiable(_formats);

  FormatNode? getFormatById(String id) {
    return _formats.firstWhere((f) => f.id == id);
  }

  List<FormatNode> getFormatsByCategory(String category) {
    return _formats.where((f) => f.category == category).toList();
  }

  List<FlowRule> getAllFlows() => List.unmodifiable(_flows);
}
