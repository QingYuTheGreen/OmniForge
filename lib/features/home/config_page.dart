import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/conversion_planner.dart';
import '../../engine/engine_providers.dart';
import '../../engine/engine_registry.dart';
import '../../models/format_node.dart';
import '../../registry/registry_manager.dart';
import '../../utils/file_type_detector.dart';
import 'home_provider.dart';

/// 转换配置页：根据「源格式 → 可达目标格式」的真实链路生成选项，
/// 并按目标格式的 ParamDef 动态渲染参数。
class ConfigPage extends ConsumerStatefulWidget {
  final String initialFilePath;

  const ConfigPage({super.key, required this.initialFilePath});

  @override
  ConsumerState<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends ConsumerState<ConfigPage> {
  String? _sourceId;
  String? _sourceLabel;
  FormatNode? _target;
  final Map<String, dynamic> _params = {};

  bool _detecting = true;

  @override
  void initState() {
    super.initState();
    _detect();
  }

  Future<void> _detect() async {
    final manager = RegistryManager();
    final detected = await FileTypeDetector.detect(widget.initialFilePath);
    FormatNode? source;
    if (detected.formatExt.isNotEmpty) {
      source = manager.getFormatByExtension(detected.formatExt);
    }
    if (source == null) {
      final dot = widget.initialFilePath.lastIndexOf('.');
      if (dot >= 0) {
        source = manager.getFormatByExtension(
          widget.initialFilePath.substring(dot + 1).toLowerCase(),
        );
      }
    }
    if (!mounted) return;
    setState(() {
      _sourceId = source?.id;
      _sourceLabel = source?.name ??
          (detected.formatLabel.isEmpty ? null : detected.formatLabel);
      _detecting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final manager = RegistryManager();
    final planner = ref.watch(conversionPlannerProvider);
    final catalog = ref.watch(formatCatalogProvider);

    final targets = _sourceId == null
        ? const <ReachableTarget>[]
        : planner.reachableFrom(_sourceId!);
    final available = targets.where((t) => t.available).toList();
    final blocked = targets.where((t) => !t.available).toList();

    // 目标格式按分类分组
    final byCategory = <String, List<ReachableTarget>>{};
    for (final target in targets) {
      final format = manager.getFormatById(target.formatId);
      final category = format == null || format.categories.isEmpty
          ? 'other'
          : format.categories.first;
      byCategory.putIfAbsent(category, () => []).add(target);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('转换配置'),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _target == null ? null : _start,
            child: const Text('开始转换', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _fileCard(cs),
          const SizedBox(height: 20),
          _infoRow(cs, '输入格式', _detecting ? '识别中…' : (_sourceLabel ?? '未识别')),
          const Divider(),
          if (_sourceId == null)
            _notice(cs, '无法识别该文件的格式，暂不支持转换')
          else ...[
            _sectionTitle('输出格式'),
            if (available.isEmpty)
              _notice(cs, '该格式暂时没有可用输出目标（部分目标需要插件）')
            else
              for (final entry in byCategory.entries)
                ..._categoryGroup(cs, manager, entry.key, entry.value),
            if (blocked.isNotEmpty) _blockedCard(cs, manager, blocked),
          ],
          const SizedBox(height: 16),
          if (_target != null) ...[
            const Divider(),
            _sectionTitle('转换参数'),
            _paramsCard(cs),
          ],
          const SizedBox(height: 24),
          Center(
            child: Text(
              '已接入 ${ref.watch(engineRegistryProvider).readyEngineIds.length} 个转换引擎 · '
              '${catalog.uniqueFormatCount} 种格式 · 全部离线运行',
              style: TextStyle(fontSize: 12, color: cs.outline),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _start() {
    final notifier = ref.read(homeProvider.notifier);
    notifier.startConvert(
      widget.initialFilePath,
      outputFormat: _target!.id,
      params: Map<String, dynamic>.from(_params),
    );
    Navigator.pop(context);
  }

  // ─────────────────────────── UI 片段 ───────────────────────────

  Widget _fileCard(ColorScheme cs) {
    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.insert_drive_file_outlined, color: cs.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.initialFilePath.split(Platform.pathSeparator).last,
                style: const TextStyle(fontWeight: FontWeight.bold),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(ColorScheme cs, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 16)),
          Text(value,
              style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Text(title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
    );
  }

  Widget _notice(ColorScheme cs, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: cs.outline),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 13, color: cs.outline)),
          ),
        ],
      ),
    );
  }

  List<Widget> _categoryGroup(
    ColorScheme cs,
    RegistryManager manager,
    String category,
    List<ReachableTarget> targets,
  ) {
    final categoryMeta = manager.getCategory(category);
    final label = categoryMeta?.name ?? category;
    return [
      Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Row(
          children: [
            Icon(categoryIcon(category), size: 16, color: cs.primary),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          ],
        ),
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final target in targets)
            if (target.available)
              _targetChip(cs, manager, target)
            else
              _targetChip(cs, manager, target, disabled: true),
        ],
      ),
    ];
  }

  Widget _targetChip(
    ColorScheme cs,
    RegistryManager manager,
    ReachableTarget target, {
    bool disabled = false,
  }) {
    final format = manager.getFormatById(target.formatId);
    final selected = _target?.id == target.formatId;
    final label = format?.name ?? target.formatId.toUpperCase();
    final suffix = target.isDirect ? '' : ' · ${target.hops} 步';
    final pluginNote = disabled
        ? '（需插件 ${target.blockedPluginId ?? '未知'}）'
        : suffix;
    return ChoiceChip(
      label: Text('$label$pluginNote'),
      selected: selected,
      onSelected: disabled
          ? null
          : (_) {
              setState(() {
                _target = format;
                _params.clear();
                for (final param in format?.params ?? const <ParamDef>[]) {
                  _params[param.key] = param.defaultValue;
                }
              });
            },
    );
  }

  Widget _blockedCard(
    ColorScheme cs,
    RegistryManager manager,
    List<ReachableTarget> blocked,
  ) {
    final names = blocked
        .map((t) => manager.getFormatById(t.formatId)?.name ?? t.formatId)
        .take(8)
        .join('、');
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        elevation: 0,
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.extension_outlined, size: 18, color: cs.outline),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '需要插件才能转换：$names'
                  '${blocked.length > 8 ? ' 等 ${blocked.length} 项' : ''}',
                  style: TextStyle(fontSize: 12, color: cs.outline),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _paramsCard(ColorScheme cs) {
    final params = _target?.params ?? const <ParamDef>[];
    if (params.isEmpty) {
      return _notice(cs, '该目标格式没有可调参数，直接开始转换即可');
    }
    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final param in params) ...[
              _paramTile(param),
              if (param != params.last) const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }

  Widget _paramTile(ParamDef param) {
    final value = _params[param.key] ?? param.defaultValue;
    switch (param.type) {
      case ParamType.slider:
        final min = (param.min ?? 0).toDouble();
        final max = (param.max ?? 100).toDouble();
        final step = (param.step ?? 1).toDouble();
        final current = (value is num ? value.toDouble() : min)
            .clamp(min, max);
        final divisions = step > 0 ? ((max - min) / step).round() : null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(param.label),
                Text(
                  current.toStringAsFixed(step < 1 ? 1 : 0),
                  style: TextStyle(color: Theme.of(context).colorScheme.primary),
                ),
              ],
            ),
            Slider(
              value: current,
              min: min,
              max: max,
              divisions: divisions != null && divisions > 0 ? divisions : null,
              onChanged: (v) => setState(() => _params[param.key] = v),
            ),
          ],
        );
      case ParamType.switch$:
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(param.label),
          value: value == true,
          onChanged: (v) => setState(() => _params[param.key] = v),
        );
      case ParamType.dropdown:
        final options = param.options;
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(param.label),
            DropdownButton<String>(
              value: value?.toString() ?? (options.isEmpty ? null : options.first),
              items: [
                for (final option in options)
                  DropdownMenuItem(value: option, child: Text(option)),
              ],
              onChanged: (v) => setState(() => _params[param.key] = v),
            ),
          ],
        );
      case ParamType.text:
        return TextFormField(
          initialValue: value?.toString() ?? '',
          decoration: InputDecoration(
            labelText: param.label,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          onChanged: (v) => _params[param.key] = v,
        );
    }
  }
}
