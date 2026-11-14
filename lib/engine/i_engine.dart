/// 取消令牌：长任务（例如 ffmpeg 子进程）可轮询它提前结束。
class CancelToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

/// 转换上下文
class EngineContext {
  final String inputPath;
  final String outputPath;
  final String targetFormat;
  final Map<String, dynamic> params;

  /// 输入格式 id（可选，部分引擎需要据此选择解析器）。
  final String sourceFormat;

  /// 取消令牌（可选）。
  final CancelToken? cancelToken;

  EngineContext({
    required this.inputPath,
    required this.outputPath,
    required this.targetFormat,
    this.params = const {},
    this.sourceFormat = '',
    this.cancelToken,
  });
}

/// 引擎状态（密封类用 sealed class 实现）
sealed class EngineProgress {
  const EngineProgress();
}

class Progress extends EngineProgress {
  final double percent;
  final String message;
  const Progress(this.percent, [this.message = '']);
}

class Success extends EngineProgress {
  final String outputPath;
  const Success(this.outputPath);
}

class Error extends EngineProgress {
  final String message;
  const Error(this.message);
}

class PluginRequired extends EngineProgress {
  final String pluginId;
  final int sizeMb;
  final String? note;
  const PluginRequired(this.pluginId, this.sizeMb, {this.note});
}

/// 统一引擎接口
abstract class IEngine {
  String get id;
  String? get requiredPluginId => null;

  Stream<EngineProgress> convert(EngineContext context);
}
