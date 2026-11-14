/// 音频 → MIDI（单旋律提取）引擎。
///
/// 处理流程：
/// 1. 通过注入的 [FfmpegBackend] 把任意音频解码成 22050Hz 单声道 WAV；
/// 2. [AudioPcmUtils.readWavPcm16] 解析为 float 采样；
/// 3. 分帧（帧长 2048 / hop 1024）+ Hann 窗 + 自相关基频估计 → MIDI 音高；
/// 4. RMS 静音过滤、中值平滑、相邻音高跳变分段、最短音符合并；
/// 5. 手写标准 MIDI 文件（Format 0，单轨，480 PPQ，meta 0x51 tempo）。
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../common/binary_io.dart';
import '../engine_utils.dart';
import '../i_engine.dart';
import 'audio_pcm_utils.dart';
import 'ffmpeg_backend.dart';

/// 一段检测出来的音符（时间单位毫秒）。
class DetectedNote {
  const DetectedNote(this.midiNote, this.startMs, this.endMs);

  /// MIDI 音符号（A4 = 69）。
  final int midiNote;

  final int startMs;
  final int endMs;

  int get durationMs => endMs - startMs;

  @override
  String toString() => 'Note($midiNote, $startMs..$endMs)';
}

/// 音频 → MIDI 引擎。
class AudioMidiEngine extends SimpleEngine {
  const AudioMidiEngine({this.backend = const NullFfmpegBackend()});

  /// ffmpeg 解码后端（测试可注入 fake）。
  final FfmpegBackend backend;

  @override
  String get id => 'audio_midi';

  /// 单声道解码目标采样率。
  static const int decodeSampleRate = 22050;

  /// 分析帧长（2 的幂）。
  static const int frameSize = 2048;

  /// 帧移。
  static const int hopSize = 1024;

  /// 每帧对应的毫秒数。
  static const double frameMs = hopSize * 1000.0 / decodeSampleRate;

  /// MIDI 每四分音符的 tick 数。
  static const int ticksPerQuarter = 480;

  /// 分帧结果（供验证与复用）：
  /// 返回每帧的 MIDI 音高（null 表示静音 / 不可判定）。
  static List<int?> pitchTrack(
    AudioPcm pcm, {
    double silence = 0.01,
    double minFrequency = 55.0,
    double maxFrequency = 1200.0,
  }) {
    final samples = pcm.samples;
    final sampleRate = pcm.sampleRate;
    if (samples.isEmpty || sampleRate <= 0) return <int?>[];
    final window = Fft.hannWindow(frameSize);
    final frameCount = samples.length < frameSize
        ? 0
        : (samples.length - frameSize) ~/ hopSize + 1;
    final result = <int?>[];
    var lowestLag = (sampleRate / maxFrequency).floor();
    var highestLag = (sampleRate / minFrequency).ceil();
    if (lowestLag < 2) lowestLag = 2;
    if (highestLag > frameSize ~/ 2) highestLag = frameSize ~/ 2;

    for (var frame = 0; frame < frameCount; frame++) {
      final start = frame * hopSize;
      // RMS（未加窗，反映真实能量）
      var sumSquares = 0.0;
      for (var i = 0; i < frameSize; i++) {
        final value = samples[start + i];
        sumSquares += value * value;
      }
      final rms = math.sqrt(sumSquares / frameSize);
      if (rms < silence) {
        result.add(null);
        continue;
      }
      // 加窗后做自相关
      final windowed = Float64List(frameSize);
      for (var i = 0; i < frameSize; i++) {
        windowed[i] = samples[start + i] * window[i];
      }
      final frequency = _autocorrelationPitch(
        windowed,
        sampleRate,
        lowestLag,
        highestLag,
      );
      if (frequency == null) {
        result.add(null);
        continue;
      }
      final midi = 69 + 12 * (math.log(frequency / 440.0) / math.ln2);
      if (!midi.isFinite) {
        result.add(null);
        continue;
      }
      final rounded = midi.round().clamp(12, 120);
      result.add(rounded);
    }
    return result;
  }

