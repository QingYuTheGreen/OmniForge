import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// 主题模式
enum ThemeMode { system, light, dark }

// 状态
class SettingsState {
  final ThemeMode themeMode;
  final bool dynamicColor;
  final Color seedColor;

  const SettingsState({
    this.themeMode = ThemeMode.system,
    this.dynamicColor = true,
    this.seedColor = Colors.teal,
  });

  SettingsState copyWith({
    ThemeMode? themeMode,
    bool? dynamicColor,
    Color? seedColor,
  }) {
    return SettingsState(
      themeMode: themeMode ?? this.themeMode,
      dynamicColor: dynamicColor ?? this.dynamicColor,
      seedColor: seedColor ?? this.seedColor,
    );
  }
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  SettingsNotifier() : super(const SettingsState());

  void setThemeMode(ThemeMode mode) => state = state.copyWith(themeMode: mode);

  void setDynamicColor(bool value) => state = state.copyWith(dynamicColor: value);

  void setSeedColor(Color color) => state = state.copyWith(seedColor: color);
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  return SettingsNotifier();
});

// MD3 预设色块
const presetColors = [
  Color(0xFF009688), // 青绿
  Color(0xFF6750A4), // 紫色
  Color(0xFFE65100), // 橙色
  Color(0xFF1976D2), // 蓝色
  Color(0xFFC62828), // 红色
  Color(0xFF2E7D32), // 绿色
];
