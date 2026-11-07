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

  /// 设备是否支持动态取色（Android 12 / API 31 及以上），仅用于设置页提示
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

  /// 接收其他应用分享/打开过来的文件：只登记路径，由 HomePage 打开转换配置页
  void _initIncomingFiles() {
    _loadInitialFiles();
    try {
      // 前台运行时收到新的分享
      _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen(
        (files) {
          for (final f in files) {
            ref.read(incomingFileProvider.notifier).state = f.path;
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
        ref.read(incomingFileProvider.notifier).state = f.path;
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
        // 回写系统是否真的给了壁纸配色，供设置页提示
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(wallpaperColorAvailableProvider.notifier).state =
              lightDynamic != null;
        });

        // 是否真正拿到壁纸配色，以插件返回值为准（插件内部已判断系统版本）
        final useDynamic = settings.dynamicColor && lightDynamic != null;

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
