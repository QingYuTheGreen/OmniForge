import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_next_flutter/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_next_flutter/ffmpeg_session.dart';
import 'package:ffmpeg_kit_next_flutter/ffprobe_kit.dart';
import 'package:ffmpeg_kit_next_flutter/return_code.dart';
import 'package:ffmpeg_kit_next_flutter/statistics.dart';
import 'package:flutter/foundation.dart';

import 'engines/ffmpeg_backend.dart';
import 'i_engine.dart';

/// 基于 `ffmpeg_kit_flutter_new` 的原生音视频后端。
///
/// 该插件在 Android / iOS / macOS / Windows / Linux 上随包内置编译好的
/// ffmpeg 原生库（Android 为 .so，Windows 为 .dll，macOS/iOS 为 .dylib /
/// xcframework），并通过平台通道直接调用原生解码/编码接口。
/// 全程不启动任何外部命令行进程，完全离线。
class FfmpegKitBackend extends FfmpegBackend {
  FfmpegKitBackend();

  FFmpegSession? _session;

  @override
  bool get isAvailable {
    if (kIsWeb) return false;
    return Platform.isAndroid ||
        Platform.isIOS ||
        Platform.isMacOS ||
        Platform.isWindows ||
        Platform.isLinux;
  }

  @override
  String get name => 'FFmpegKit（原生库）';

  @override
  Future<void> execute(
    List<String> arguments, {
    void Function(double percent)? onProgress,
    CancelToken? cancelToken,
  }) async {
    if (!isAvailable) {
      throw const FfmpegBackendUnavailable('当前平台没有可用的原生音视频库');
    }

    // 先用 ffprobe 读取媒体时长，便于把 statistics 换算成百分比。
    int? totalMs;
    final inputIndex = arguments.indexOf('-i');
    if (inputIndex >= 0 && inputIndex + 1 < arguments.length) {
      totalMs = await probeDurationMs(arguments[inputIndex + 1]);
    }

    final completer = Completer<void>();
    String? lastMessage;
    var cancelled = false;

    unawaited(
      FFmpegKit.executeAsync(
        arguments.join(' '),
        (FFmpegSession session) async {
          final returnCode = await session.getReturnCode();
          _session = null;
          if (ReturnCode.isSuccess(returnCode)) {
            if (!completer.isCompleted) completer.complete();
          } else if (ReturnCode.isCancel(returnCode)) {
            cancelled = true;
            if (!completer.isCompleted) {
              completer.completeError(
                const FfmpegBackendCancelled('转码已取消'),
              );
            }
          } else {
            final logs = await session.getOutput();
            if (!completer.isCompleted) {
              completer.completeError(
                FfmpegBackendFailure(
                  _tail(logs ?? lastMessage ?? '原生转码失败'),
                ),
              );
            }
          }
        },
        (log) {
          final message = log.getMessage();
          if (message.isNotEmpty) lastMessage = message;
        },
        (Statistics statistics) {
          if (onProgress == null) return;
          if (totalMs != null && totalMs > 0) {
            final ratio = statistics.getTime() / totalMs;
            onProgress(ratio.clamp(0.0, 1.0));
          }
        },
      ).then((session) {
        _session = session;
      }),
    );

    if (cancelToken != null) {
      unawaited(
        _watchCancel(cancelToken, () {
          cancelled = true;
          _session?.cancel();
        }),
      );
    }

    try {
      await completer.future;
    } finally {
      _session = null;
      if (cancelled && onProgress != null) {
        // 取消后不再推进进度。
      }
    }
  }

  Future<void> _watchCancel(CancelToken token, void Function() onCancel) async {
    while (!token.isCancelled) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    onCancel();
  }

  @override
  Future<int?> probeDurationMs(String inputPath) async {
    if (!isAvailable) return null;
    try {
      final session = await FFprobeKit.getMediaInformation(inputPath);
      final information = session.getMediaInformation();
      final duration = information?.getDuration();
      if (duration == null || duration.isEmpty) return null;
      final seconds = double.tryParse(duration);
      if (seconds == null) return null;
      return (seconds * 1000).round();
    } catch (_) {
      return null;
    }
  }

  String _tail(String text) {
    final lines = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) return '原生转码失败';
    return lines.last;
  }
}
