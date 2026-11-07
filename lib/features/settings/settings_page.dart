import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:dynamic_app_icon_changer/dynamic_app_icon_changer.dart';
import '../../utils/output_paths.dart';
import 'settings_provider.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _checking = true;

  /// 安卓版本号（sdkInt），非安卓为 0
  int _sdkInt = 0;
  String _deviceLabel = '';
  bool _hasStorageAccess = true;

  /// 当前平台是否支持运行时切换桌面图标
  bool get _iconSwitchSupported =>
      Platform.isAndroid || Platform.isIOS;

  @override
  void initState() {
    super.initState();
    _loadPlatform();
    _syncCurrentIcon();
  }

  Future<void> _loadPlatform() async {
    if (!Platform.isAndroid) {
      if (mounted) setState(() => _checking = false);
      return;
    }
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      final granted = await Permission.manageExternalStorage.isGranted;
      if (!mounted) return;
      setState(() {
        _sdkInt = info.version.sdkInt;
        _deviceLabel = 'Android ${info.version.release}（API ${info.version.sdkInt}）'
            ' · ${info.brand} ${info.model}';
        _hasStorageAccess = granted;
        _checking = false;
      });
    } catch (_) {
      if (mounted) setState(() => _checking = false);
    }
  }

  /// 启动时读取系统当前生效的图标，回写到设置状态
  Future<void> _syncCurrentIcon() async {
    if (!_iconSwitchSupported) return;
    try {
      final name = await DynamicAppIconChanger.alternateIconName;
      final match = AppIcon.values.firstWhere(
        (i) => i.aliasName == name,
        orElse: () => AppIcon.defaultIcon,
      );
      ref.read(settingsProvider.notifier).setAppIcon(match);
    } catch (_) {
      // 不支持就保持默认
    }
  }

  bool get _dynamicSupported => Platform.isAndroid && _sdkInt >= 31;

  Future<void> _requestStorage() async {
    final status = await Permission.manageExternalStorage.request();
    if (!mounted) return;
    setState(() => _hasStorageAccess = status.isGranted);
    if (!status.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未获得存储权限，输出文件会存到应用私有目录')),
      );
    }
  }

  /// 选择桌面图标：先存偏好，再在支持的平台调用原生切换
  Future<void> _pickIcon(AppIcon icon) async {
    final notifier = ref.read(settingsProvider.notifier);
    notifier.setAppIcon(icon);

    if (!_iconSwitchSupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前平台不支持切换桌面图标，偏好已保存')),
      );
      return;
    }

    try {
      await DynamicAppIconChanger.setAlternateIconName(icon.aliasName);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('图标切换失败：$e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('主题与外观'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 外观模式 ──
          _title('外观模式'),
          _card(cs, [
            const Text('选择应用的明暗外观'),
            const SizedBox(height: 12),
            Row(
              children: [
                for (final mode in ThemeMode.values) ...[
                  Expanded(
                    child: _toggle(
                      cs,
                      label: _themeLabel(mode),
                      selected: state.themeMode == mode,
                      onTap: () => notifier.setThemeMode(mode),
                    ),
                  ),
                  if (mode != ThemeMode.values.last) const SizedBox(width: 10),
                ],
              ],
            ),
          ]),
          const SizedBox(height: 20),

          // ── 文件名显示 ──
          _title('文件名显示'),
          _card(cs, [
            const Text('文件名过长时的展示方式'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _toggle(
                    cs,
                    label: '跑马灯滚动',
                    selected: state.fileNameDisplay == FileNameDisplay.marquee,
                    onTap: () =>
                        notifier.setFileNameDisplay(FileNameDisplay.marquee),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _toggle(
                    cs,
                    label: '多行显示',
                    selected: state.fileNameDisplay == FileNameDisplay.multiline,
                    onTap: () =>
                        notifier.setFileNameDisplay(FileNameDisplay.multiline),
                  ),
                ),
              ],
            ),
          ]),
          const SizedBox(height: 20),

          // ── 主题色 ──
          _card(cs, [
            Row(
              children: [
                Icon(Icons.palette_outlined, color: cs.primary),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('主题色',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ),
                const Icon(Icons.expand_less),
              ],
            ),
            const Divider(height: 24),

            if (_checking)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(),
              )
            else if (_dynamicSupported) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('动态色彩'),
                subtitle: Text('从系统壁纸自动取色（$_deviceLabel）'),
                value: state.dynamicColor,
                onChanged: notifier.setDynamicColor,
              ),
              if (state.dynamicColor &&
                  !ref.watch(wallpaperColorAvailableProvider))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '系统当前没有提供壁纸配色。请在系统「设置 → 壁纸与个性化」里开启壁纸取色/主题色后重启本应用；部分 MIUI 版本不支持第三方应用取色。',
                    style: TextStyle(fontSize: 12, color: cs.error),
                  ),
                ),
            ]
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  Platform.isAndroid
                      ? '当前设备 $_deviceLabel，动态取色需要 Android 12（API 31）及以上'
                      : '动态取色仅支持 Android 12+，当前平台使用下方固定主题色',
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),
              ),

            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('主题颜色',
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final c in presetColors)
                  _dot(c, state.seedColor == c, () => notifier.setSeedColor(c)),
              ],
            ),
          ]),
          const SizedBox(height: 20),

          // ── 桌面图标（3 个真实预览） ──
          _card(cs, [
            Row(
              children: [
                Icon(Icons.star_outline, color: cs.primary),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('桌面图标',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ),
                const Icon(Icons.expand_less),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                for (final icon in AppIcon.values) ...[
                  Expanded(
                    child: _iconPreview(
                      cs,
                      icon: icon,
                      asset: _iconAsset(icon),
                      selected: state.appIcon == icon,
                      onTap: () => _pickIcon(icon),
                    ),
                  ),
                  if (icon != AppIcon.values.last) const SizedBox(width: 12),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _iconSwitchSupported
                  ? '点击即切换；部分启动器需几秒或重启桌面后刷新。'
                  : '当前平台不支持运行时切换，桌面仍显示默认图标。',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ]),
          const SizedBox(height: 20),

          // ── 输出目录 ──
          _card(cs, [
            Row(
              children: [
                Icon(Icons.folder_outlined, color: cs.primary),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('输出目录',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SelectableText(OutputPaths.description,
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
            if (Platform.isAndroid) ...[
              const SizedBox(height: 8),
              if (_hasStorageAccess)
                Row(children: [
                  const Icon(Icons.check_circle_outline,
                      size: 16, color: Colors.green),
                  const SizedBox(width: 6),
                  const Text('已获得存储权限', style: TextStyle(fontSize: 12)),
                ])
              else
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _requestStorage,
                    child: const Text('授予存储权限（否则只存应用私有目录）'),
                  ),
                ),
            ],
          ]),
        ],
      ),
    );
  }

  String _iconAsset(AppIcon icon) {
    switch (icon) {
      case AppIcon.defaultIcon:
        return 'assets/icons/icon_default.png';
      case AppIcon.anvil:
        return 'assets/icons/icon_anvil.png';
      case AppIcon.flame:
        return 'assets/icons/icon_flame.png';
    }
  }

  Widget _title(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary)),
      );

  Widget _card(ColorScheme cs, List<Widget> children) => Card(
        elevation: 0,
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      );

  Widget _toggle(ColorScheme cs,
      {required String label,
      required bool selected,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: selected
              ? cs.primaryContainer
              : cs.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Center(
          child: Text(label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? cs.onPrimaryContainer : cs.onSurface,
              )),
        ),
      ),
    );
  }

  Widget _dot(Color color, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: selected ? Border.all(color: Colors.white, width: 3) : null,
          boxShadow: selected
              ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6, spreadRadius: 1)]
              : null,
        ),
        child: selected
            ? const Icon(Icons.check, color: Colors.white, size: 20)
            : null,
      ),
    );
  }

  Widget _iconPreview(
    ColorScheme cs, {
    required AppIcon icon,
    required String asset,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? cs.primary : cs.outlineVariant,
                width: selected ? 3 : 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: Image.asset(asset, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 6),
          Text(icon.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              )),
        ],
      ),
    );
  }

  String _themeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return '跟随系统';
      case ThemeMode.light:
        return '浅色';
      case ThemeMode.dark:
        return '深色';
    }
  }
}
