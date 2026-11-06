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
  String? _mcSourceVersion;
  String? _mcTargetVersion;
  bool _isMidi = false;
  double _fps = 15;
  bool _loopGif = true;

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(homeProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('转换配置'),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: () {
              notifier.startConvert(widget.initialFilePath);
              Navigator.pop(context);
            },
            child: const Text('完毕', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 文件名显示
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.insert_drive_file_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.initialFilePath.split('/').last,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ── 输入/输出选项区 ──
          _buildOptionRow(
            label: '输入类型',
            value: _inputType?.label,
            onTap: () => _showPicker(
              title: '选择输入类型',
              options: inputTypeOptions,
              onSelect: (opt) => setState(() => _inputType = opt),
            ),
          ),
          _buildOptionRow(
            label: '输入格式',
            value: _inputFormat?.label,
            onTap: () => _showPicker(
              title: '选择输入格式',
              options: inputFormatOptions,
              onSelect: (opt) => setState(() => _inputFormat = opt),
            ),
          ),
          _buildOptionRow(
            label: '输出类型',
            value: _outputType?.label,
            onTap: () => _showPicker(
              title: '选择输出类型',
              options: outputTypeOptions,
              onSelect: (opt) => setState(() => _outputType = opt),
            ),
          ),
          _buildOptionRow(
            label: '输出格式',
            value: _outputFormat?.label,
            onTap: () => _showPicker(
              title: '选择输出格式',
              options: outputFormatOptions,
              onSelect: (opt) => setState(() => _outputFormat = opt),
            ),
          ),

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),

          // ── 高级选项区 ──
          InkWell(
            onTap: () => setState(() => _showAdvanced = !_showAdvanced),
            child: Row(
              children: [
                Icon(_showAdvanced ? Icons.expand_less : Icons.expand_more),
                const SizedBox(width: 8),
                const Text('高级选项', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(height: 0),
            secondChild: _buildAdvancedContent(),
            crossFadeState: _showAdvanced ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  // 选项行
  Widget _buildOptionRow({
    required String label,
    required String? value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 16)),
            Row(
              children: [
                Text(
                  value ?? '请选择',
                  style: TextStyle(
                    fontSize: 16,
                    color: value == null ? Colors.grey : Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, color: Colors.grey),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 高级选项内容
  Widget _buildAdvancedContent() {
    // 判断当前场景
    final isMcConvert = _inputType?.value == 'mc_java' || _inputType?.value == 'mc_bedrock' ||
        _outputType?.value == 'mc';
    final isGifConvert = _outputFormat?.value == 'gif';
    final isMidiConvert = _outputFormat?.value == 'midi';

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        children: [
          // MC 互转
          if (isMcConvert) ...[
            _buildMcSection(),
            const SizedBox(height: 16),
          ],

          // GIF 转换
          if (isGifConvert) ...[
            _buildGifSection(),
            const SizedBox(height: 16),
          ],

          // MIDI 转换
          if (isMidiConvert) ...[
            _buildMidiSection(),
            const SizedBox(height: 16),
          ],

          // 默认提示
          if (!isMcConvert && !isGifConvert && !isMidiConvert)
            const Text(
              '选择特定转换类型后，这里会显示对应参数',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
        ],
      ),
    );
  }

  // MC 版本选择
  Widget _buildMcSection() {
    return Card(
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
                  child: _buildVersionDropdown(
                    label: '源版本',
                    value: _mcSourceVersion,
                    onTap: () => _showVersionPicker(
                      title: '选择源版本',
                      current: _mcSourceVersion,
                      onSelect: (v) => setState(() => _mcSourceVersion = v),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('→'),
                ),
                Expanded(
                  child: _buildVersionDropdown(
                    label: '目标版本',
                    value: _mcTargetVersion,
                    onTap: () => _showVersionPicker(
                      title: '选择目标版本',
                      current: _mcTargetVersion,
                      onSelect: (v) => setState(() => _mcTargetVersion = v),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVersionDropdown({
    required String label,
    required String? value,
    required VoidCallback onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
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

  // GIF 选项
  Widget _buildGifSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('GIF 设置', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('FPS'),
                Text('${_fps.toInt()}'),
              ],
            ),
            Slider(
              value: _fps,
              min: 1,
              max: 60,
              divisions: 59,
              onChanged: (v) => setState(() => _fps = v),
            ),
            SwitchListTile(
              title: const Text('循环播放'),
              value: _loopGif,
              onChanged: (v) => setState(() => _loopGif = v),
              dense: true,
            ),
          ],
        ),
      ),
    );
  }

  // MIDI 选项
  Widget _buildMidiSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('人声处理', style: TextStyle(fontWeight: FontWeight.bold)),
            RadioListTile<bool>(
              title: const Text('去人声'),
              value: true,
              groupValue: _isMidi,
              onChanged: (v) => setState(() => _isMidi = v!),
              dense: true,
            ),
            RadioListTile<bool>(
              title: const Text('带人声'),
              value: false,
              groupValue: _isMidi,
              onChanged: (v) => setState(() => _isMidi = v!),
              dense: true,
            ),
          ],
        ),
      ),
    );
  }

  // ── 界面 3：底部选择弹窗 ──
  void _showPicker({
    required String title,
    required List<FormatOption> options,
    required void Function(FormatOption) onSelect,
  }) {
    showModalBottomSheet(
      context: context,
      builder: (context) => ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          for (final opt in options)
            ListTile(
              title: Text(opt.label),
              subtitle: opt.category != null ? Text(opt.category!) : null,
              onTap: () {
                Navigator.pop(context);
                onSelect(opt);
              },
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _showVersionPicker({
    required String title,
    required String? current,
    required void Function(String) onSelect,
  }) {
    showModalBottomSheet(
      context: context,
      builder: (context) => ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          for (final v in mcVersions)
            ListTile(
              title: Text(v),
              trailing: v == current ? const Icon(Icons.check, color: Colors.teal) : null,
              onTap: () {
                Navigator.pop(context);
                onSelect(v);
              },
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
