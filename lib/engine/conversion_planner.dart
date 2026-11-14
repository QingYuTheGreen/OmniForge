import '../models/format_node.dart';

/// 转换链路中的一个步骤。
class ConversionStep {
  final String engineId;
  final String fromFormat;
  final String toFormat;

  /// 目标格式首选扩展名（不含点；复合扩展名如 `tar.gz` 原样保留）。
  final String toExtension;
  final Map<String, dynamic> params;

  const ConversionStep({
    required this.engineId,
    required this.fromFormat,
    required this.toFormat,
    this.toExtension = '',
    this.params = const {},
  });

  ConversionStep withParams(Map<String, dynamic> extra) => ConversionStep(
        engineId: engineId,
        fromFormat: fromFormat,
        toFormat: toFormat,
        toExtension: toExtension,
        params: {...params, ...extra},
      );

  @override
  String toString() => '$fromFormat --[$engineId]--> $toFormat';
}

/// 一条完整的转换方案。
class ConversionPlan {
  final String sourceFormat;
  final String targetFormat;
  final List<ConversionStep> steps;

  /// 所有步骤引擎都可用时为 true。
  final bool available;

  /// 不可用时，第一个缺失插件 id（引擎尚未注册时为 null）。
  final String? blockedPluginId;

  const ConversionPlan({
    required this.sourceFormat,
    required this.targetFormat,
    required this.steps,
    this.available = true,
    this.blockedPluginId,
  });

  bool get isEmpty => steps.isEmpty;

  bool get isDirect => steps.length == 1;

  /// 每一步的引擎 id。
  List<String> get engineIds => steps.map((s) => s.engineId).toList();

  /// 链路说明，例如 `mp4 → mp3` 或 `dds → png → jpg`。
  String get describe {
    if (steps.isEmpty) return '$sourceFormat → $targetFormat';
    final buffer = StringBuffer(sourceFormat);
    for (final step in steps) {
      buffer.write(' --[${step.engineId}]--> ${step.toFormat}');
    }
    return buffer.toString();
  }
}

/// 从某个输入格式出发可到达的目标。
class ReachableTarget {
  final String formatId;
  final String engineId;
  final int hops;
  final bool available;
  final String? blockedPluginId;

  const ReachableTarget({
    required this.formatId,
    required this.engineId,
    required this.hops,
    required this.available,
    this.blockedPluginId,
  });

  bool get isDirect => hops == 1;
}

class _Edge {
  final String from;
  final String to;
  final String engineId;
  final List<ParamDef> params;
  final bool explicit;

  const _Edge({
    required this.from,
    required this.to,
    required this.engineId,
    this.params = const [],
    this.explicit = false,
  });
}

class _Path {
  final List<_Edge> edges;
  final int unavailableCount;

  const _Path(this.edges, this.unavailableCount);

  int get hops => edges.length;

  /// 排序权值：先保证「无需插件」，再保证步数最少。
  int get cost => unavailableCount * 100 + hops;
}

/// 转换规划器：在「格式 × 引擎」图上用 BFS/最短路找转换方案。
///
/// 边有两个来源：
/// 1. `formats.yaml` 里显式声明的 `flows`（带参数，优先）；
/// 2. 每个格式的 `accepts_from` + `engines`（隐式边，覆盖同引擎跨类转换）。
///
/// 纯 Dart 实现，不依赖 Flutter，方便单测。
class ConversionPlanner {
  final List<FormatNode> formats;
  final List<FlowRule> flows;

  /// 当前平台可直接运行的引擎 id。
  final Set<String> readyEngines;

  /// 注册表中存在的全部引擎 id（含需要插件的）。
  final Set<String> knownEngines;

  final Map<String, FormatNode> _formatById = {};
  final Map<String, List<_Edge>> _adjacency = {};
  bool _built = false;

  /// 最大链路长度，避免离谱的多跳转换。
  static const int maxHops = 3;

  ConversionPlanner({
    required this.formats,
    required this.flows,
    required this.readyEngines,
    required this.knownEngines,
  });

  /// 根据注册表数据构建规划器（供 UI / 服务层调用）。
  factory ConversionPlanner.fromData({
    required List<FormatNode> formats,
    required List<FlowRule> flows,
    required Set<String> readyEngines,
    required Set<String> knownEngines,
  }) {
    return ConversionPlanner(
      formats: formats,
      flows: flows,
      readyEngines: readyEngines,
      knownEngines: knownEngines,
    );
  }

  FormatNode? formatById(String id) => _formatById[id];

  void _ensureBuilt() {
    if (_built) return;
    _built = true;
    for (final format in formats) {
      _formatById[format.id] = format;
      _adjacency[format.id] = <_Edge>[];
    }

    // ── 1. 显式 flows：带 engine 与 params，最可靠 ──
    for (final flow in flows) {
      if (flow.engine.isEmpty || !knownEngines.contains(flow.engine)) continue;
      for (final source in flow.source) {
        for (final target in flow.target) {
          if (source == target) continue;
          if (!_formatById.containsKey(source)) continue;
          if (!_formatById.containsKey(target)) continue;
          _addEdge(_Edge(
            from: source,
            to: target,
            engineId: flow.engine,
            params: flow.params,
            explicit: true,
          ));
        }
      }
    }

    // ── 2. 隐式边：目标格式声明 accepts_from + engines ──
    for (final target in formats) {
      // 只有标为 ready 的目标才自动建边；plugin/planned 只通过显式 flows 暴露
      if (target.status != 'ready') continue;
      if (target.engines.isEmpty) continue;
      final candidates = target.engines
          .where(knownEngines.contains)
          .toList(growable: false);
      for (final source in _sourcesFor(target)) {
        if (source.id == target.id) continue;
        // 与源格式共享引擎的排在前面：docx→txt 优先复用 document 引擎，
        // 而不是从零开始用 text 引擎硬读二进制文档。
        final ordered = candidates.toList()
          ..sort((a, b) {
            final aShared = source.engines.contains(a) ? 0 : 1;
            final bShared = source.engines.contains(b) ? 0 : 1;
            if (aShared != bShared) return aShared - bShared;
            return 0;
          });
        for (final engineId in ordered) {
          _addEdge(_Edge(
            from: source.id,
            to: target.id,
            engineId: engineId,
            params: target.params,
          ));
        }
      }
    }
  }

