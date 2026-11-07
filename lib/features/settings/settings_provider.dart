import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 文件名过长时的展示方式
enum FileNameDisplay { marquee, multiline }

/// 桌面图标样式
enum AppIcon { classic, newOne }

class SettingsState {
  final ThemeMode themeMode;
  final bool dynamicColor;
  final Color seedColor;
  final FileNameDisplay fileNameDisplay;
  final AppIcon appIcon;

  const SettingsState({
    this.themeMode = ThemeMode.system,
    this.dynamicColor = true,
    this.seedColor = Colors.teal,
    this.fileNameDisplay = FileNameDisplay.marquee,
    this.appIcon = AppIcon.classic,
  });

  SettingsState copyWith({
    ThemeMode? themeMode,
    bool? dynamicColor,
    Color? seedColor,
    FileNameDisplay? fileNameDisplay,
    AppIcon? appIcon,
  }) {
    return SettingsState(
      themeMode: themeMode ?? this.themeMode,
      dynamicColor: dynamicColor ?? this.dynamicColor,
      seedColor: seedColor ?? this.seedColor,
      fileNameDisplay: fileNameDisplay ?? this.fileNameDisplay,
      appIcon: appIcon ?? this.appIcon,
    );
  }
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  SettingsNotifier() : super(const SettingsState());

  void setThemeMode(ThemeMode mode) => state = state.copyWith(themeMode: mode);

  void setDynamicColor(bool value) => state = state.copyWith(dynamicColor: value);

  void setSeedColor(Color color) => state = state.copyWith(seedColor: color);

  void setFileNameDisplay(FileNameDisplay v) =>
      state = state.copyWith(fileNameDisplay: v);

  void setAppIcon(AppIcon v) => state = state.copyWith(appIcon: v);
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  return SettingsNotifier();
});

/// 预设色块（对应设置页参考图的 6 个颜色）
const presetColors = [
  Color(0xFF1565C0), // 蓝
  Color(0xFF3F51B5), // 靛蓝
  Color(0xFF6A1B9A), // 紫
  Color(0xFFC2185B), // 玫红
  Color(0xFFC62828), // 红
  Color(0xFFE65100), // 橙
];
