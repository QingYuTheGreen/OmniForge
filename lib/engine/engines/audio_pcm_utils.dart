/// 音频 PCM / WAV 公共工具：供「音频 → MIDI」与「音频 → 频谱图」两个引擎共用。
///
/// 只依赖 dart:typed_data 与 dart:math，纯 Dart 实现：
/// - WAV（RIFF）解析：PCM 8/16/24/32bit 与 IEEE float32，自动混为单声道 float；
/// - WAV（16bit PCM 单声道）编码：测试与离线场景下自造音频；
/// - 通过 [FfmpegBackend] 把任意音频解码成 22050Hz 单声道 WAV 的辅助函数；
/// - 迭代 radix-2 FFT，供频谱图（以及可选的基于 FFT 的分析）使用。
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../engine_utils.dart';
import '../i_engine.dart';
import 'ffmpeg_backend.dart';

/// 解码后的单声道音频。
class AudioPcm {
  const AudioPcm(this.samples, this.sampleRate);

  /// -1.0 .. 1.0 的采样。
  final Float32List samples;

  final int sampleRate;

  int get length => samples.length;

  double get durationSeconds =>
      sampleRate <= 0 ? 0 : samples.length / sampleRate;
}

/// WAV 解析 / 生成与 PCM 相关工具。
class AudioPcmUtils {
  const AudioPcmUtils._();

  /// 解析 WAV 字节，返回单声道 float 采样。
  ///
  /// 支持 PCM（8/16/24/32 bit）与 IEEE float（32/64 bit）；多声道取平均。
  static AudioPcm readWavPcm16(Uint8List bytes) {
    if (bytes.length < 12) {
      throw const EngineException('音频数据过短，无法解析 WAV');
    }
    if (!_asciiEquals(bytes, 0, 'RIFF') ||
        !_asciiEquals(bytes, 8, 'WAVE')) {
      throw const EngineException('不是有效的 WAV 文件');
    }

    int? audioFormat;
    int? channels;
    int? sampleRate;
    int? bitsPerSample;
    Uint8List? data;

    var offset = 12;
    while (offset + 8 <= bytes.length) {
      final chunkId = _ascii(bytes, offset, 4);
      final chunkSize = _u32le(bytes, offset + 4);
      final payload = offset + 8;
      if (chunkId == 'fmt ') {
        if (payload + 16 > bytes.length) break;
        audioFormat = _u16le(bytes, payload);
        channels = _u16le(bytes, payload + 2);
        sampleRate = _u32le(bytes, payload + 4);
        bitsPerSample = _u16le(bytes, payload + 14);
      } else if (chunkId == 'data') {
        final end = math.min(payload + chunkSize, bytes.length);
        data = bytes.sublist(payload, end);
      }
      // 每个 chunk 按偶数长度对齐
      offset = payload + chunkSize + (chunkSize.isOdd ? 1 : 0);
    }

    if (audioFormat == null ||
        channels == null ||
        sampleRate == null ||
        bitsPerSample == null) {
      throw const EngineException('WAV 缺少 fmt 数据块');
    }
    if (data == null || data.isEmpty) {
      throw const EngineException('WAV 缺少音频数据块');
    }
    if (channels <= 0 || sampleRate <= 0) {
      throw const EngineException('WAV 声道数或采样率非法');
    }
    final isFloat = audioFormat == 3;
    if (audioFormat != 1 && !isFloat) {
      throw EngineException('不支持的 WAV 编码（audioFormat=$audioFormat）');
    }

    final bytesPerSample = bitsPerSample ~/ 8;
    if (bytesPerSample <= 0) {
      throw const EngineException('WAV 位深非法');
    }
    final frameSize = bytesPerSample * channels;
    if (frameSize <= 0) {
      throw const EngineException('WAV 帧大小非法');
    }
    final frameCount = data.length ~/ frameSize;
    final out = Float32List(frameCount);
    final view = ByteData.sublistView(data);

    for (var frame = 0; frame < frameCount; frame++) {
      var sum = 0.0;
      for (var channel = 0; channel < channels; channel++) {
        final base = frame * frameSize + channel * bytesPerSample;
        sum += _readSample(view, base, bitsPerSample, isFloat);
      }
      out[frame] = (sum / channels).clamp(-1.0, 1.0);
    }
    return AudioPcm(out, sampleRate);
  }

