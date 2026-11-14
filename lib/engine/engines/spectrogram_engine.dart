/// 音频 → 频谱图（png / jpg）引擎。
///
/// 处理流程：ffmpeg 解码为 22050Hz 单声道 WAV → 分帧（1024 / hop 512）+ Hann 窗 →
/// radix-2 FFT → 幅度谱转 dB 并归一化 → viridis 简化色带着色 → 图片。
/// 无 ffmpeg 后端时抛出 PluginRequired（ffmpeg / 45MB）。
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../engine_utils.dart';
import '../i_engine.dart';
import 'audio_pcm_utils.dart';
import 'ffmpeg_backend.dart';

/// 音频 → 频谱图引擎。
class SpectrogramEngine extends SimpleEngine {
  const SpectrogramEngine({this.backend = const NullFfmpegBackend()});

  /// ffmpeg 解码后端（测试可注入 fake）。
  final FfmpegBackend backend;

  @override
  String get id => 'spectrogram';

  /// 单声道解码目标采样率。
  static const int decodeSampleRate = 22050;

  /// FFT 帧长。
  static const int frameSize = 1024;

  /// 帧移。
  static const int hopSize = 512;

  /// 动态范围（dB）：高于 [maxDb]-[dynamicRangeDb] 的才着色，其余用背景色。
  static const double dynamicRangeDb = 80.0;

  /// viridis 简化色带（从低到高）。
  static const List<int> _viridis = <int>[
    0x440154,
    0x482878,
    0x3E4A89,
    0x31688E,
    0x26828E,
    0x1F9E89,
    0x35B779,
    0x6DCD59,
    0xB4DE2C,
    0xFDE725,
  ];

  /// 计算频谱图矩阵：返回 [frames][bins] 的 dB 值（未归一化）。
  static List<Float64List> computeSpectrum(AudioPcm pcm) {
    final samples = pcm.samples;
    if (samples.length < frameSize) return <Float64List>[];
    final window = Fft.hannWindow(frameSize);
    final frameCount = (samples.length - frameSize) ~/ hopSize + 1;
    const bins = frameSize ~/ 2;
    final spectrum = <Float64List>[];
    final real = Float64List(frameSize);
    final imag = Float64List(frameSize);
    for (var frame = 0; frame < frameCount; frame++) {
      final start = frame * hopSize;
      for (var i = 0; i < frameSize; i++) {
        real[i] = samples[start + i] * window[i];
        imag[i] = 0;
      }
      Fft.forward(real, imag);
      final magnitudes = Float64List(bins);
      for (var bin = 0; bin < bins; bin++) {
        final re = real[bin];
        final im = imag[bin];
        final magnitude = math.sqrt(re * re + im * im) / (frameSize / 2);
        magnitudes[bin] = magnitude;
      }
      spectrum.add(magnitudes);
    }
    return spectrum;
  }

