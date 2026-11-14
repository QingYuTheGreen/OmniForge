import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../registry/registry_manager.dart';
import 'conversion_planner.dart';
import 'conversion_service.dart';
import 'engine_registry.dart';
import 'ffmpeg_kit_backend.dart';

/// 引擎注册表（应用层单例）。
///
/// 音视频引擎注入 `FfmpegKitBackend`：由 ffmpeg_kit_flutter_new 随包内置的
/// 原生库（so / dll / dylib）驱动，不启动任何命令行进程。
final engineRegistryProvider = Provider<EngineRegistry>((ref) {
  return EngineRegistry.platformDefaults(ffmpegBackend: FfmpegKitBackend());
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
