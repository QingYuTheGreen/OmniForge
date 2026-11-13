import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../utils/file_type_detector.dart';
import 'home_provider.dart';

class ConfigPage extends ConsumerStatefulWidget {
  final String initialFilePath;

  const ConfigPage({super.key, required this.initialFilePath});

  @override
  ConsumerState<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends ConsumerState<ConfigPage> {
  FormatOption? _inputType;
  FormatOption? _inputFormat;
  FormatOption? _outputType;
  FormatOption? _outputFormat;

  bool _showAdvanced = false;
  double _fps = 15;
  bool _loop = true;

  @override
  void initState() {
    super.initState();
    _autoDetect();
  }

  /// 自动识别输入类型和输入格式（文件头魔数 + 扩展名），进页面直接预填
  Future<void> _autoDetect() async {
    final detected = await FileTypeDetector.detect(widget.initialFilePath);
    if (!detected.isKnown || !mounted) return;

    final catalog = ref.read(formatCatalogProvider);

    // 类型：detected.typeKey 就是 formats.yaml 里的分类键
    final type = catalog.typeOf(detected.typeKey) ??
        FormatOption(label: detected.typeLabel, value: detected.typeKey);

    // 格式：在该类型下按扩展名别名匹配（tif→tiff、jpeg→jpg 都能命中）
    final format = catalog.formatByExt(detected.typeKey, detected.formatExt) ??
        FormatOption(
          label: detected.formatLabel,
          value: detected.formatExt,
          ext: detected.formatExt,
        );

    setState(() {
      _inputType = type;
      _inputFormat = format;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final notifier = ref.read(homeProvider.notifier);
    final catalog = ref.watch(formatCatalogProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('转换配置'),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: () {
              if (_outputFormat == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('请先选择输出类型和输出格式')),
                );
                return;
              }
              notifier.startConvert(
                widget.initialFilePath,
                outputExt: _outputFormat!.ext,
              );
              Navigator.pop(context);
            },
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
              }),
            ),
          ),
          _row(
            label: '输出格式',
            value: _outputFormat?.label,
            enabled: _outputType != null,
            hint: _outputType == null ? '请先选择输出类型' : null,
            onTap: () {
              final list = catalog.formatsOf(_outputType!.value);
              _pick(
                title: '选择输出格式',
                options: list,
                onSelect: (o) => setState(() => _outputFormat = o),
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
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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

  Widget _advanced() {
    final isGif = _outputFormat?.value == 'gif';

    return Column(
      children: [
        if (isGif) _gifCard(),
        if (!isGif)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('选择 GIF 输出后，这里会出现对应参数',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
          ),
      ],
    );
  }

  Widget _gifCard() {
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('GIF 设置', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [const Text('帧率 FPS'), Text('${_fps.toInt()}')],
            ),
            Slider(
              value: _fps,
              min: 1,
              max: 60,
              divisions: 59,
              onChanged: (v) => setState(() => _fps = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('循环播放'),
              value: _loop,
              onChanged: (v) => setState(() => _loop = v),
            ),
          ],
        ),
      ),
    );
  }

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
                    ? Text('${o.category}${o.note == null ? '' : ' · ${o.note}'}')
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
