import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'settings_provider.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('设置'), centerTitle: true),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('外观', style: TextStyle(color: Colors.grey, fontSize: 12)),
          ),

          // 主题模式
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: const Text('主题模式'),
            subtitle: Text(_themeModeLabel(state.themeMode)),
            onTap: () => _showThemePicker(context, notifier, state.themeMode),
          ),

          // 动态取色
          SwitchListTile(
            secondary: const Icon(Icons.wallpaper_outlined),
            title: const Text('动态取色'),
            subtitle: const Text('Android 12+ 使用壁纸颜色'),
            value: state.dynamicColor,
            onChanged: (v) => notifier.setDynamicColor(v),
          ),

          const Divider(),

          // 自定义主色
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('主色调', style: TextStyle(color: Colors.grey, fontSize: 12)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final color in presetColors)
                  _ColorCircle(
                    color: color,
                    selected: state.seedColor == color,
                    onTap: () => notifier.setSeedColor(color),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _themeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return '跟随系统';
      case ThemeMode.light:
        return '浅色';
      case ThemeMode.dark:
        return '深色';
    }
  }

  void _showThemePicker(BuildContext context, SettingsNotifier notifier, ThemeMode current) {
    showModalBottomSheet(
      context: context,
      builder: (context) => ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('选择主题模式', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          for (final mode in ThemeMode.values)
            ListTile(
              title: Text(_themeModeLabel(mode)),
              trailing: mode == current ? const Icon(Icons.check, color: Colors.teal) : null,
              onTap: () {
                notifier.setThemeMode(mode);
                Navigator.pop(context);
              },
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _ColorCircle extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ColorCircle({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: selected ? Border.all(color: Colors.black, width: 3) : null,
          boxShadow: selected
              ? [BoxShadow(color: color.withOpacity(0.4), blurRadius: 8, spreadRadius: 2)]
              : null,
        ),
        child: selected ? const Icon(Icons.check, color: Colors.white) : null,
      ),
    );
  }
}