  /// 把单声道 float 采样编码成 16bit PCM WAV。
  static Uint8List encodeWavPcm16(
    Float32List samples, {
    int sampleRate = 22050,
    int channels = 1,
  }) {
    if (channels < 1) channels = 1;
    const bytesPerSample = 2;
    final frameSize = bytesPerSample * channels;
    final dataSize = samples.length * frameSize;
    final totalSize = 44 + dataSize;
    final out = Uint8List(totalSize);
    final view = ByteData.sublistView(out);

    void writeAscii(int at, String text) {
      for (var i = 0; i < text.length; i++) {
        out[at + i] = text.codeUnitAt(i);
      }
    }

    writeAscii(0, 'RIFF');
    view.setUint32(4, totalSize - 8, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    view.setUint32(16, 16, Endian.little);
    view.setUint16(20, 1, Endian.little); // PCM
    view.setUint16(22, channels, Endian.little);
    view.setUint32(24, sampleRate, Endian.little);
    view.setUint32(28, sampleRate * frameSize, Endian.little);
    view.setUint16(32, frameSize, Endian.little);
    view.setUint16(34, 16, Endian.little);
    writeAscii(36, 'data');
    view.setUint32(40, dataSize, Endian.little);

    var at = 44;
    for (final sample in samples) {
      final scaled = (sample.clamp(-1.0, 1.0) * 32767.0).round();
      for (var channel = 0; channel < channels; channel++) {
        view.setInt16(at, scaled, Endian.little);
        at += 2;
      }
    }
    return out;
  }

  /// 生成一段正弦波（测试 / 预览用）。
  static Float32List sineWave(
    double frequency, {
    int sampleRate = 22050,
    double seconds = 1.0,
    double amplitude = 0.5,
  }) {
    final count = (sampleRate * seconds).round();
    final samples = Float32List(count);
    final omega = 2 * math.pi * frequency / sampleRate;
    for (var i = 0; i < count; i++) {
      samples[i] = amplitude * math.sin(omega * i);
    }
    return samples;
  }

  /// 通过 [backend] 把 [inputPath] 解码为 [sampleRate] 单声道 WAV 并解析。
  ///
  /// ffmpeg 原生库缺失时抛 [PluginRequiredException]（ffmpeg / 45MB），
  /// 由 [SimpleEngine.convert] 转成 PluginRequired 进度事件。
  static Future<AudioPcm> decodeWithFfmpeg(
    FfmpegBackend backend,
    String inputPath, {
    int sampleRate = 22050,
    void Function(double percent)? onProgress,
    CancelToken? cancelToken,
  }) async {
    if (!backend.isAvailable) {
      throw const PluginRequiredException('ffmpeg', 45);
    }
    final tempDir = await Directory.systemTemp.createTemp('omniforge_audio_');
    final wavPath = '${tempDir.path}${Platform.pathSeparator}decoded.wav';
    try {
      await backend.execute(
        <String>[
          '-y',
          '-i',
          inputPath,
          '-vn',
          '-ac',
          '1',
          '-ar',
          '$sampleRate',
          '-f',
          'wav',
          wavPath,
        ],
        onProgress: onProgress,
        cancelToken: cancelToken,
      );
      if (cancelToken?.isCancelled ?? false) {
        throw const EngineException('已取消');
      }
      final file = File(wavPath);
      if (!await file.exists()) {
        throw const EngineException('音频解码失败：未生成中间 WAV 文件');
      }
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        throw const EngineException('音频解码失败：中间 WAV 为空');
      }
      return readWavPcm16(bytes);
    } on PluginRequiredException {
      rethrow;
    } on FfmpegBackendUnavailable {
      throw const PluginRequiredException('ffmpeg', 45);
    } on FfmpegBackendCancelled {
      throw const EngineException('已取消');
    } on FfmpegBackendFailure catch (error) {
      throw EngineException('音频解码失败：${error.message}');
    } on FileSystemException catch (error) {
      throw EngineException('音频解码失败：${error.message}');
    } finally {
      try {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {
        // 临时目录清理失败不影响结果
      }
    }
  }

  static bool _asciiEquals(Uint8List bytes, int offset, String text) {
    if (offset + text.length > bytes.length) return false;
    for (var i = 0; i < text.length; i++) {
      if (bytes[offset + i] != text.codeUnitAt(i)) return false;
    }
    return true;
  }

  static String _ascii(Uint8List bytes, int offset, int length) {
    if (offset + length > bytes.length) return '';
    return String.fromCharCodes(bytes.sublist(offset, offset + length));
  }

  static int _u16le(Uint8List bytes, int offset) =>
      bytes[offset] | (bytes[offset + 1] << 8);

  static int _u32le(Uint8List bytes, int offset) =>
      (bytes[offset] |
          (bytes[offset + 1] << 8) |
          (bytes[offset + 2] << 16) |
          (bytes[offset + 3] << 24)) &
      0xFFFFFFFF;

  static double _readSample(ByteData view, int base, int bits, bool isFloat) {
    switch (bits) {
      case 8:
        return (view.getUint8(base) - 128) / 128.0;
      case 16:
        return view.getInt16(base, Endian.little) / 32768.0;
      case 24:
        var value = view.getUint8(base) |
            (view.getUint8(base + 1) << 8) |
            (view.getUint8(base + 2) << 16);
        if (value & 0x800000 != 0) value -= 0x1000000;
        return value / 8388608.0;
      case 32:
        if (isFloat) {
          return view.getFloat32(base, Endian.little).toDouble();
        }
        return view.getInt32(base, Endian.little) / 2147483648.0;
      case 64:
        if (isFloat) {
          return view.getFloat64(base, Endian.little);
        }
        return 0;
      default:
        return 0;
    }
  }
}

/// 迭代 radix-2 复数 FFT（长度必须是 2 的幂）。
///
/// 默认使用 double 精度，直接对 real/imag 数组原地变换。
class Fft {
  const Fft._();

