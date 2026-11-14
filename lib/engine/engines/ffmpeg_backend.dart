import '../i_engine.dart';

/// 音视频转码后端抽象。
///
/// 约定：所有实现都必须通过「原生库」（so / dylib / dll，经 FFI 或平台插件
/// 直接链接 libav*）完成转码，**不允许**启动 `ffmpeg` 命令行进程。
/// 这样 Android / iOS 上无需任何外部二进制，桌面端也不依赖用户环境。
abstract class FfmpegBackend {
  const FfmpegBackend();

  /// 原生库是否可用。
  bool get isAvailable;

  /// 后端显示名，用于日志与错误提示。
  String get name;

  /// 执行一次 ffmpeg 参数化转码。
  ///
  /// [arguments] 为不含 `ffmpeg` 前缀的参数列表，
  /// 例如 `['-y', '-i', in, '-vn', '-c:a', 'libmp3lame', out]`。
  /// [onProgress] 以 0..1 汇报进度。失败时抛出带原因的异常。
  Future<void> execute(
    List<String> arguments, {
    void Function(double percent)? onProgress,
    CancelToken? cancelToken,
  });

  /// 查询媒体时长（毫秒）；无法获取时返回 null。
  Future<int?> probeDurationMs(String inputPath);
}

/// 没有任何原生后端时使用的占位实现：音视频转换会提示缺少原生插件。
class NullFfmpegBackend extends FfmpegBackend {
  const NullFfmpegBackend();

  @override
  bool get isAvailable => false;

  @override
  String get name => '未加载原生音视频库';

  @override
  Future<void> execute(
    List<String> arguments, {
    void Function(double percent)? onProgress,
    CancelToken? cancelToken,
  }) async {
    throw const FfmpegBackendUnavailable();
  }

  @override
  Future<int?> probeDurationMs(String inputPath) async => null;
}

/// 原生音视频库缺失。
class FfmpegBackendUnavailable implements Exception {
  const FfmpegBackendUnavailable([this.message = '原生音视频库未加载']);

  final String message;

  @override
  String toString() => message;
}

/// 原生转码失败（携带 ffmpeg 日志尾部）。
class FfmpegBackendFailure implements Exception {
  FfmpegBackendFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 转码被取消。
class FfmpegBackendCancelled implements Exception {
  const FfmpegBackendCancelled([this.message = '转码已取消']);

  final String message;

  @override
  String toString() => message;
}