  Iterable<FormatNode> _sourcesFor(FormatNode target) sync* {
    if (target.acceptsFrom.isEmpty) return;
    for (final token in target.acceptsFrom) {
      if (token == '*') {
        yield* formats;
        continue;
      }
      for (final format in formats) {
        if (format.id == token || format.categories.contains(token)) {
          yield format;
        }
      }
    }
  }

  void _addEdge(_Edge edge) {
    final list = _adjacency[edge.from];
    if (list == null) return;
    for (var i = 0; i < list.length; i++) {
      final existing = list[i];
      if (existing.to == edge.to && existing.engineId == edge.engineId) {
        // 显式 flows 覆盖隐式边
        if (edge.explicit && !existing.explicit) list[i] = edge;
        return;
      }
    }
    list.add(edge);
  }

  /// 最短/最优路径搜索。
  _Path? _findPath(String sourceId, String targetId) {
    _ensureBuilt();
    if (!_formatById.containsKey(sourceId) || !_formatById.containsKey(targetId)) {
      return null;
    }
    if (sourceId == targetId) return const _Path(<_Edge>[], 0);

    final best = <String, _Path>{sourceId: const _Path(<_Edge>[], 0)};
    final queue = <String>[sourceId];

    // 简单的逐层扩展（边数 ≤ 3，规模很小，无需优先队列）
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      final currentPath = best[current]!;
      if (currentPath.hops >= maxHops) continue;
      for (final edge in _adjacency[current] ?? const <_Edge>[]) {
        final unavailable = currentPath.unavailableCount +
            (readyEngines.contains(edge.engineId) ? 0 : 1);
        final candidate = _Path(
          [...currentPath.edges, edge],
          unavailable,
        );
        final existing = best[edge.to];
        if (existing == null || candidate.cost < existing.cost) {
          best[edge.to] = candidate;
          queue.add(edge.to);
        }
      }
    }

    return best[targetId];
  }

  /// 从 [sourceId] 出发所有可达目标（按「直转优先、可用的优先」排序）。
  List<ReachableTarget> reachableFrom(String sourceId) {
    _ensureBuilt();
    final result = <ReachableTarget>[];
    final best = <String, _Path>{};
    final queue = <String>[sourceId];
    best[sourceId] = const _Path(<_Edge>[], 0);

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      final currentPath = best[current]!;
      if (currentPath.hops >= maxHops) continue;
      for (final edge in _adjacency[current] ?? const <_Edge>[]) {
        final unavailable = currentPath.unavailableCount +
            (readyEngines.contains(edge.engineId) ? 0 : 1);
        final candidate = _Path([...currentPath.edges, edge], unavailable);
        final existing = best[edge.to];
        if (existing == null || candidate.cost < existing.cost) {
          best[edge.to] = candidate;
          queue.add(edge.to);
        }
      }
    }

    for (final entry in best.entries) {
      if (entry.key == sourceId) continue;
      final path = entry.value;
      if (path.edges.isEmpty) continue;
      final blocker = path.unavailableCount == 0
          ? null
          : path.edges
              .map((e) => e.engineId)
              .firstWhere((e) => !readyEngines.contains(e));
      result.add(ReachableTarget(
        formatId: entry.key,
        engineId: path.edges.last.engineId,
        hops: path.hops,
        available: path.unavailableCount == 0,
        blockedPluginId: blocker,
      ));
    }

    result.sort((a, b) {
      if (a.isDirect != b.isDirect) return a.isDirect ? -1 : 1;
      if (a.available != b.available) return a.available ? -1 : 1;
      if (a.hops != b.hops) return a.hops.compareTo(b.hops);
      return a.formatId.compareTo(b.formatId);
    });
    return result;
  }

  /// 把 ParamDef 列表转成默认参数表。
  Map<String, dynamic> _defaults(List<ParamDef> defs) {
    final result = <String, dynamic>{};
    for (final def in defs) {
      if (def.defaultValue != null) result[def.key] = def.defaultValue;
    }
    return result;
  }

  /// 生成从 [sourceId] 到 [targetId] 的转换方案；不可达返回 null。
  ConversionPlan? plan(
    String sourceId,
    String targetId, {
    Map<String, dynamic> params = const {},
  }) {
    final path = _findPath(sourceId, targetId);
    if (path == null || path.edges.isEmpty) return null;

    final steps = path.edges.map((edge) {
      final target = _formatById[edge.to];
      final rawExt = target != null && target.extensions.isNotEmpty
          ? target.extensions.first
          : '';
      return ConversionStep(
        engineId: edge.engineId,
        fromFormat: edge.from,
        toFormat: edge.to,
        toExtension: rawExt.replaceFirst(RegExp(r'^\.'), ''),
        params: {..._defaults(edge.params), ...params},
      );
    }).toList();

    final blocked = <String>[
      for (final step in steps)
        if (!readyEngines.contains(step.engineId)) step.engineId,
    ];

    return ConversionPlan(
      sourceFormat: sourceId,
      targetFormat: targetId,
      steps: steps,
      available: blocked.isEmpty,
      blockedPluginId: blocked.isEmpty ? null : blocked.first,
    );
  }
}