  /// 把频谱渲染成图片。
  static img.Image renderImage(
    List<Float64List> spectrum, {
    int width = 800,
    int height = 400,
    String background = '#000000',
  }) {
    final targetWidth = width.clamp(16, 8192);
    final targetHeight = height.clamp(16, 8192);
    if (spectrum.isEmpty || spectrum.first.isEmpty) {
      final empty = img.Image(
        width: targetWidth,
        height: targetHeight,
        numChannels: 3,
      );
      final backgroundRgb = _parseHexColor(background, 0x000000);
      img.fill(
        empty,
        color: img.ColorRgb8(
          (backgroundRgb >> 16) & 0xFF,
          (backgroundRgb >> 8) & 0xFF,
          backgroundRgb & 0xFF,
        ),
      );
      return empty;
    }

    final frameCount = spectrum.length;
    final bins = spectrum.first.length;
    // 全局最大值作为归一化基准
    var maxDb = -1e9;
    for (final frame in spectrum) {
      for (final magnitude in frame) {
        final db = 20 * (math.log(magnitude + 1e-12) / math.ln10);
        if (db > maxDb) maxDb = db;
      }
    }
    if (!maxDb.isFinite) maxDb = 0;
    final minDb = maxDb - dynamicRangeDb;
    final backgroundRgb = _parseHexColor(background, 0x000000);
    final backgroundRed = (backgroundRgb >> 16) & 0xFF;
    final backgroundGreen = (backgroundRgb >> 8) & 0xFF;
    final backgroundBlue = backgroundRgb & 0xFF;

    final image = img.Image(
      width: targetWidth,
      height: targetHeight,
      numChannels: 3,
    );
    for (var x = 0; x < targetWidth; x++) {
      final frameIndex = (x * (frameCount - 1) / math.max(1, targetWidth - 1))
          .round()
          .clamp(0, frameCount - 1);
      final frame = spectrum[frameIndex];
      for (var y = 0; y < targetHeight; y++) {
        // 屏幕上方 = 高频
        final ratio = (targetHeight - 1 - y) / math.max(1, targetHeight - 1);
        final binIndex = (ratio * (bins - 1)).round().clamp(0, bins - 1);
        final magnitude = frame[binIndex];
        final db = 20 * (math.log(magnitude + 1e-12) / math.ln10);
        if (db <= minDb) {
          image.setPixelRgb(x, y, backgroundRed, backgroundGreen, backgroundBlue);
          continue;
        }
        final level = ((db - minDb) / dynamicRangeDb).clamp(0.0, 1.0);
        final color = _viridisColor(level);
        image.setPixelRgb(
          x,
          y,
          (color >> 16) & 0xFF,
          (color >> 8) & 0xFF,
          color & 0xFF,
        );
      }
    }
    return image;
  }

  /// 在 viridis 简化色带上取色。
  static int _viridisColor(double level) {
    final clamped = level.clamp(0.0, 1.0);
    final scaled = clamped * (_viridis.length - 1);
    final index = scaled.floor().clamp(0, _viridis.length - 2);
    final fraction = scaled - index;
    final low = _viridis[index];
    final high = _viridis[index + 1];
    int mix(int shift) {
      final a = (low >> shift) & 0xFF;
      final b = (high >> shift) & 0xFF;
      return (a + (b - a) * fraction).round().clamp(0, 255);
    }

    return (mix(16) << 16) | (mix(8) << 8) | mix(0);
  }

  static int _parseHexColor(String text, int fallback) {
    var value = text.trim();
    if (value.startsWith('#')) value = value.substring(1);
    if (value.length == 3) {
      value = value.split('').map((c) => '$c$c').join();
    }
    if (value.length == 8) value = value.substring(2);
    return int.tryParse(value, radix: 16) ?? fallback;
  }

  @override
  void validate(EngineContext context) {
    final target = context.targetFormat.toLowerCase();
    if (target != 'png' && target != 'jpg' && target != 'jpeg') {
      throw EngineException('频谱图仅支持输出 png / jpg，收到：$target');
    }
  }

  @override
  Future<void> execute(EngineContext context) async {
    final width = intParam(context, 'width', 800).clamp(16, 8192);
    final height = intParam(context, 'height', 400).clamp(16, 8192);
    final background = stringParam(context, 'background', '#000000');
    final quality = intParam(context, 'quality', 90).clamp(1, 100);

    final pcm = await AudioPcmUtils.decodeWithFfmpeg(
      backend,
      context.inputPath,
      sampleRate: decodeSampleRate,
      cancelToken: context.cancelToken,
    );
    if (pcm.samples.isEmpty) {
      throw const EngineException('解码后的音频为空');
    }
    if (context.cancelToken?.isCancelled ?? false) {
      throw const EngineException('已取消');
    }
    final spectrum = computeSpectrum(pcm);
    final image = renderImage(
      spectrum,
      width: width,
      height: height,
      background: background,
    );
    final target = context.targetFormat.toLowerCase();
    final bytes = target == 'png'
        ? img.encodePng(image, level: 6)
        : img.encodeJpg(image, quality: quality);
    await writeFileBytes(context.outputPath, Uint8List.fromList(bytes));
  }
}
