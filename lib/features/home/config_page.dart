import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/conversion_planner.dart';
import '../../engine/engine_providers.dart';
import '../../models/format_node.dart';
import '../../registry/registry_manager.dart';
import '../../utils/file_type_detector.dart';
import 'home_provider.dart';

/// 转换配置页。
///
/// 保持 v0.6.0 的界面格式：文件卡片 + 四行选择项（输入类型 / 输入格式 /
/// 输出类型 / 输出格式）+「高级选项」展开区。
/// 区别只在于数据：输出类型与输出格式来自 BFS 规划器的真实可达链路，
/// 高级选项按目标格式的 ParamDef 动态渲染。
class ConfigPage extends ConsumerStatefulWidget {
  final String initialFilePath;

  const ConfigPage({super.key, required this.initialFilePath});

  @override
  ConsumerState<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends ConsumerState<ConfigPage> {
  // 输入侧（自动识别后预填，可手动改，仅用于展示）
  FormatOption? _inputType;
  FormatOption? _inputFormat;

  // 输出侧
  FormatOption? _outputType;
  FormatOption? _outputFormat;
  FormatNode? _target;

  // 源格式 id（规划器用）
  String? _sourceId;

  bool _showAdvanced = false;
  final Map<String, dynamic> _params = {};

  @override
  void initState() {
    super.initState();
    _autoDetect();
  }

  /// 自动识别输入类型和输入格式（文件头魔数 + 扩展名），进页面直接预填
  Future<void> _autoDetect() async {
    final detected = await FileTypeDetector.detect(widget.initialFilePath);
    if (!mounted) return;

    final catalog = ref.read(formatCatalogProvider);
    final manager = RegistryManager();

    // 源格式：先按扩展名 → 再按检测到的格式扩展名
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

    if (!detected.isKnown) {
      setState(() => _sourceId = source?.id);
      return;
    }

    final type = catalog.typeOf(detected.typeKey) ??
        FormatOption(label: detected.typeLabel, value: detected.typeKey);
    final format = catalog.formatByExt(detected.typeKey, detected.formatExt) ??
        FormatOption(
          label: detected.formatLabel,
          value: detected.formatExt,
          ext: detected.formatExt,
        );

    setState(() {
      _inputType = type;
      _inputFormat = format;
      _sourceId = source?.id;
    });
  }

  /// 当前源格式能到达的目标（含不可用的，用于展示插件提示）
  List<ReachableTarget> _targets() {
    final id = _sourceId;
    if (id == null) return const <ReachableTarget>[];
    return ref.watch(conversionPlannerProvider).reachableFrom(id);
  }

  ReachableTarget? _targetOf(String formatId) {
    for (final t in _targets()) {
      if (t.formatId == formatId) return t;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final catalog = ref.watch(formatCatalogProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('转换配置'),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _outputFormat == null ? null : _start,
            child: const Text('完毕', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
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
          ),
          const SizedBox(height: 24),

          _row(
            label: '输入类型',
            value: _inputType?.label,
            onTap: () => _pick(
              title: '选择输入类型',
              options: catalog.types,
              onSelect: (o) => setState(() {
                _inputType = o;
                // 类型变了，之前选的格式作废
                _inputFormat = null;
              }),
            ),
          ),
          _row(
            label: '输入格式',
            value: _inputFormat?.label,
            enabled: _inputType != null,
            hint: _inputType == null ? '请先选择输入类型' : null,
            onTap: () {
              final list = catalog.formatsOf(_inputType!.value);
              _pick(
                title: '选择输入格式',
                options: list,
                onSelect: (o) => setState(() => _inputFormat = o),
              );
            },
          ),
          _row(
            label: '输出类型',
            value: _outputType?.label,
            onTap: () => _pick(
              title: '选择输出类型',
              options: catalog.types,
              onSelect: (o) => setState(() {
                _outputType = o;
                _outputFormat = null;
                _target = null;
                _params.clear();
              }),
            ),
          ),
          _row(
            label: '输出格式',
            value: _outputFormat?.label,
            enabled: _outputType != null,
            hint: _outputType == null ? '请先选择输出类型' : null,
            onTap: () {
              if (_sourceId == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('无法识别该文件的格式，暂不支持转换')),
                );
                return;
              }
              final list = _outputOptions(_outputType!.value);
              _pick(
                title: '选择输出格式',
                options: list,
                onSelect: (o) {
                  final target = _targetOf(o.value) == null
                      ? null
                      : RegistryManager().getFormatById(o.value);
                  if (target == null) {
                    _snack('该目标格式需要安装插件后才能使用');
                    return;
                  }
                  setState(() {
                    _outputFormat = o;
                    _target = target;
                    _params.clear();
                    for (final param in target.params) {
                      _params[param.key] = param.defaultValue;
                    }
                  });
                },
              );
            },
          ),

          const SizedBox(height: 16),
          const Divider(),
          InkWell(
            onTap: () => setState(() => _showAdvanced = !_showAdvanced),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Icon(_showAdvanced ? Icons.expand_less : Icons.expand_more),
                  const SizedBox(width: 8),
                  const Text('高级选项',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
            ),
          ),
          if (_showAdvanced) _advanced(),
          if (catalog.shellStage) _shellNotice(catalog),
        ],
      ),
    );
  }

  /// 输出格式候选：只保留规划器判定可达的格式，按当前输出类型过滤。
  /// 需要插件的目标仍然展示，并在副标题注明，选中时提示安装插件。
  List<FormatOption> _outputOptions(String categoryKey) {
    final manager = RegistryManager();
    final result = <FormatOption>[];
    for (final target in _targets()) {
      final format = manager.getFormatById(target.formatId);
      if (format == null) continue;
      if (!format.categories.contains(categoryKey)) continue;

      final routeNote = target.available
          ? (target.isDirect ? '直接转换' : '${target.hops} 步转换')
          : '需要插件 ${target.blockedPluginId ?? '未知'}';

      result.add(FormatOption(
        label: format.name,
        value: format.id,
        ext: format.extensions.isEmpty ? '' : format.extensions.first,
        category: manager.getCategory(categoryKey)?.name,
        note: routeNote,
      ));
    }
    // 直接转换排前面，跳数少的优先
    result.sort((a, b) {
      final ta = _targetOf(a.value);
      final tb = _targetOf(b.value);
      final da = ta?.isDirect == true ? 0 : 1;
      final db = tb?.isDirect == true ? 0 : 1;
      if (da != db) return da - db;
      final ha = ta?.hops ?? 9;
      final hb = tb?.hops ?? 9;
      if (ha != hb) return ha - hb;
      return a.label.compareTo(b.label);
    });
    return result;
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

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// 空壳阶段提示：格式表已全量铺好，但转换引擎还没接
  Widget _shellNotice(FormatCatalog catalog) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Row(
        children: [
          Icon(Icons.construction_outlined, size: 16, color: cs.outline),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '空壳阶段：已登记 ${catalog.types.length} 类 / '
              '${catalog.uniqueFormatCount} 种格式，转换引擎尚未接入',
              style: TextStyle(fontSize: 12, color: cs.outline),
            ),
          ),
        ],
      ),
    );
  }

  // ── 高级选项：按目标格式的 ParamDef 动态渲染 ──

  Widget _advanced() {
    final params = _target?.params ?? const <ParamDef>[];

    if (_target == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Text('选择输出格式后，这里会出现对应参数',
            style: TextStyle(color: Colors.grey, fontSize: 13)),
      );
    }
    if (params.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text('该目标格式没有可调参数，直接点「完毕」即可',
            style: TextStyle(
                color: Theme.of(context).colorScheme.outline, fontSize: 13)),
      );
    }

    return Card(
      elevation: 0,
      color: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withValues(alpha: 0.35),
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
        final current =
            (value is num ? value.toDouble() : min).clamp(min, max).toDouble();
        final divisions = step > 0 ? ((max - min) / step).round() : 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(param.label),
                Text(
                  current.toStringAsFixed(step < 1 ? 1 : 0),
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.primary),
                ),
              ],
            ),
            Slider(
              value: current,
              min: min,
              max: max,
              divisions: divisions > 0 ? divisions : null,
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
        final current = value?.toString() ??
            (options.isEmpty ? null : options.first);
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(param.label),
            DropdownButton<String>(
              value: current,
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
          onChanged: (v) => setState(() => _params[param.key] = v),
        );
    }
  }

  // ── 通用行 / 底部弹窗选择器（保持 v0.6.0 的交互） ──

  Widget _row({
    required String label,
    required String? value,
    required VoidCallback onTap,
    bool enabled = true,
    String? hint,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 16)),
              Row(
                children: [
                  Text(
                    value ?? hint ?? '请选择',
                    style: TextStyle(
                      fontSize: 16,
                      color: value == null ? cs.onSurfaceVariant : cs.primary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right, color: cs.outline),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _pick({
    required String title,
    required List<FormatOption> options,
    required void Function(FormatOption) onSelect,
  }) {
    if (options.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('该类型下暂时没有可用格式')));
      return;
    }
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.72,
      ),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            for (final o in options)
              ListTile(
                title: Text(o.label),
                subtitle: o.category != null
                    ? Text(
                        '${o.category}${o.note == null ? '' : ' · ${o.note}'}')
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  onSelect(o);
                },
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
