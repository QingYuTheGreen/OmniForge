import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'engines/ffmpeg_backend.dart';
import 'i_engine.dart';

/// 基于 OpenHarmony NAPI 原生库 `@ohos/ffmpeg-kit` 的音视频后端。
///
/// ArkTS 侧桥接在 `ohos/entry/src/main/ets/plugins/FFmpegBridge.ets`，
/// 通道名固定为 [channelName]，底层是 libffmpegkit_napi.so（libav* + NAPI），
/// 全程不启动任何命令行进程。
///
/// 通道契约（与 FFmpegBridge.ets 严格对应）：
///
/// Dart -> ArkTS：
/// * `execute`  `{command: String, durationMs?: int}` -> `int` sessionId
/// * `cancel`   `{sessionId: int}` -> void
/// * `probeDuration` `{path: String}` -> `int?`（毫秒，无法解析时为 null）
///
/// ArkTS -> Dart（回调）：
/// * `progress` `{sessionId: int, percent: double}`（0..100）
/// * `log`      `{sessionId: int, message: String}`
/// * `complete` `{sessionId: int, code: int}`（0 成功，255 取消）
class FfmpegOhosBackend extends FfmpegBackend {
  FfmpegOhosBackend();

  /// 与 ArkTS 侧 `MethodChannel(messenger, 'omniforge/ffmpeg')` 一致。
  static const MethodChannel _channel = MethodChannel(channelName);

  /// 通道名，同时导出给文档/测试使用。
  static const String channelName = 'omniforge/ffmpeg';

  static const String _unavailableMessage =
      '鸿蒙 FFmpeg 原生库未集成（@ohos/ffmpeg-kit）';

  /// ffmpeg-kit 约定的“被取消”返回码。
  static const int _cancelCode = 255;

  /// 按 sessionId 分发回调，因此同一后端可并发执行多个转码任务。
  static final Map<int, _OhosFfmpegSession> _sessions =
      <int, _OhosFfmpegSession>{};

  static bool _handlerInstalled = false;

  @override
  bool get isAvailable => !kIsWeb && Platform.operatingSystem == 'ohos';

  @override
  String get name => 'ohos-ffmpeg';

  @override
  Future<void> execute(
    List<String> arguments, {
    void Function(double percent)? onProgress,
    CancelToken? cancelToken,
  }) async {
    if (!isAvailable) {
      throw const FfmpegBackendUnavailable('当前平台不支持鸿蒙 FFmpeg 后端');
    }
    _ensureHandlerInstalled();

    final String command = arguments.join(' ');
    if (command.trim().isEmpty) {
      throw FfmpegBackendFailure('FFmpeg 命令为空');
    }

    // 先探测媒体时长：ArkTS 侧据此把 statistics 的 time(ms) 换算成百分比。
    int? totalMs;
    final int inputIndex = arguments.indexOf('-i');
    if (inputIndex >= 0 && inputIndex + 1 < arguments.length) {
      totalMs = await probeDurationMs(arguments[inputIndex + 1]);
    }

    final int? sessionId;
    try {
      sessionId = await _channel.invokeMethod<int>('execute', <String, dynamic>{
        'command': command,
        if (totalMs != null && totalMs > 0) 'durationMs': totalMs,
      });
    } on MissingPluginException {
      throw const FfmpegBackendUnavailable(_unavailableMessage);
    } on PlatformException catch (error) {
      throw _mapPlatformException(error);
    }

    if (sessionId == null) {
      throw FfmpegBackendFailure('鸿蒙 FFmpeg 未返回会话 ID');
    }

    final _OhosFfmpegSession session = _OhosFfmpegSession(
      sessionId: sessionId,
      onProgress: onProgress,
    );
    _sessions[sessionId] = session;

    Timer? watchTimer;
    Timer? cancelFallback;
    if (cancelToken != null) {
      watchTimer = Timer.periodic(const Duration(milliseconds: 200), (Timer t) {
        if (!cancelToken.isCancelled) return;
        t.cancel();
        if (session.cancelRequested) return;
        session.cancelRequested = true;
        unawaited(_cancelSession(session.sessionId));
        // 原生侧取消后一般会回传 complete；若没有，兜底结束，避免永久等待。
        cancelFallback = Timer(const Duration(seconds: 8), () {
          session.complete(code: _cancelCode);
        });
      });
    }

    try {
      await session.done.future;
    } finally {
      watchTimer?.cancel();
      cancelFallback?.cancel();
      _sessions.remove(sessionId);
    }

    final int code = session.returnCode ?? -1;
    if (session.cancelRequested || code == _cancelCode) {
      throw const FfmpegBackendCancelled('转码已取消');
    }
    if (code == 0) return;
    throw FfmpegBackendFailure(_failureMessage(code, session.lastLog));
  }

