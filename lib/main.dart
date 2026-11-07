import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'features/home/home_page.dart';
import 'features/home/home_provider.dart';
import 'features/settings/settings_provider.dart';

void main() {
  runApp(const ProviderScope(child: OmniForgeApp()));
}

class OmniForgeApp extends ConsumerStatefulWidget {
  const OmniForgeApp({super.key});

  @override
  ConsumerState<OmniForgeApp> createState() => _OmniForgeAppState();
}

class _OmniForgeAppState extends ConsumerState<OmniForgeApp> {
  StreamSubscription? _intentSub;

  /// 设备是否支持动态取色（Android 12 / API 31 及以上）
  bool _dynamicSupported = false;

  @override
  void initState() {
    super.initState();
    _checkAndroidVersion();
    _initIncomingFiles();
  }

  /// 读取安卓版本号，判断能不能用 Material You 动态取色
  Future<void> _checkAndroidVersion() async {
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      if (!mounted) return;
      setState(() => _dynamicSupported = info.version.sdkInt >= 31);
    } catch (_) {
      // 非 Android 平台（iOS / 桌面 / 鸿蒙）直接视为不支持
      if (mounted) setState(() => _dynamicSupported = false);
    }
  }

  /// 接收其他应用分享/打开过来的文件
  void _initIncomingFiles() {
    _loadInitialFiles();
    try {
      // 前台运行时收到新的分享
      _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen(
        (files) {
          for (final f in files) {
            ref.read(homeProvider.notifier).addExternalFile(f.path);
          }
        },
        onError: (_) {},
      );
    } catch (_) {
      // 不支持该能力的平台直接跳过
    }
  }

  /// 冷启动：应用是被分享行为拉起来的
  Future<void> _loadInitialFiles() async {
    try {
      final files = await ReceiveSharingIntent.instance.getInitialMedia();
      if (files.isEmpty || !mounted) return;
      for (final f in files) {
        ref.read(homeProvider.notifier).addExternalFile(f.path);
      }
      ReceiveSharingIntent.instance.reset();
    } catch (_) {
      // 测试环境 / 非 Android-iOS 平台无原生实现，忽略
    }
  }

  @override
  void dispose() {
    _intentSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        // 三重条件：用户开启开关 + 设备是 Android 12+ + 系统真的给了壁纸色
        final useDynamic =
            settings.dynamicColor && _dynamicSupported && lightDynamic != null;

        final ColorScheme lightScheme;
        final ColorScheme darkScheme;

        if (useDynamic) {
          // 这里 lightDynamic 一定非空（上面判断过），用 ! 显式断言
          lightScheme = lightDynamic!.harmonized();
          darkScheme = (darkDynamic ?? lightDynamic!).harmonized();
        } else {
          lightScheme = ColorScheme.fromSeed(seedColor: settings.seedColor);
          darkScheme = ColorScheme.fromSeed(
            seedColor: settings.seedColor,
            brightness: Brightness.dark,
          );
        }

        return MaterialApp(
          title: 'OmniForge',
          theme: ThemeData(colorScheme: lightScheme, useMaterial3: true),
          darkTheme: ThemeData(colorScheme: darkScheme, useMaterial3: true),
          themeMode: settings.themeMode,
          home: const HomePage(),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}
