import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../registry/registry_manager.dart';
import 'conversion_planner.dart';
import 'conversion_service.dart';
import 'engine_registry.dart';
import 'ffmpeg_backend_factory.dart';
import 'plugin/native_plugin_registry.dart';

/// 插件安装根目录（应用可写数据目录，由 main.dart 用 path_provider 注入）。
///
/// 未注入时退回系统临时目录，保证 provider 永远可用；此时插件状态为
/// 「未安装」，不影响任何纯 Dart 引擎。
final pluginInstallDirProvider = Provider<Directory>((ref) {
  return Directory.systemTemp;
});

/// 原生插件注册表：管理插件清单、安装状态与动态库路径。
final nativePluginRegistryProvider = Provider<NativePluginRegistry>((ref) {
  return NativePluginRegistry(installDir: ref.watch(pluginInstallDirProvider));
});

/// 引擎注册表（应用层单例）。
///
/// - 音视频引擎走平台原生库：桌面 / 移动端由 ffmpeg_kit_flutter_new 提供的
///   原生 FFmpeg 库驱动，鸿蒙由 `@ohos/ffmpeg-kit` 的 NAPI 插件驱动，
///   全程不启动命令行进程；
/// - 模型类能力（OCR / ASR / TTS / WOFF2 / PDF 渲染 / 扩展压缩包）
///   由用户导入的原生插件提供，未安装时对应引擎返回 PluginRequired。
final engineRegistryProvider = Provider<EngineRegistry>((ref) {
  return EngineRegistry.platformDefaults(
    ffmpegBackend: createPlatformFfmpegBackend(),
    plugins: ref.watch(nativePluginRegistryProvider),
  );
});

/// 转换规划器：BFS 计算直转 / 多跳链路。
final conversionPlannerProvider = Provider<ConversionPlanner>((ref) {
  final registry = ref.watch(engineRegistryProvider);
  final manager = RegistryManager();
  return ConversionPlanner.fromData(
    formats: manager.getAllFormats(),
    flows: manager.getAllFlows(),
    readyEngines: registry.readyEngineIds,
    knownEngines: registry.all.map((engine) => engine.id).toSet(),
  );
});

/// 转换执行服务。
final conversionServiceProvider = Provider<ConversionService>((ref) {
  return ConversionService(ref.watch(engineRegistryProvider));
});
