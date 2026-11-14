import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'conversion_planner.dart';
import 'engine_registry.dart';
import 'i_engine.dart';

/// 转换执行服务：按 [ConversionPlan] 串联执行多个引擎。
///
/// - 单步转换直接把引擎输出写到目标路径；
/// - 多步转换在系统临时目录里生成中间文件，全部完成后清理；
/// - 进度按步骤加权汇总成 0..1；
/// - 需要插件时原样向上传递 [PluginRequired]。
class ConversionService {
  final EngineRegistry registry;

  const ConversionService(this.registry);

  /// 执行方案。[inputPath] 为源文件，[outputPath] 为最终输出。
  Stream<EngineProgress> convert({
    required ConversionPlan plan,
    required String inputPath,
    required String outputPath,
    String sourceFormat = '',
    CancelToken? cancelToken,
  }) async* {
    final steps = plan.steps;
    if (steps.isEmpty) {
      yield const Error('没有可用的转换方案');
      return;
    }

    if (!plan.available) {
      final engineId = plan.blockedPluginId ?? (steps.first.engineId);
      final info = registry.pluginInfoOf(engineId);
      if (info != null) {
        yield PluginRequired(info.id, info.sizeMb);
      } else {
        yield Error('缺少转换引擎：$engineId');
      }
      return;
    }

    final token = cancelToken ?? CancelToken();
    Directory? tempRoot;
    try {
      tempRoot = await Directory.systemTemp.createTemp('omniforge_');
      var currentInput = inputPath;
      final total = steps.length;

      for (var i = 0; i < total; i++) {
        if (token.isCancelled) {
          yield const Error('已取消');
          return;
        }
        final step = steps[i];
        final isLast = i == total - 1;
        final engine = registry[step.engineId];
        if (engine == null) {
          yield Error('缺少转换引擎：${step.engineId}');
          return;
        }

        final extension = step.toExtension.isEmpty
            ? 'bin'
            : step.toExtension;
        final stepOutput = isLast
            ? outputPath
            : p.join(tempRoot.path, 'step_${i + 1}.$extension');

        final context = EngineContext(
          inputPath: currentInput,
          outputPath: stepOutput,
          targetFormat: step.toFormat,
          sourceFormat: step.fromFormat,
          params: step.params,
          cancelToken: token,
        );

        var finished = false;
        var interrupted = false;
        try {
          await for (final progress in engine.convert(context)) {
            if (progress is Progress) {
              final overall = ((i + progress.percent.clamp(0.0, 1.0)) / total)
                  .clamp(0.0, 1.0);
              yield Progress(overall, progress.message);
            } else if (progress is Success) {
              finished = true;
            } else if (progress is PluginRequired) {
              yield progress;
              interrupted = true;
            } else if (progress is Error) {
              yield progress;
              interrupted = true;
            }
          }
        } on PluginRequiredException catch (e) {
          yield PluginRequired(e.pluginId, e.sizeMb);
          return;
        } catch (error) {
          yield Error('转换失败：$error');
          return;
        }

        if (interrupted) return;
        if (!finished) {
          yield Error('步骤 ${i + 1} 未能完成');
          return;
        }
        if (!await File(stepOutput).exists()) {
          yield Error('步骤 ${i + 1} 未生成输出文件');
          return;
        }
        currentInput = stepOutput;
      }

      if (!await File(outputPath).exists()) {
        yield Error('转换完成但未找到输出文件');
        return;
      }
      yield Success(outputPath);
    } finally {
      if (tempRoot != null) {
        try {
          await tempRoot.delete(recursive: true);
        } catch (_) {
          // 临时目录清理失败不影响转换结果
        }
      }
    }
  }
}

// 让转换服务可以直接抛出插件需求异常时使用。
class PluginRequiredException implements Exception {
  final String pluginId;
  final int sizeMb;

  const PluginRequiredException(this.pluginId, this.sizeMb);
}
