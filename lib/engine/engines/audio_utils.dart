import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../engine_utils.dart';

/// 解码后的 16-bit PCM WAV 数据。
///
/// [samples] 为**交错**（interleaved）排列的 16-bit 有符号样本，
/// 即 `[L0, R0, L1, R1, ...]`；单声道时就是顺序样本。
class WavPcm16 {
  const WavPcm16({
    required this.sampleRate,
    required this.channels,
    required this.samples,
  });

  /// 采样率（Hz）。
  final int sampleRate;

  /// 声道数（>= 1）。
  final int channels;

  /// 交错排列的 16-bit 有符号 PCM 样本。
  final Int16List samples;

  /// 采样帧数（每帧包含 [channels] 个样本）。
  int get frameCount => channels <= 0 ? 0 : samples.length ~/ channels;

  /// 音频时长。
  Duration get duration {
    if (sampleRate <= 0) return Duration.zero;
    return Duration(
      milliseconds: (frameCount * 1000 / sampleRate).round(),
    );
  }

  bool get isEmpty => samples.isEmpty || channels <= 0;
}

/// 音频相关的纯 Dart 工具：WAV 解析 + 波形图绘制。
///
/// 只依赖 `package:image`，不依赖 Flutter，也不启动任何外部进程。
class AudioUtils {
  const AudioUtils._();

  // ─────────────────────────── WAV 解析 ───────────────────────────

  /// 解析 16-bit PCM WAV。
  ///
  /// 支持标准 RIFF/WAVE 容器、`fmt ` / `data` 分块（允许分块乱序与填充字节），
  /// 以及 WAVE_FORMAT_EXTENSIBLE（0xFFFE）中 bitsPerSample=16 的常见形态。
  /// 其它位深/压缩编码会抛 [EngineException]。
  static WavPcm16 decodeWavPcm16(Uint8List bytes) {
    if (bytes.length < 44) {
      throw const EngineException('WAV 数据长度不足，无法解析');
    }
    final data = ByteData.sublistView(bytes);

    String tagAt(int offset) {
      if (offset < 0 || offset + 4 > bytes.length) return '';
      return String.fromCharCodes(bytes.sublist(offset, offset + 4));
    }

    if (tagAt(0) != 'RIFF' || tagAt(8) != 'WAVE') {
      throw const EngineException('不是有效的 WAV（RIFF/WAVE）文件');
    }

    int? channels;
    int? sampleRate;
    int? bitsPerSample;
    int? audioFormat;
    Int16List? samples;

    var offset = 12;
    while (offset + 8 <= bytes.length) {
      final chunkId = tagAt(offset);
      final chunkSize = data.getUint32(offset + 4, Endian.little);
      final body = offset + 8;

      if (chunkId == 'fmt ') {
        if (chunkSize < 16 || body + 16 > bytes.length) {
          throw const EngineException('WAV fmt 分块不完整');
        }
        audioFormat = data.getUint16(body, Endian.little);
        channels = data.getUint16(body + 2, Endian.little);
        sampleRate = data.getUint32(body + 4, Endian.little);
        bitsPerSample = data.getUint16(body + 14, Endian.little);
      } else if (chunkId == 'data') {
        if (channels == null || sampleRate == null || bitsPerSample == null) {
          // data 出现在 fmt 之前：先记录失败，继续找 fmt 不现实，直接报错。
          throw const EngineException('WAV 缺少 fmt 分块');
        }
        final usable = chunkSize < bytes.length - body
            ? chunkSize
            : bytes.length - body;
        final sampleCount = usable ~/ 2;
        final pcm = Int16List(sampleCount);
        for (var i = 0; i < sampleCount; i++) {
          pcm[i] = data.getInt16(body + i * 2, Endian.little);
        }
        samples = pcm;
        break;
      }

      // 分块按偶数字节对齐。
      final advance = chunkSize + (chunkSize & 1);
      if (advance <= 0) break;
      offset = body + advance;
    }

    if (channels == null || sampleRate == null || bitsPerSample == null) {
      throw const EngineException('WAV 缺少 fmt 分块');
    }
    if (samples == null) {
      throw const EngineException('WAV 缺少 data 分块');
    }
    if (channels <= 0) {
      throw const EngineException('WAV 声道数无效');
    }
    final formatOk = audioFormat == 1 || audioFormat == 0xFFFE;
    if (!formatOk || bitsPerSample != 16) {
      throw EngineException(
        '仅支持 16-bit PCM WAV（当前格式=$audioFormat，位深=$bitsPerSample）',
      );
    }
    return WavPcm16(
      sampleRate: sampleRate,
      channels: channels,
      samples: samples,
    );
  }

  // ─────────────────────────── 颜色 ───────────────────────────

