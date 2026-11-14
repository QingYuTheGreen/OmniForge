// 跨类型音视频转换自检（不依赖 Flutter、不依赖本机 FFmpeg）。
//
// 用法：cd /root/work/media && /opt/dart/dart-sdk/bin/dart run tool/verify_media.dart
//
// 本机没有原生 FFmpeg（NullFfmpegBackend），所以用 FakeBackend 断言传给
// backend.execute 的 ffmpeg 参数；纯 Dart 部分（WAV 解析 + 波形绘制）真实执行。
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'package:omniforge/engine/engines/audio_utils.dart';
import 'package:omniforge/engine/engines/ffmpeg_backend.dart';
import 'package:omniforge/engine/engines/ffmpeg_engine.dart';
import 'package:omniforge/engine/i_engine.dart';

var _failures = 0;

void check(bool ok, String label, [String? detail]) {
  final mark = ok ? '✓' : '✗';
  final suffix = detail == null || detail.isEmpty ? '' : ' — $detail';
  print('$mark $label$suffix');
  if (!ok) _failures++;
}

Future<List<EngineProgress>> runEngine(
  FfmpegEngine engine,
  EngineContext context,
) => engine.convert(context).toList();

void main() async {
  final temp = await Directory.systemTemp.createTemp('omniforge_verify_');
  try {
    final audioInput = p.join(temp.path, 'song.mp3');
    final videoInput = p.join(temp.path, 'clip.mp4');
    await File(audioInput).writeAsBytes(<int>[0x49, 0x44, 0x33, 1, 2, 3]);
    await File(videoInput).writeAsBytes(<int>[0, 0, 0, 0]);

    await _testAudioToVideo(temp.path, audioInput);
    await _testAudioToVideoSolidBackground(temp.path, audioInput);
    await _testAudioToWebm(temp.path, audioInput);
    await _testAudioToWaveformPng(temp.path, audioInput);
    await _testAudioToWaveformJpg(temp.path, audioInput);
    await _testVideoToSubtitle(temp.path, videoInput);
    await _testVideoWithoutSubtitle(temp.path, videoInput);
    _testWavParser();
  } finally {
    try {
      await temp.delete(recursive: true);
    } catch (_) {}
  }

  print('');
  if (_failures == 0) {
    print('全部自检通过 ✓');
  } else {
    print('自检失败：$_failures 项');
    exitCode = 1;
  }
}

// ─────────────────────────── 1) 音频 → 视频（波形封面） ───────────────────────────

Future<void> _testAudioToVideo(String dir, String audioInput) async {
  print('\n[1] 音频 → 视频（默认 cover=true，波形封面）');
  final backend = FakeBackend();
  final engine = FfmpegEngine(backend: backend);
  final out = p.join(dir, 'audio_to_video.mp4');
  final events = await runEngine(
    engine,
    EngineContext(
      inputPath: audioInput,
      outputPath: out,
      targetFormat: 'mp4',
      sourceFormat: 'mp3',
    ),
  );

  check(backend.invocations.isNotEmpty, 'backend 被调用');
  check(
    events.any((e) => e is Success),
    '转换返回 Success',
    _eventSummary(events),
  );
  check(File(out).existsSync(), '输出文件存在：audio_to_video.mp4');

  final wavCalls = backend.invocations
      .where((args) => args.isNotEmpty && args.last.endsWith('.wav'))
      .toList();
  check(wavCalls.length == 1, '第一步先解出 WAV', '共 ${wavCalls.length} 次');
  if (wavCalls.length == 1) {
    final args = wavCalls.single;
    check(
      args.contains('-ac') && args.contains('1') && args.contains('8000'),
      'WAV 参数：单声道 / 8kHz',
      args.join(' '),
    );
  }

  final videoCall = _findCall(backend, '-shortest');
  check(videoCall != null, '找到合成视频的调用（含 -shortest）');
  if (videoCall != null) {
    final joined = videoCall.join(' ');
    check(videoCall.contains('libx264'), '视频编码 libx264');
    check(videoCall.contains('yuv420p'), '像素格式 yuv420p');
    check(videoCall.contains('aac'), '音频编码 aac');
    check(
      videoCall.contains('-loop') &&
          videoCall.any((a) => a.endsWith('cover.png')),
      '使用波形封面 PNG（-loop 1 -i cover.png）',
    );
    check(
      videoCall.last == out,
      '输出路径在参数末尾',
      videoCall.last,
    );
    print('    命令：${joined.replaceAll(dir, '<tmp>')}');
  }
}