  /// 归一化自相关基频估计；返回 null 表示无明显周期。
  static double? _autocorrelationPitch(
    Float64List frame,
    int sampleRate,
    int lowestLag,
    int highestLag,
  ) {
    final n = frame.length;
    // 只计算一次能量
    var energy = 0.0;
    for (var i = 0; i < n; i++) {
      energy += frame[i] * frame[i];
    }
    if (energy <= 1e-12) return null;

    var bestLag = -1;
    var bestScore = -2.0;
    // 归一化自相关 r(lag)
    for (var lag = lowestLag; lag <= highestLag && lag < n; lag++) {
      var correlation = 0.0;
      var norm = 0.0;
      final limit = n - lag;
      for (var i = 0; i < limit; i++) {
        final a = frame[i];
        final b = frame[i + lag];
        correlation += a * b;
        norm += a * a + b * b;
      }
      final score = norm <= 1e-12 ? 0.0 : 2 * correlation / norm;
      if (score > bestScore) {
        bestScore = score;
        bestLag = lag;
      }
    }
    if (bestLag <= 0 || bestScore < 0.3) return null;
    // 在峰值附近取三点做抛物线插值，提升精度
    var refinedLag = bestLag.toDouble();
    if (bestLag > lowestLag && bestLag < highestLag) {
      double scoreAt(int lag) {
        var correlation = 0.0;
        var norm = 0.0;
        final limit = n - lag;
        for (var i = 0; i < limit; i++) {
          final a = frame[i];
          final b = frame[i + lag];
          correlation += a * b;
          norm += a * a + b * b;
        }
        return norm <= 1e-12 ? 0.0 : 2 * correlation / norm;
      }

      final left = scoreAt(bestLag - 1);
      final center = scoreAt(bestLag);
      final right = scoreAt(bestLag + 1);
      final denominator = left - 2 * center + right;
      if (denominator.abs() > 1e-9) {
        final delta = 0.5 * (left - right) / denominator;
        refinedLag = bestLag + delta.clamp(-0.5, 0.5);
      }
    }
    if (refinedLag <= 1) return null;
    return sampleRate / refinedLag;
  }

  /// 从 PCM 提取音符序列。
  static List<DetectedNote> extractNotes(
    AudioPcm pcm, {
    double silence = 0.01,
    int minNoteMs = 100,
    int bpm = 120,
  }) {
    final raw = pitchTrack(pcm, silence: silence);
    if (raw.isEmpty) return <DetectedNote>[];
    // 中值平滑（窗口 3，忽略 null）
    final smoothed = List<int?>.from(raw);
    for (var i = 1; i < raw.length - 1; i++) {
      final values = <int>[
        if (raw[i - 1] != null) raw[i - 1]!,
        if (raw[i] != null) raw[i]!,
        if (raw[i + 1] != null) raw[i + 1]!,
      ];
      if (values.length >= 2) {
        values.sort();
        smoothed[i] = values[values.length ~/ 2];
      }
    }

    // 合并成段
    final segments = <List<int>>[]; // [midi, startFrame, endFrame]
    for (var i = 0; i < smoothed.length; i++) {
      final pitch = smoothed[i];
      if (pitch == null) continue;
      if (segments.isNotEmpty &&
          segments.last[2] >= i - 1 &&
          (segments.last[0] - pitch).abs() <= 1) {
        segments.last[2] = i + 1;
        // 用更长的音高为准
        if (i > 0 && raw[i] != null) {
          final previousPitch = segments.last[0];
          segments.last[0] = ((previousPitch + pitch) / 2).round();
        }
      } else {
        segments.add(<int>[pitch, i, i + 1]);
      }
    }

    // 应用最短音符时长：过短段合并到相邻同音高段或丢弃
    final notes = <DetectedNote>[];
    for (final segment in segments) {
      final startMs = (segment[1] * frameMs).round();
      final endMs = (segment[2] * frameMs).round();
      final duration = endMs - startMs;
      if (duration < minNoteMs) {
        if (notes.isNotEmpty && (notes.last.midiNote - segment[0]).abs() <= 2) {
          final last = notes.removeLast();
          notes.add(DetectedNote(
            last.midiNote,
            last.startMs,
            math.max(last.endMs, endMs),
          ));
        }
        continue;
      }
      notes.add(DetectedNote(segment[0], startMs, endMs));
    }

    // 量化到 bpm 网格并消除重叠
    final beatMs = 60000.0 / bpm;
    final quantized = <DetectedNote>[];
    for (final note in notes) {
      final start = _quantize(note.startMs, beatMs);
      var end = _quantize(note.endMs, beatMs);
      if (end <= start) end = start + beatMs.toInt().clamp(1, 100000);
      if (quantized.isNotEmpty && start < quantized.last.endMs) {
        // 与上一音符重叠：截断上一音符
        final last = quantized.removeLast();
        quantized.add(DetectedNote(
          last.midiNote,
          last.startMs,
          math.max(last.startMs + 1, start),
        ));
      }
      quantized.add(DetectedNote(note.midiNote, start, end));
    }
    return quantized.where((note) => note.endMs > note.startMs).toList();
  }