  @override
  Future<int?> probeDurationMs(String inputPath) async {
    if (!isAvailable) return null;
    try {
      final num? value = await _channel.invokeMethod<num>(
        'probeDuration',
        <String, dynamic>{'path': inputPath},
      );
      if (value == null) return null;
      final int ms = value.round();
      return ms > 0 ? ms : null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// 安装唯一的通道回调处理器（MethodChannel 全局只有一个 handler）。
  static void _ensureHandlerInstalled() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  static Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'progress':
        _handleProgress(call.arguments);
        return null;
      case 'log':
        _handleLog(call.arguments);
        return null;
      case 'complete':
        _handleComplete(call.arguments);
        return null;
      default:
        // 未知方法直接忽略，避免向原生侧抛未捕获异常。
        return null;
    }
  }

  static void _handleProgress(Object? arguments) {
    if (arguments is! Map) return;
    final int? sessionId = _asInt(arguments['sessionId']);
    final double? percent = _asDouble(arguments['percent']);
    if (sessionId == null || percent == null) return;
    final _OhosFfmpegSession? session = _sessions[sessionId];
    if (session == null) return;
    session.onProgress?.call((percent / 100).clamp(0.0, 1.0));
  }

  static void _handleLog(Object? arguments) {
    if (arguments is! Map) return;
    final int? sessionId = _asInt(arguments['sessionId']);
    final Object? message = arguments['message'];
    if (sessionId == null || message is! String || message.isEmpty) return;
    _sessions[sessionId]?.appendLog(message);
  }

  static void _handleComplete(Object? arguments) {
    if (arguments is! Map) return;
    final int? sessionId = _asInt(arguments['sessionId']);
    if (sessionId == null) return;
    final int code = _asInt(arguments['code']) ?? -1;
    _sessions[sessionId]?.complete(code: code);
  }

  static Future<void> _cancelSession(int sessionId) async {
    try {
      await _channel.invokeMethod<void>(
        'cancel',
        <String, dynamic>{'sessionId': sessionId},
      );
    } on MissingPluginException {
      // 原生库不在，忽略：execute 会在 complete 超时后自行收敛。
    } on PlatformException {
      // 取消本身失败无需上抛，调用方仍按 Cancelled 处理。
    }
  }

  static Object _mapPlatformException(PlatformException error) {
    if (error.code == 'plugin_missing') {
      return const FfmpegBackendUnavailable(_unavailableMessage);
    }
    final String detail = error.message?.trim().isNotEmpty == true
        ? error.message!.trim()
        : '鸿蒙 FFmpeg 调用失败（${error.code}）';
    return FfmpegBackendFailure(detail);
  }

  static String _failureMessage(int code, String log) {
    final List<String> lines = log
        .split('\n')
        .map((String line) => line.trim())
        .where((String line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) return 'FFmpeg 执行失败(code=$code)';
    return lines.last;
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static double? _asDouble(Object? value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}

/// 单次原生转码会话的 Dart 侧状态。
class _OhosFfmpegSession {
  _OhosFfmpegSession({required this.sessionId, this.onProgress});

  final int sessionId;
  final void Function(double percent)? onProgress;
  final Completer<void> done = Completer<void>();

  String lastLog = '';
  int? returnCode;
  bool cancelRequested = false;

  void appendLog(String message) {
    lastLog = lastLog.isEmpty ? message : '$lastLog\n$message';
    // 只保留末尾 8KB，避免长时间转码时日志无限增长。
    if (lastLog.length > 8192) {
      lastLog = lastLog.substring(lastLog.length - 8192);
    }
  }

  void complete({required int code}) {
    if (done.isCompleted) return;
    returnCode = code;
    done.complete();
  }
}
