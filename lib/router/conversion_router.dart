import '../models/format_node.dart';
import '../registry/registry_manager.dart';

/// 路由结果
class RouteResult {
  final List<FormatNode> direct;
  final List<FormatNode> multiHop;

  RouteResult({required this.direct, required this.multiHop});
}

/// 智能路由：BFS 广度优先搜索
class ConversionRouter {
  final RegistryManager _registry = RegistryManager();

  /// 从源格式出发，找出所有可达目标
  RouteResult findReachableTargets(String sourceId) {
    final formats = _registry.getAllFormats();
    final flows = _registry.getAllFlows();

    // 构建邻接表
    final adjacency = <String, Set<String>>{};

    // FlowRule 直接边
    for (final flow in flows) {
      for (final src in flow.source) {
        for (final tgt in flow.target) {
          adjacency.putIfAbsent(src, () => {}).add(tgt);
        }
      }
    }

    // acceptsFrom 反向边；accepts_from 写 "*" 表示接受任意格式（哈希类）
    for (final target in formats) {
      for (final accepted in target.acceptsFrom) {
        final isAll = accepted == '*';
        for (final source in formats) {
          final matched = isAll ||
              source.id == accepted ||
              source.categories.contains(accepted) ||
              source.category == accepted;
          if (matched && source.id != target.id) {
            adjacency.putIfAbsent(source.id, () => {}).add(target.id);
          }
        }
      }
    }

    // BFS
    final visited = <String>{sourceId};
    final queue = <String>[sourceId];
    final direct = <FormatNode>[];
    final multiHop = <FormatNode>[];

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      final neighbors = adjacency[current] ?? {};

      for (final neighbor in neighbors) {
        if (!visited.contains(neighbor)) {
          visited.add(neighbor);
          final node = _registry.getFormatById(neighbor);
          if (node != null) {
            if (current == sourceId) {
              direct.add(node);
            } else {
              multiHop.add(node);
            }
          }
          queue.add(neighbor);
        }
      }
    }

    return RouteResult(direct: direct, multiHop: multiHop);
  }
}
