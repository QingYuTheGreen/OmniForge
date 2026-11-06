/// 转换上下文
class EngineContext {
  final String inputPath;
  final String outputPath;
  final String targetFormat;
  final Map<String, dynamic> params;

  EngineContext({
    required this.inputPath,
    required this.outputPath,
    required this.targetFormat,
    this.params = const {},
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
  const PluginRequired(this.pluginId, this.sizeMb);
}

/// 统一引擎接口
abstract class IEngine {
  String get id;
  String? get requiredPluginId => null;

  Stream<EngineProgress> convert(EngineContext context);
}