// ─────────────────────────── 2) 音频 → 视频（lavfi 纯色） ───────────────────────────

Future<void> _testAudioToVideoSolidBackground(
  String dir,
  String audioInput,
) async {
  print('\n[2] 音频 → 视频（cover=false，lavfi 纯色背景）');
  final backend = FakeBackend();
  final engine = FfmpegEngine(backend: backend);
  final out = p.join(dir, 'solid.mp4');
  final events = await runEngine(
    engine,
    EngineContext(
      inputPath: audioInput,
      outputPath: out,
      targetFormat: 'mp4',
      sourceFormat: 'mp3',
      params: <String, dynamic>{
        'cover': false,
        'width': 640,
        'height': 360,
        'background': '#101418',
      },
    ),
  );

  check(events.any((e) => e is Success), '转换返回 Success');
  check(File(out).existsSync(), '输出文件存在：solid.mp4');
  check(backend.invocations.length == 1, 'cover=false 时只调用一次 backend');

  final args = backend.invocations.single;
  final joined = args.join(' ');
  check(args.contains('lavfi'), '使用 lavfi 输入');
  check(
    joined.contains('color=c=0x101418:s=640x360'),
    '纯色背景参数正确',
    joined,
  );
  check(args.contains('-shortest') && args.contains('libx264'), '-shortest / libx264');
  check(args.last == out, '输出路径在参数末尾');
}

// ─────────────────────────── 2b) 音频 → WebM ───────────────────────────

Future<void> _testAudioToWebm(String dir, String audioInput) async {
  print('\n[2b] 音频 → WebM（VP9 + Opus，WebM 容器不支持 H.264/AAC）');
  final backend = FakeBackend();
  final engine = FfmpegEngine(backend: backend);
  final out = p.join(dir, 'audio_to_video.webm');
  final events = await runEngine(
    engine,
    EngineContext(
      inputPath: audioInput,
      outputPath: out,
      targetFormat: 'webm',
      sourceFormat: 'mp3',
      params: <String, dynamic>{'cover': false},
    ),
  );
  check(events.any((e) => e is Success), '转换返回 Success');
  final args = backend.invocations.single;
  check(
    args.contains('libvpx-vp9') && args.contains('libopus'),
    'WebM 使用 VP9 + Opus 编码',
    args.join(' '),
  );
  check(args.contains('-shortest'), '含 -shortest');
}

// ─────────────────────────── 3) 音频 → PNG 波形 ───────────────────────────
Future<void> _testAudioToWaveformPng(String dir, String audioInput) async {
  print('\n[3] 音频 → PNG 波形图');
  final backend = FakeBackend();
  final engine = FfmpegEngine(backend: backend);
  final out = p.join(dir, 'wave.png');
  final events = await runEngine(
    engine,
    EngineContext(
      inputPath: audioInput,
      outputPath: out,
      targetFormat: 'png',
      sourceFormat: 'mp3',
      params: <String, dynamic>{'width': 480, 'height': 180},
    ),
  );

  check(events.any((e) => e is Success), '转换返回 Success', _eventSummary(events));
  check(File(out).existsSync(), '输出文件存在：wave.png');

  final bytes = await File(out).readAsBytes();
  check(
    bytes.length > 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A,
    'PNG 文件头正确',
  );

  final image = img.decodePng(bytes);
  check(image != null, 'image 包可解码输出的 PNG');
  if (image != null) {
    check(
      image.width == 480 && image.height == 180,
      '尺寸符合 width/height 参数',
      '${image.width}x${image.height}',
    );
    // 默认背景 #0f1115；统计非背景像素，应有波形线条。
    var nonBackground = 0;
    for (final pixel in image) {
      if (pixel.r.toInt() != 0x0F ||
          pixel.g.toInt() != 0x11 ||
          pixel.b.toInt() != 0x15) {
        nonBackground++;
      }
    }
    check(
      nonBackground > 0,
      '波形像素非纯背景（min/max 包络已绘制）',
      '$nonBackground 个像素',
    );
  }

  final wavCall = backend.invocations.single;
  check(
    wavCall.length > 2 &&
        wavCall[1] == '-i' &&
        wavCall.contains('-ac') &&
        wavCall.last.endsWith('.wav'),
    '第一步解码为 WAV',
    wavCall.join(' '),
  );
}