  static bool isPowerOfTwo(int value) =>
      value > 0 && (value & (value - 1)) == 0;

  /// 原地正向变换。
  static void forward(Float64List real, Float64List imag) {
    final n = real.length;
    if (n != imag.length) {
      throw ArgumentError('real/imag 长度不一致');
    }
    if (n <= 1) return;
    if (!isPowerOfTwo(n)) {
      throw ArgumentError('FFT 长度必须是 2 的幂：$n');
    }

    // 位反转置换
    var j = 0;
    for (var i = 1; i < n; i++) {
      var bit = n >> 1;
      while (j & bit != 0) {
        j ^= bit;
        bit >>= 1;
      }
      j ^= bit;
      if (i < j) {
        final tr = real[i];
        real[i] = real[j];
        real[j] = tr;
        final ti = imag[i];
        imag[i] = imag[j];
        imag[j] = ti;
      }
    }

    // 蝶形运算
    for (var length = 2; length <= n; length <<= 1) {
      final angle = -2 * math.pi / length;
      final wReal = math.cos(angle);
      final wImag = math.sin(angle);
      for (var start = 0; start < n; start += length) {
        var curReal = 1.0;
        var curImag = 0.0;
        final half = length >> 1;
        for (var k = 0; k < half; k++) {
          final evenIndex = start + k;
          final oddIndex = evenIndex + half;
          final oddReal = real[oddIndex] * curReal - imag[oddIndex] * curImag;
          final oddImag = real[oddIndex] * curImag + imag[oddIndex] * curReal;
          real[oddIndex] = real[evenIndex] - oddReal;
          imag[oddIndex] = imag[evenIndex] - oddImag;
          real[evenIndex] += oddReal;
          imag[evenIndex] += oddImag;
          final nextReal = curReal * wReal - curImag * wImag;
          curImag = curReal * wImag + curImag * wReal;
          curReal = nextReal;
        }
      }
    }
  }

  /// 对实信号做单帧 FFT，返回幅度谱（长度 n/2，只保留正频率）。
  static Float64List magnitudeSpectrum(Float64List frame) {
    final n = frame.length;
    final real = Float64List.fromList(frame);
    final imag = Float64List(n);
    forward(real, imag);
    final half = n >> 1;
    final out = Float64List(half);
    for (var i = 0; i < half; i++) {
      out[i] = math.sqrt(real[i] * real[i] + imag[i] * imag[i]);
    }
    return out;
  }

  /// 生成 Hann 窗。
  static Float64List hannWindow(int size) {
    final window = Float64List(size);
    for (var i = 0; i < size; i++) {
      window[i] = 0.5 * (1 - math.cos(2 * math.pi * i / (size - 1)));
    }
    return window;
  }
}
