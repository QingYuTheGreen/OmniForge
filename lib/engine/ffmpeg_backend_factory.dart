import 'dart:io';

import 'package:flutter/foundation.dart';

import 'engines/ffmpeg_backend.dart';
import 'ffmpeg_kit_backend.dart';
import 'ffmpeg_ohos_backend.dart';

/// 按当前平台创建 FFmpeg 原生后端。
///
/// * OpenHarmony（`Platform.operatingSystem == 'ohos'`）走自行桥接的
///   `@ohos/ffmpeg-kit` 原生库（见 `FFmpegOhosBackend`）。
/// * 其余平台（Android / iOS / macOS / Windows / Linux）继续使用
///   `ffmpeg_kit_next_flutter` 插件（见 `FfmpegKitBackend`）。
FfmpegBackend createPlatformFfmpegBackend() {
  if (!kIsWeb && Platform.operatingSystem == 'ohos') {
    return FfmpegOhosBackend();
  }
  return FfmpegKitBackend();
}