// ─────────────────────────── 4) 音频 → JPG 波形 ───────────────────────────

Future<void> _testAudioToWaveformJpg(String dir, String audioInput) async {
  print('\n[4] 音频 → JPG 波形图（白色背景 / 深色波形）');
  final backend = FakeBackend();
  final engine = FfmpegEngine(backend: backend);
  final out = p.join(dir, 'wave.jpg');
  final events = await runEngine(
    engine,
    EngineContext(
      inputPath: audioInput,
      outputPath: out,
      targetFormat: 'jpg',
      sourceFormat: 'mp3',
      params: <String, dynamic>{'width': 320, 'height': 120},
    ),
  );

  check(events.any((e) => e is Success), '转换返回 Success', _eventSummary(events));
  final bytes = await File(out).readAsBytes();
  check(bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8, 'JPG 文件头正确');
  final image = img.decodeJpg(bytes);
  check(image != null, 'image 包可解码输出的 JPG');
  if (image != null) {
    final pixel = image.getPixel(0, 0);
    check(
      pixel.r.toInt() > 240 && pixel.g.toInt() > 240 && pixel.b.toInt() > 240,
      'JPG 默认白色背景',
      '#${pixel.r.toInt().toRadixString(16)}${pixel.g.toInt().toRadixString(16)}${pixel.b.toInt().toRadixString(16)}',
    );
  }
}

// ─────────────────────────── 5) 视频 → SRT ───────────────────────────

Future<void> _testVideoToSubtitle(String dir, String videoInput) async {
  print('\n[5] 视频 → 字幕（抽取内嵌字幕轨）');
  final backend = FakeBackend();
  final engine = FfmpegEngine(backend: backend);
  final out = p.join(dir, 'sub.srt');
  final events = await runEngine(
    engine,
    EngineContext(
      inputPath: videoInput,
      outputPath: out,
      targetFormat: 'srt',
      sourceFormat: 'mp4',
      params: <String, dynamic>{'stream': 1},
    ),
  );

  check(events.any((e) => e is Success), '转换返回 Success', _eventSummary(events));
  check(File(out).existsSync(), '输出文件存在：sub.srt');
  final content = await File(out).readAsString();
  check(content.contains('-->'), 'SRT 内容含时间轴 -->');
  check(
    content.contains('你好') && content.trimLeft().startsWith('1'),
    'SRT 内容完整',
    content.replaceAll('\n', ' | '),
  );

  final args = backend.invocations.single;
  check(
    args.contains('-map') && args.contains('0:s:1'),
    '按 stream 参数选择字幕轨 0:s:1',
    args.join(' '),
  );
  check(args.contains('-c:s') && args.contains('srt'), '字幕编码 srt');
}

// ─────────────────────────── 6) 视频无字幕轨 ───────────────────────────

Future<void> _testVideoWithoutSubtitle(String dir, String videoInput) async {
  print('\n[6] 视频无字幕轨 → 明确错误提示');
  final backend = FakeBackend(failSrt: true);
  final engine = FfmpegEngine(backend: backend);
  final out = p.join(dir, 'no_sub.srt');
  final events = await runEngine(
    engine,
    EngineContext(
      inputPath: videoInput,
      outputPath: out,
      targetFormat: 'srt',
      sourceFormat: 'mp4',
    ),
  );

  final errors = events.whereType<Error>().map((e) => e.message).toList();
  check(errors.isNotEmpty, '返回 Error');
  check(
    errors.any((message) => message.contains('内嵌字幕')),
    '错误消息包含「内嵌字幕」',
    errors.isEmpty ? '(无)' : errors.first,
  );
  check(
    errors.any(
      (message) => message.contains('语音识别生成字幕需要模型插件'),
    ),
    '错误消息说明语音识别需要插件',
  );
  check(!events.any((e) => e is Success), '不会返回 Success');
  check(!File(out).existsSync(), '没有生成伪造的 srt 文件');
}

// ─────────────────────────── 7) WAV 解析单测 ───────────────────────────

