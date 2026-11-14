import 'dart:async';
import 'dart:io';

import '../engine_utils.dart';
import '../i_engine.dart';
import 'ffmpeg_backend.dart';

/// 音视频引擎。
///
/// 所有转码都通过 [FfmpegBackend] 调用**原生库**（Android .so / Windows .dll /
/// macOS .dylib，由 FFmpegKitNext 原生库提供）完成；
/// 不使用命令行进程，不依赖系统安装的 ffmpeg。
class FfmpegEngine implements IEngine {
  FfmpegEngine({FfmpegBackend backend = const NullFfmpegBackend()})
    : _backend = backend;

  final FfmpegBackend _backend;

  @override
  String get id => 'ffmpeg';

  @override
  String? get requiredPluginId => isAvailable ? null : 'ffmpeg';

  bool get isAvailable => _backend.isAvailable;

  String get backendName => _backend.name;

  @override
  Stream<EngineProgress> convert(EngineContext context) {
    final controller = StreamController<EngineProgress>();

    Future<void> run() async {
      final output = context.outputPath;
      if (!isAvailable) {
        controller.add(const PluginRequired('ffmpeg', 45, note: '需要内置原生音视频解码库'));
        await controller.close();
        return;
      }
      try {
        await ensureParentDirectory(output);
        final args = <String>[
          '-y',
          '-i',
          context.inputPath,
          ..._buildArgs(context),
          output,
        ];
        controller.add(const Progress(0.05, '准备转码（原生库）'));
        controller.add(const Progress(0.1, '转换中'));
        var lastPercent = 0.1;
        await _backend.execute(
          args,
          cancelToken: context.cancelToken,
          onProgress: (ratio) {
            final percent = (0.1 + ratio.clamp(0.0, 1.0) * 0.88).clamp(0.1, 0.98);
            if (percent - lastPercent >= 0.01 && !controller.isClosed) {
              lastPercent = percent;
              controller.add(Progress(percent, '转换中'));
            }
          },
        );
        if (!File(output).existsSync()) {
          controller.add(const Error('原生转码没有生成输出文件'));
        } else {
          controller.add(const Progress(0.99, '完成'));
          controller.add(Success(output));
        }
      } on FfmpegBackendUnavailable catch (error) {
        controller.add(PluginRequired('ffmpeg', 45, note: error.message));
      } on FfmpegBackendFailure catch (error) {
        controller.add(Error(_short(error.message)));
      } catch (error) {
        controller.add(Error('原生转码失败：$error'));
      } finally {
        await controller.close();
      }
    }

    unawaited(run());
    return controller.stream;
  }

  List<String> _buildArgs(EngineContext context) {
    final target = context.targetFormat.toLowerCase();
    final args = <String>[];
    final quality = intParam(context, 'quality', 23);
    switch (target) {
      case 'mp3':
        args.addAll(['-vn', '-c:a', 'libmp3lame', '-b:a', '192k']);
      case 'wav':
        args.addAll(['-vn', '-c:a', 'pcm_s16le']);
      case 'flac':
        args.addAll(['-vn', '-c:a', 'flac']);
      case 'aac':
      case 'm4a':
        args.addAll(['-vn', '-c:a', 'aac', '-b:a', '192k']);
      case 'ogg':
        args.addAll(['-vn', '-c:a', 'libvorbis', '-q:a', '5']);
      case 'mp4':
        args.addAll([
          '-c:v',
          'libx264',
          '-preset',
          'medium',
          '-crf',
          '$quality',
          '-c:a',
          'aac',
          '-b:a',
          '192k',
          '-movflags',
          '+faststart',
        ]);
      case 'webm':
        args.addAll([
          '-c:v',
          'libvpx-vp9',
          '-crf',
          '$quality',
          '-c:a',
          'libopus',
        ]);
      case 'mkv':
      case 'mov':
        args.addAll(['-c:v', 'libx264', '-crf', '$quality', '-c:a', 'aac']);
      case 'avi':
        args.addAll(['-c:v', 'mpeg4', '-qscale:v', '5', '-c:a', 'mp3']);
      case 'gif':
        final fps = intParam(context, 'fps', 12).clamp(1, 60);
        args.addAll([
          '-vf',
          'fps=$fps,scale=640:-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse',
          '-loop',
          '${intParam(context, 'loop', 0)}',
        ]);
      case 'srt':
        args.addAll(['-map', '0:s:0', '-c:s', 'srt']);
      case 'png':
      case 'jpg':
      case 'jpeg':
        final fps = intParam(context, 'fps', 1).clamp(1, 60);
        args.addAll(['-vf', 'fps=$fps']);
      default:
        break;
    }
    final start = stringParam(context, 'start', '');
    if (start.isNotEmpty) args.addAll(['-ss', start]);
    final duration = stringParam(context, 'duration', '');
    if (duration.isNotEmpty) args.addAll(['-t', duration]);
    return args;
  }

  String _short(String text) {
    final lines = text.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return text;
    return lines.last.trim();
  }
}