  static int _quantize(int valueMs, double beatMs) {
    // 量化到 1/4 拍
    final step = beatMs / 4;
    return (valueMs / step).round() * step.round();
  }

  /// 生成标准 MIDI 文件（Format 0，单轨）。
  static Uint8List encodeMidi(
    List<DetectedNote> notes, {
    int bpm = 120,
    int ticksPerBeat = ticksPerQuarter,
    String trackName = 'OmniForge',
  }) {
    if (bpm < 1 || bpm > 1000) bpm = 120;
    final division = ticksPerBeat.clamp(24, 960);
    double msToTicks(int ms) => ms / 1000.0 * (bpm / 60.0) * division;

    // 事件列表：(tick, order, bytes)，order 保证同 tick 时 note-off 先于 note-on
    final events = <List<Object>>[];
    events.add(<Object>[
      0,
      0,
      <int>[0xFF, 0x51, 0x03, ..._u24be(60000000 ~/ bpm)],
    ]);
    final nameBytes = <int>[
      for (final code in trackName.codeUnits) code & 0x7F,
    ];
    events.add(<Object>[
      0,
      0,
      <int>[0xFF, 0x03, ..._vlq(nameBytes.length), ...nameBytes],
    ]);

    for (final note in notes) {
      if (note.endMs <= note.startMs) continue;
      final pitch = note.midiNote.clamp(0, 127);
      final startTick = msToTicks(note.startMs).round();
      final endTick = math.max(startTick + 1, msToTicks(note.endMs).round());
      events.add(<Object>[
        startTick,
        2,
        <int>[0x90, pitch, 100],
      ]);
      events.add(<Object>[
        endTick,
        1,
        <int>[0x80, pitch, 64],
      ]);
    }
    events.sort((a, b) {
      final tickCompare = (a[0] as int).compareTo(b[0] as int);
      if (tickCompare != 0) return tickCompare;
      return (a[1] as int).compareTo(b[1] as int);
    });

    final track = ByteWriter();
    var previousTick = 0;
    for (final event in events) {
      final tick = event[0] as int;
      final delta = math.max(0, tick - previousTick);
      previousTick = tick;
      track.bytes(_vlq(delta));
      track.bytes(event[2] as List<int>);
    }
    track
      ..bytes(_vlq(0))
      ..u8(0xFF)
      ..u8(0x2F)
      ..u8(0x00);
    final trackBytes = track.toBytes();

    final writer = ByteWriter()
      ..ascii('MThd')
      ..bytes(_u32be(6))
      ..bytes(_u16be(0)) // format 0
      ..bytes(_u16be(1)) // 单轨
      ..bytes(_u16be(division))
      ..ascii('MTrk')
      ..bytes(_u32be(trackBytes.length))
      ..bytes(trackBytes);
    return writer.toBytes();
  }

  static List<int> _u16be(int value) =>
      <int>[(value >> 8) & 0xFF, value & 0xFF];

  static List<int> _u32be(int value) => <int>[
        (value >> 24) & 0xFF,
        (value >> 16) & 0xFF,
        (value >> 8) & 0xFF,
        value & 0xFF,
      ];

  /// 可变长度数量（MIDI VLQ）。
  static List<int> _vlq(int value) {
    var remaining = value < 0 ? 0 : value;
    final buffer = <int>[remaining & 0x7F];
    remaining >>= 7;
    while (remaining > 0) {
      buffer.insert(0, (remaining & 0x7F) | 0x80);
      remaining >>= 7;
    }
    return buffer;
  }

  static List<int> _u24be(int value) =>
      <int>[(value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF];

  @override
  void validate(EngineContext context) {
    final target = context.targetFormat.toLowerCase();
    if (target != 'midi' && target != 'mid') {
      throw EngineException('音频转 MIDI 仅支持输出 midi，收到：$target');
    }
  }

  @override
  Future<void> execute(EngineContext context) async {
    final silence = doubleParam(context, 'silence', 0.01).clamp(0.0, 1.0);
    final minNoteMs = intParam(context, 'min_note_ms', 100).clamp(10, 10000);
    final bpm = intParam(context, 'bpm', intParam(context, 'tempo', 120))
        .clamp(20, 400);

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
    final notes = extractNotes(
      pcm,
      silence: silence,
      minNoteMs: minNoteMs,
      bpm: bpm,
    );
    if (notes.isEmpty) {
      throw const EngineException('未检测到有效音符（可能是静音或非旋律音频）');
    }
    final bytes = encodeMidi(notes, bpm: bpm);
    await writeFileBytes(context.outputPath, bytes);
  }
}