void _testWavParser() {
  print('\n[7] WAV 解析（纯 Dart 真实执行）');
  final wavBytes = FakeBackend.buildSineWav();
  final wav = AudioUtils.decodeWavPcm16(wavBytes);
  check(wav.sampleRate == 8000, '采样率 8000', '${wav.sampleRate}');
  check(wav.channels == 1, '声道数 1', '${wav.channels}');
  check(wav.frameCount == 2400, '帧数 2400（0.3s）', '${wav.frameCount}');
  check(wav.duration.inMilliseconds == 300, '时长 300ms', '${wav.duration}');

  var bad = false;
  try {
    AudioUtils.decodeWavPcm16(Uint8List.fromList(<int>[1, 2, 3, 4]));
  } on Object {
    bad = true;
  }
  check(bad, '损坏数据抛 EngineException');

  check(AudioUtils.parseHexColor('#4ade80') == 0x4ADE80, 'parseHexColor(#4ade80)');
  check(
    AudioUtils.parseHexColor('101418') == 0x101418,
    'parseHexColor(101418)',
  );
  check(
    AudioUtils.parseHexColor('#abc') == 0xAABBCC,
    'parseHexColor(#abc)',
  );
  check(
    AudioUtils.parseHexColor('nope', fallback: 0x123456) == 0x123456,
    'parseHexColor 非法值回退',
  );
}

// ─────────────────────────── FakeBackend ───────────────────────────

class FakeBackend extends FfmpegBackend {
  FakeBackend({this.failSrt = false});

  /// srt 输出时模拟「视频没有字幕轨」的失败。
  final bool failSrt;

  /// 记录每次 execute 收到的完整参数。
  final List<List<String>> invocations = <List<String>>[];

  @override
  bool get isAvailable => true;

  @override
  String get name => 'FakeBackend（仅用于自检）';

  @override
  Future<int?> probeDurationMs(String inputPath) async => 3000;

  @override
  Future<void> execute(
    List<String> arguments, {
    void Function(double percent)? onProgress,
    CancelToken? cancelToken,
  }) async {
    invocations.add(List<String>.of(arguments));
    final output = arguments.isEmpty ? '' : arguments.last;
    final file = File(output);

    if (output.endsWith('.wav')) {
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(buildSineWav(), flush: true);
    } else if (output.endsWith('.srt')) {
      if (failSrt) {
        throw FfmpegBackendFailure(
          'Output #0 does not contain any stream\n[out#0/srt] Error opening output: Invalid argument',
        );
      }
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        '1\n00:00:00,000 --> 00:00:02,500\n你好，世界\n\n'
        '2\n00:00:02,500 --> 00:00:05,000\n第二句字幕\n',
        flush: true,
      );
    } else {
      // mp4 等二进制输出：写入任意字节，只要求文件存在。
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(List<int>.generate(128, (i) => i & 0xFF), flush: true);
    }
    onProgress?.call(1.0);
  }

  /// 生成 8000Hz / 单声道 / 16-bit / 0.3s、440Hz 正弦波的合法最小 WAV。
  static Uint8List buildSineWav() {
    const sampleRate = 8000;
    const sampleCount = 2400; // 0.3s
    const dataSize = sampleCount * 2;
    final bytes = Uint8List(44 + dataSize);
    final data = ByteData.sublistView(bytes);

    void tag(int offset, String value) {
      bytes.setRange(offset, offset + 4, value.codeUnits);
    }

    tag(0, 'RIFF');
    data.setUint32(4, 36 + dataSize, Endian.little);
    tag(8, 'WAVE');
    tag(12, 'fmt ');
    data.setUint32(16, 16, Endian.little); // fmt 块长度
    data.setUint16(20, 1, Endian.little); // PCM
    data.setUint16(22, 1, Endian.little); // 单声道
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(28, sampleRate * 2, Endian.little); // byteRate
    data.setUint16(32, 2, Endian.little); // blockAlign
    data.setUint16(34, 16, Endian.little); // bitsPerSample
    tag(36, 'data');
    data.setUint32(40, dataSize, Endian.little);

    for (var i = 0; i < sampleCount; i++) {
      final value = sin(2 * pi * 440 * i / sampleRate) * 0.6 * 32767;
      data.setInt16(44 + i * 2, value.round(), Endian.little);
    }
    return bytes;
  }
}

// ─────────────────────────── 小工具 ───────────────────────────

List<String>? _findCall(FakeBackend backend, String flag) {
  for (final args in backend.invocations) {
    if (args.contains(flag)) return args;
  }
  return null;
}

String _eventSummary(List<EngineProgress> events) {
  final parts = <String>[];
  for (final event in events) {
    if (event is Success) {
      parts.add('Success');
    } else if (event is Error) {
      parts.add('Error(${event.message})');
    } else if (event is Progress) {
      parts.add(event.percent.toStringAsFixed(2));
    }
  }
  return parts.join(', ');
}
