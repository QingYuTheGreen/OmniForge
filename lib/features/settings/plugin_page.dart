import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/engine_providers.dart';
import '../../engine/plugin/native_plugin_registry.dart';
import '../../engine/plugin/plugin_manifest.dart';

/// 转换插件管理页。
///
/// OmniForge 的主转换能力全部由纯 Dart 引擎完成；语音识别、OCR、
/// TTS、WOFF2、PDF 渲染等「需要模型 / 大型原生库」的能力通过
/// 原生插件（.so / .dll / .dylib）提供，插件完全离线运行。
///
/// 页面只做三件事：展示清单、导入库文件、卸载；安装状态变化后
/// 刷新 `nativePluginRegistryProvider`，转换规划器随之重新计算。
class PluginPage extends ConsumerStatefulWidget {
  const PluginPage({super.key});

  @override
  ConsumerState<PluginPage> createState() => _PluginPageState();
}

class _PluginPageState extends ConsumerState<PluginPage> {
  bool _busy = false;

  Future<void> _import(PluginManifest manifest) async {
    setState(() => _busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: '选择 ${manifest.name} 原生库',
        type: FileType.custom,
        allowedExtensions: _extensionsFor(manifest),
        withData: false,
      );
      final path = result?.files.single.path;
      if (path == null) return;
      final registry = ref.read(nativePluginRegistryProvider);
      await registry.install(manifest.id, File(path));
      ref.invalidate(nativePluginRegistryProvider);
      if (!mounted) return;
      _toast('已安装 ${manifest.name}');
    } on ArgumentError catch (error) {
      _toast('安装失败：${error.message}');
    } on FileSystemException catch (error) {
      _toast('安装失败：${error.message}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _uninstall(PluginManifest manifest) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('卸载插件'),
        content: Text('卸载「${manifest.name}」后，相关转换会提示需要插件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('卸载'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(nativePluginRegistryProvider).uninstall(manifest.id);
      ref.invalidate(nativePluginRegistryProvider);
      if (!mounted) return;
      _toast('已卸载 ${manifest.name}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  List<String> _extensionsFor(PluginManifest manifest) {
    final platform = Platform.operatingSystem;
    if (platform == 'windows') return const ['dll'];
    if (platform == 'macos' || platform == 'ios') return const ['dylib'];
    return const ['so'];
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final registry = ref.watch(nativePluginRegistryProvider);
    final manifests = registry.manifests;

    return Scaffold(
      appBar: AppBar(title: const Text('转换插件')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(
            '主转换能力（图片 / 音频 / 视频 / 文档 / 电子书 / 3D / 压缩包等）'
            '全部由内置纯 Dart 引擎与原生 FFmpeg 库完成，无需插件。\n'
            '下列插件用于需要模型或大型第三方库的能力，导入后完全离线运行。',
            style: TextStyle(fontSize: 13, height: 1.5, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Text(
            '插件 ABI：导出符号 omniforge_convert，'
            '参数 (inputPath, outputPath, paramsJson, errbuf, errlen)。',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          for (final manifest in manifests) ...[
            _PluginCard(
              manifest: manifest,
              state: registry.stateOf(manifest.id),
              platform: registry.platform,
              busy: _busy,
              onImport: () => _import(manifest),
              onUninstall: () => _uninstall(manifest),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _PluginCard extends StatelessWidget {
  const _PluginCard({
    required this.manifest,
    required this.state,
    required this.platform,
    required this.busy,
    required this.onImport,
    required this.onUninstall,
  });

  final PluginManifest manifest;
  final PluginInstallState state;
  final String platform;
  final bool busy;
  final VoidCallback onImport;
  final VoidCallback onUninstall;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final installed = state == PluginInstallState.installed;
    final incompatible = state == PluginInstallState.incompatible;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                installed ? Icons.verified_outlined : Icons.extension_outlined,
                color: installed ? Colors.green : cs.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${manifest.name}（${manifest.sizeMb} MB）',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              _stateChip(cs, installed, incompatible),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            manifest.description,
            style: TextStyle(fontSize: 13, height: 1.45, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Text(
            '支持平台：${manifest.platforms.join(' / ')}　当前：$platform',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          if (manifest.notes['backend'] != null) ...[
            const SizedBox(height: 4),
            Text(
              '后端：${manifest.notes['backend']}',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              FilledButton.tonal(
                onPressed: busy || incompatible ? null : onImport,
                child: Text(installed ? '重新导入' : '导入库文件'),
              ),
              const SizedBox(width: 10),
              if (installed)
                TextButton(
                  onPressed: busy ? null : onUninstall,
                  child: const Text('卸载'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stateChip(ColorScheme cs, bool installed, bool incompatible) {
    final label = installed
        ? '已安装'
        : incompatible
            ? '当前平台不支持'
            : '未安装';
    final color = installed
        ? Colors.green
        : incompatible
            ? cs.error
            : cs.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, color: color)),
    );
  }
}
