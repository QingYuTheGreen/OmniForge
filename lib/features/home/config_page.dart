import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  String? _mcSource;
  String? _mcTarget;
  double _fps = 15;
  bool _loop = true;

  @override
  void initState() {
    super.initState();
    _autoDetect();
  }

  /// 根据文件扩展名自动识别输入类型和输入格式
  void _autoDetect() {
    final path = widget.initialFilePath;
    final dot = path.lastIndexOf('.');
    if (dot < 0) return;
    final ext = path.substring(dot + 1).toLowerCase();

    for (final entry in inputFormatsByType.entries) {
      for (final f in entry.value) {
        final parts = f.label.replaceAll(' ', '').split('/');
        final match =
            parts.any((p) => p.replaceAll('.', '').toLowerCase() == ext) ||
                f.value == ext;
        if (match) {
          _inputType = inputTypeOptions.firstWhere(
            (o) => o.value == entry.key,
            orElse: () => FormatOption(label: entry.key, value: entry.key),
          );
          _inputFormat = f;
          return;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final notifier = ref.read(homeProvider.notifier);

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
                outputExt: _outputFormat!.value,
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
              options: inputTypeOptions,
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
              final list = inputFormatsByType[_inputType!.value] ?? const [];
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
              options: outputTypeOptions,
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
              final list = outputFormatsByType[_outputType!.value] ?? const [];
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
        ],
      ),
    );
  }

  Widget _advanced() {
    final isMc = _inputType?.value.startsWith('mc') == true ||
        _outputType?.value == 'mc';
    final isGif = _outputFormat?.value == 'gif';

    return Column(
      children: [
        if (isMc) _mcCard(),
        if (isGif) _gifCard(),
        if (!isMc && !isGif)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('选择「我的世界」或 GIF 输出后，这里会出现对应参数',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
          ),
      ],
    );
  }

  Widget _mcCard() {
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('我的世界互转', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _versionBox(
                      '源版本', _mcSource, (v) => setState(() => _mcSource = v)),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('→'),
                ),
                Expanded(
                  child: _versionBox(
                      '目标版本', _mcTarget, (v) => setState(() => _mcTarget = v)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _versionBox(String label, String? value, ValueChanged<String> onPick) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 6),
        InkWell(
          onTap: () => _pick(
            title: '选择$label',
            options:
                mcVersions.map((v) => FormatOption(label: v, value: v)).toList(),
            onSelect: (o) => onPick(o.value),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade400),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(value ?? '选择'),
                const Icon(Icons.arrow_drop_down, size: 20),
              ],
            ),
          ),
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
                subtitle: o.category != null ? Text(o.category!) : null,
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
