import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:path_provider/path_provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'features/home/home_page.dart';
import 'features/home/home_provider.dart';
import 'features/settings/settings_provider.dart';
import 'engine/engine_providers.dart';
import 'registry/registry_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 先把 assets/formats.yaml 全量读进注册中心，UI 的类型/格式级联全部来自这里
  await RegistryManager().initialize();
  // 插件安装根目录：应用可写数据目录（Android / iOS / 桌面均可用）
  Directory pluginDir;
  try {
    pluginDir = await getApplicationSupportDirectory();
  } catch (_) {
    pluginDir = Directory.systemTemp;
  }
  runApp(
    ProviderScope(
      overrides: [pluginInstallDirProvider.overrideWithValue(pluginDir)],
      child: const OmniForgeApp(),
    ),
  );
}

class OmniForgeApp extends ConsumerStatefulWidget {
  const OmniForgeApp({super.key});

  @override
  ConsumerState<OmniForgeApp> createState() => _OmniForgeAppState();
}

class _OmniForgeAppState extends ConsumerState<OmniForgeApp> {
  StreamSubscription? _intentSub;

  @override
  void initState() {
    super.initState();
    _initIncomingFiles();
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
          // 这里 lightDynamic 一定非空（上面判断过）
          final light = lightDynamic;
          lightScheme = light.harmonized();
          darkScheme = (darkDynamic ?? light).harmonized();
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