  /// 解析 `#RRGGBB` / `0xRRGGBB` / `RRGGBB` / `#RGB` 形式颜色，返回 0xRRGGBB。
  ///
  /// 解析失败时返回 [fallback]。
  static int parseHexColor(String value, {int fallback = 0x000000}) {
    var text = value.trim();
    if (text.startsWith('#')) {
      text = text.substring(1);
    } else if (text.startsWith('0x') || text.startsWith('0X')) {
      text = text.substring(2);
    }
    if (text.length == 3) {
      text = text.split('').map((c) => '$c$c').join();
    }
    if (text.length != 6) return fallback & 0xFFFFFF;
    final parsed = int.tryParse(text, radix: 16);
    if (parsed == null) return fallback & 0xFFFFFF;
    return parsed & 0xFFFFFF;
  }

  // ─────────────────────────── 波形绘制 ───────────────────────────

  /// 把 [wav] 画成波形图并返回 [img.Image]。
  ///
  /// 每一列取对应时间窗内的最小/最大样本，构成 min/max 包络：
  /// - [fill] 为 true：把整段包络填成实心竖条；
  /// - [fill] 为 false：只画 2px 宽的包络线。
  ///
  /// [background] / [waveColor] 为 0xRRGGBB 整数。
  static img.Image renderWaveformImage({
    required WavPcm16 wav,
    required int width,
    required int height,
    required int background,
    required int waveColor,
    bool fill = false,
  }) {
    final w = width.clamp(1, 8192);
    final h = height.clamp(1, 8192);
    final image = img.Image(width: w, height: h, numChannels: 3);
    img.fill(
      image,
      color: img.ColorRgb8(_red(background), _green(background), _blue(background)),
    );

    final frames = wav.frameCount;
    if (frames <= 0) return image;

    // 多声道下混为单声道（算术平均），并求峰值用于归一化。
    final mono = Int32List(frames);
    var peak = 0;
    final channels = wav.channels;
    final samples = wav.samples;
    for (var frame = 0; frame < frames; frame++) {
      var sum = 0;
      final base = frame * channels;
      for (var c = 0; c < channels; c++) {
        sum += samples[base + c];
      }
      final value = sum ~/ channels;
      mono[frame] = value;
      final abs = value.abs();
      if (abs > peak) peak = abs;
    }
    if (peak == 0) return image; // 静音：保持背景色。

    final wave = img.ColorRgb8(_red(waveColor), _green(waveColor), _blue(waveColor));
    final centerY = (h - 1) / 2.0;
    final amplitude = h / 2.0 - 1.0;

    for (var x = 0; x < w; x++) {
      final start = (x * frames) ~/ w;
      var end = ((x + 1) * frames) ~/ w;
      if (end <= start) end = start + 1;
      if (end > frames) end = frames;

      var minValue = mono[start];
      var maxValue = mono[start];
      for (var i = start + 1; i < end; i++) {
        final v = mono[i];
        if (v < minValue) minValue = v;
        if (v > maxValue) maxValue = v;
      }

      final top = (centerY - maxValue / peak * amplitude)
          .round()
          .clamp(0, h - 1);
      final bottom = (centerY - minValue / peak * amplitude)
          .round()
          .clamp(0, h - 1);
      final y1 = top <= bottom ? top : bottom;
      final y2 = top <= bottom ? bottom : top;

      if (fill) {
        for (var y = y1; y <= y2; y++) {
          image.setPixelRgb(x, y, wave.r, wave.g, wave.b);
        }
      } else {
        img.drawLine(
          image,
          x1: x,
          y1: y1,
          x2: x,
          y2: y2,
          color: wave,
          thickness: 2,
        );
      }
    }
    return image;
  }

  /// 把 [wav] 画成 PNG 波形图字节。
  static Uint8List encodeWaveformPng({
    required WavPcm16 wav,
    required int width,
    required int height,
    required int background,
    required int waveColor,
    bool fill = false,
  }) {
    final image = renderWaveformImage(
      wav: wav,
      width: width,
      height: height,
      background: background,
      waveColor: waveColor,
      fill: fill,
    );
    return img.encodePng(image);
  }

  /// 把 [wav] 画成 JPG 波形图字节。
  ///
  /// JPG 没有透明通道，默认背景应为白色、波形为深色（由调用方决定颜色）。
  static Uint8List encodeWaveformJpg({
    required WavPcm16 wav,
    required int width,
    required int height,
    required int background,
    required int waveColor,
    bool fill = false,
    int quality = 92,
  }) {
    final image = renderWaveformImage(
      wav: wav,
      width: width,
      height: height,
      background: background,
      waveColor: waveColor,
      fill: fill,
    );
    return img.encodeJpg(image, quality: quality.clamp(1, 100));
  }

  static int _red(int rgb) => (rgb >> 16) & 0xFF;

  static int _green(int rgb) => (rgb >> 8) & 0xFF;

  static int _blue(int rgb) => rgb & 0xFF;
}
