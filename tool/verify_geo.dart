/// OmniForge 跨类型引擎自检脚本（纯 Dart，无 Flutter）。
///
/// 运行：`/opt/dart/dart-sdk/bin/dart tool/verify_geo.dart`
///
/// 覆盖四组引擎：
/// - geo_render：手写 3 点 GPX → svg / png；
/// - embroidery：手写 3 针 DST → 读回 → 写 PES/DST 往返、dst→png 预览、png→dst；
/// - audio_midi：Fake 后端产出 440Hz 正弦 WAV → midi（MThd / note-on）；
/// - spectrogram：同一 Fake 后端 → png 频谱图尺寸与非纯色；
/// - NullFfmpegBackend 时两个音频引擎给出 PluginRequired。
///
/// 任一条断言失败即 exit(1)。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'package:omniforge/engine/engines/audio_midi_engine.dart';
import 'package:omniforge/engine/engines/audio_pcm_utils.dart';
import 'package:omniforge/engine/engines/embroidery_engine.dart';
import 'package:omniforge/engine/engines/ffmpeg_backend.dart';
import 'package:omniforge/engine/engines/geo_render_engine.dart';
import 'package:omniforge/engine/engines/spectrogram_engine.dart';
import 'package:omniforge/engine/engine_utils.dart';
import 'package:omniforge/engine/i_engine.dart';

int _checks = 0;
final List<String> _failures = <String>[];

void check(bool condition, String message) {
  _checks++;
  if (!condition) {
    _failures.add(message);
    stderr.writeln('  ✗ $message');
  }
}

void checkEq(Object? actual, Object? expected, String message) {
  check(actual == expected, '$message（期望 $expected，实际 $actual）');
}

void section(String title) => stdout.writeln('\n▶ $title');

/// 跑一次转换并返回全部进度事件；断言最终为 Success。
Future<List<EngineProgress>> runEngine(
  IEngine engine,
  EngineContext context, {
  required String label,
}) async {
  final events = <EngineProgress>[];
  await for (final event in engine.convert(context)) {
    events.add(event);
    if (event is Error) {
      throw StateError('$label 转换失败：${event.message}');
    }
  }
  check(events.last is Success, '$label 最终事件应为 Success');
  check(File(context.outputPath).existsSync(), '$label 应生成输出文件');
  return events;
}

/// 手写一份 3 针 DST（字节级按公开 DST 规范拼装，不复用引擎编码器）。
Uint8List buildHandmadeDst() {
  final header = Uint8List(512)..fillRange(0, 512, 0x20);
  final fields = <String>[
    'LA:${'VERIFY'.padRight(16)}\r',
    'ST:${'3'.padLeft(7)}\r',
    'CO:${'1'.padLeft(3)}\r',
    '+X:00010\r',
    '-X:00000\r',
    '+Y:00010\r',
    '-Y:00000\r',
    'AX:+00000\r',
    'AY:+00000\r',
    'MX:+00000\r',
    'MY:+00000\r',
    'PD:******\r',
  ];
  var at = 0;
  for (final field in fields) {
    for (final code in field.codeUnits) {
      header[at++] = code;
    }
  }
  header[at] = 0x1A;
  // 位域按公开 DST 规范手工推算：
  //  +10x = +9(bit2) +1(bit0)；+10y = +9(bit5) +1(bit7)；-10x = -9(bit3) -1(bit1)
  final records = <List<int>>[
    [0x05, 0x00, 0x03], // x += 10
    [0x50, 0x00, 0x03], // y += 10
    [0x0A, 0x00, 0x03], // x -= 10
    [0x00, 0x00, 0xF3], // 结束
  ];
  final out = BytesBuilder(copy: false)..add(header);
  for (final record in records) {
    out.add(record);
  }
  return out.toBytes();
}

class FakeWavBackend extends FfmpegBackend {
  FakeWavBackend({this.frequency = 440.0, this.amplitude = 0.5});

  final double frequency;
  final double amplitude;

  @override
  bool get isAvailable => true;

  @override
  String get name => 'FakeWavBackend';

  @override
  Future<void> execute(
    List<String> arguments, {
    void Function(double percent)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final outputPath = arguments.last;
    final samples = AudioPcmUtils.sineWave(
      frequency,
      amplitude: amplitude,
      sampleRate: 22050,
    );
    await writeFileBytes(
      outputPath,
      AudioPcmUtils.encodeWavPcm16(
        samples,
        sampleRate: 22050,
      ),
    );
    onProgress?.call(1.0);
  }

  @override
  Future<int?> probeDurationMs(String inputPath) async => 1000;
}

Future<void> verifyGeoRender(Directory work) async {
  section('geo_render：GPX → SVG / PNG');
  final input = File('${work.path}/track.gpx');
  await input.writeAsString('''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="verify" xmlns="http://www.topografix.com/GPX/1/1">
  <trk><name>demo</name><trkseg>
    <trkpt lat="31.2304" lon="121.4737"><ele>5</ele></trkpt>
    <trkpt lat="31.2400" lon="121.5000"><ele>8</ele></trkpt>
    <trkpt lat="31.2600" lon="121.4800"><ele>12</ele></trkpt>
  </trkseg></trk>
</gpx>
''');

  const engine = GeoRenderEngine();
  checkEq(engine.id, 'geo_render', '引擎 id');

  // 其余轨迹格式的最小解析校验（gpx 走完整链路，其余直接测解析器）
  const kml = '<kml><Document><Placemark><LineString><coordinates>'
      '121.4,31.2,0 121.5,31.25,0 121.55,31.3,0</coordinates>'
      '</LineString></Placemark></Document></kml>';
  checkEq(GeoRenderEngine.parseTrack(kml, 'kml').length, 3, 'KML 解析点数');
  const tcx = '<?xml version="1.0"?>'
      '<TrainingCenterDatabase><Activities><Activity><Lap><Track>'
      '<Trackpoint><Position><LatitudeDegrees>31.2</LatitudeDegrees>'
      '<LongitudeDegrees>121.4</LongitudeDegrees></Position></Trackpoint>'
      '<Trackpoint><Position><LatitudeDegrees>31.25</LatitudeDegrees>'
      '<LongitudeDegrees>121.5</LongitudeDegrees></Position></Trackpoint>'
      '</Track></Lap></Activity></Activities></TrainingCenterDatabase>';
  checkEq(GeoRenderEngine.parseTrack(tcx, 'tcx').length, 2, 'TCX 解析点数');
  const geojson = '{"type":"FeatureCollection","features":[{"type":"Feature",'
      '"geometry":{"type":"LineString","coordinates":'
      '[[121.4,31.2],[121.5,31.25],[121.55,31.3]]}}]}';
  checkEq(GeoRenderEngine.parseTrack(geojson, 'geojson').length, 3,
      'GeoJSON 解析点数');

  // ── SVG ──
  final svgPath = '${work.path}/track.svg';
  await runEngine(
    engine,
    EngineContext(
      inputPath: input.path,
      outputPath: svgPath,
      targetFormat: 'svg',
      sourceFormat: 'gpx',
      params: const {'width': 800, 'height': 600, 'padding': 40},
    ),
    label: 'GPX→SVG',
  );
  final svg = await File(svgPath).readAsString();
  check(svg.contains('<svg'), 'SVG 应包含 <svg');
  check(svg.contains('viewBox'), 'SVG 应包含 viewBox');
  check(svg.contains('<path'), 'SVG 应包含 <path');
  check(RegExp(r'<path[^>]*d="M').hasMatch(svg), 'SVG path 应以 M 开头');
  final pathData = RegExp(r'<path[^>]*d="([^"]+)"').firstMatch(svg)?.group(1);
  check(pathData != null && pathData.contains('L'), 'SVG path 应包含 L 线段');
  final numbers = RegExp(r'-?\d+(?:\.\d+)?')
      .allMatches(pathData ?? '')
      .map((match) => double.parse(match.group(0)!))
      .toList();
  check(numbers.length >= 6, 'SVG path 至少应有 3 个点（6 个数值）');
  final withinBounds = numbers.every((value) => value >= 0 && value <= 900);
  check(withinBounds, 'SVG 坐标应在画布范围内');
  stdout.writeln('  SVG 大小：${await File(svgPath).length()} 字节');

  // ── PNG ──
  final pngPath = '${work.path}/track.png';
  await runEngine(
    engine,
    EngineContext(
      inputPath: input.path,
      outputPath: pngPath,
      targetFormat: 'png',
      sourceFormat: 'gpx',
      params: const {'width': 800, 'height': 600, 'padding': 40},
    ),
    label: 'GPX→PNG',
  );
  final pngBytes = await File(pngPath).readAsBytes();
  final decoded = img.decodePng(pngBytes);
  check(decoded != null, 'PNG 应可解码');
  if (decoded != null) {
    checkEq(decoded.width, 800, 'PNG 宽度');
    checkEq(decoded.height, 600, 'PNG 高度');
    var colored = 0;
    for (var y = 0; y < decoded.height; y += 2) {
      for (var x = 0; x < decoded.width; x += 2) {
        final pixel = decoded.getPixel(x, y);
        if (pixel.r < 200 || pixel.g < 200 || pixel.b < 200) colored++;
      }
    }
    check(colored > 50, 'PNG 应为非空白（着色彩点 $colored）');
    stdout.writeln('  PNG 尺寸：${decoded.width}×${decoded.height}，'
        '非背景采样点：$colored');
  }
  stdout.writeln('  PNG 大小：${pngBytes.length} 字节');
}

Future<void> verifyEmbroidery(Directory work) async {
  section('embroidery：DST 读回 / PES·DST 往返 / dst→png / png→dst');
  const engine = EmbroideryEngine();
  checkEq(engine.id, 'embroidery', '引擎 id');

  // ── 手写 DST → 读回 ──
  final handmade = buildHandmadeDst();
  final parsed = EmbroideryEngine.decodeDst(handmade);
  checkEq(parsed.stitches.length, 3, '手写 DST 应读回 3 针');
  final expected = <List<int>>[
    [10, 0],
    [10, 10],
    [0, 10],
  ];
  for (var i = 0; i < expected.length && i < parsed.stitches.length; i++) {
    final stitch = parsed.stitches[i];
    check(
      stitch.x == expected[i][0] && stitch.y == expected[i][1],
      '第 ${i + 1} 针坐标应为 (${expected[i][0]}, ${expected[i][1]})，'
      '实际 (${stitch.x}, ${stitch.y})',
    );
  }
  stdout.writeln('  手写 DST 读回：${parsed.stitches}');

  // ── DST / PES 往返（含跳针与换色）──
  final pattern = EmbroideryPattern(
    name: 'roundtrip',
    colors: <int>[0xE60000, 0x0000E6],
    stitches: const <Stitch>[
      Stitch(0, 0),
      Stitch(100, 50),
      Stitch(200, 100, type: StitchType.jump),
      Stitch(210, 110),
      Stitch(210, 110, type: StitchType.colorChange),
      Stitch(240, 140),
    ],
  );

  final dstRoundTrip = EmbroideryEngine.decodeDst(
    EmbroideryEngine.encodeDst(pattern),
  );
  checkEq(dstRoundTrip.stitches.length, pattern.stitches.length,
      'DST 往返针数应一致');
  check(
    dstRoundTrip.stitches.any((stitch) => stitch.type == StitchType.jump),
    'DST 往返应保留跳针',
  );
  check(
    dstRoundTrip.stitches.any((stitch) => stitch.type == StitchType.colorChange),
    'DST 往返应保留换色',
  );

  final pesBytes = EmbroideryEngine.encodePes(pattern);
  final pesRoundTrip = EmbroideryEngine.decodePes(pesBytes);
  check(pesBytes.length > 512, 'PES 输出应大于 512 字节');
  checkEq(pesRoundTrip.stitches.length, pattern.stitches.length,
      'PES 往返针数应一致');
  checkEq(pesRoundTrip.name, 'roundtrip', 'PES 往返标签');
  final visibleDst = pattern.stitches
      .where((stitch) =>
          stitch.type == StitchType.stitch || stitch.type == StitchType.jump)
      .toList();
  final visiblePes = pesRoundTrip.stitches
      .where((stitch) =>
          stitch.type == StitchType.stitch || stitch.type == StitchType.jump)
      .toList();
  var coordinatesMatch = visibleDst.length == visiblePes.length;
  for (var i = 0; coordinatesMatch && i < visibleDst.length; i++) {
    coordinatesMatch = visibleDst[i].x == visiblePes[i].x &&
        visibleDst[i].y == visiblePes[i].y;
  }
  check(coordinatesMatch, 'PES 往返可见针迹坐标应一致');
  stdout.writeln('  DST 往返针数：${dstRoundTrip.stitches.length}，'
      'PES 往返针数：${pesRoundTrip.stitches.length}，'
      'PES 大小：${pesBytes.length} 字节');

  // ── JEF 往返 ──
  final jefBytes = EmbroideryEngine.encodeJef(pattern);
  final jefRoundTrip = EmbroideryEngine.decodeJef(jefBytes);
  checkEq(jefRoundTrip.stitches.length, pattern.stitches.length,
      'JEF 往返针数应一致');
  stdout.writeln('  JEF 往返针数：${jefRoundTrip.stitches.length}，'
      'JEF 大小：${jefBytes.length} 字节');

  // ── dst → png 预览（走完整引擎链路）──
  final dstFile = File('${work.path}/pattern.dst');
  await dstFile.writeAsBytes(EmbroideryEngine.encodeDst(pattern));
  final previewPath = '${work.path}/pattern_preview.png';
  await runEngine(
    engine,
    EngineContext(
      inputPath: dstFile.path,
      outputPath: previewPath,
      targetFormat: 'png',
      sourceFormat: 'dst',
      params: const {'scale': 2.0, 'margin': 8},
    ),
    label: 'DST→PNG',
  );
  final preview = img.decodePng(await File(previewPath).readAsBytes());
  check(preview != null, '预览 PNG 应可解码');
  if (preview != null) {
    check(preview.width > 8 && preview.height > 8, '预览图尺寸应大于 8×8');
    var colored = 0;
    for (var y = 0; y < preview.height; y++) {
      for (var x = 0; x < preview.width; x++) {
        final pixel = preview.getPixel(x, y);
        if (pixel.r < 240 || pixel.g < 240 || pixel.b < 240) colored++;
      }
    }
    check(colored > 0, '预览图应包含非背景像素（$colored）');
    stdout.writeln('  预览图尺寸：${preview.width}×${preview.height}，'
        '非背景像素：$colored');
  }

  // ── png → dst（位图转针迹，走完整引擎链路）──
  final sourceImage = img.Image(width: 96, height: 64, numChannels: 3);
  img.fill(sourceImage, color: img.ColorRgb8(255, 255, 255));
  for (var y = 16; y < 48; y++) {
    for (var x = 8; x < 88; x++) {
      if (y >= 24 && y < 40 && x >= 20 && x < 76) {
        sourceImage.setPixelRgb(x, y, 0, 0, 0);
      }
    }
  }
  final sourcePng = File('${work.path}/design.png');
  await sourcePng.writeAsBytes(img.encodePng(sourceImage));
  final outputDstPath = '${work.path}/design.dst';
  await runEngine(
    engine,
    EngineContext(
      inputPath: sourcePng.path,
      outputPath: outputDstPath,
      targetFormat: 'dst',
      sourceFormat: 'png',
      params: const {'threshold': 128, 'max_stitches': 20000},
    ),
    label: 'PNG→DST',
  );
  final outputDst = await File(outputDstPath).readAsBytes();
  check(outputDst.length > 512, 'PNG→DST 输出应大于 512 字节');
  check(
    String.fromCharCodes(outputDst.sublist(0, 3)) == 'LA:',
    'PNG→DST 输出应以 LA: 头开始',
  );
  final generated = EmbroideryEngine.decodeDst(outputDst);
  check(generated.stitches.isNotEmpty, 'PNG→DST 应能读回针迹');
  stdout.writeln('  PNG→DST 大小：${outputDst.length} 字节，'
      '生成针迹：${generated.stitches.length}');
}

Future<void> verifyAudioMidi(Directory work) async {
  section('audio_midi：正弦 440Hz → MIDI');
  final engine = AudioMidiEngine(backend: FakeWavBackend());
  checkEq(engine.id, 'audio_midi', '引擎 id');
  final input = File('${work.path}/tone.bin');
  await input.writeAsBytes(Uint8List.fromList(List<int>.generate(64, (i) => i)));

  final midiPath = '${work.path}/tone.mid';
  await runEngine(
    engine,
    EngineContext(
      inputPath: input.path,
      outputPath: midiPath,
      targetFormat: 'midi',
      params: const {'silence': 0.01, 'min_note_ms': 100, 'bpm': 120},
    ),
    label: 'AUDIO→MIDI',
  );
  final midi = await File(midiPath).readAsBytes();
  final magic = String.fromCharCodes(midi.sublist(0, 4));
  checkEq(magic, 'MThd', 'MIDI 魔数');
  check(midi.length > 32, 'MIDI 文件应非空');
  checkEq(midi[12], 0x01, 'MIDI division 高字节（480 PPQ）');
  checkEq(midi[13], 0xE0, 'MIDI division 低字节（480 PPQ）');
  checkEq(String.fromCharCodes(midi.sublist(14, 18)), 'MTrk', 'MIDI 轨道块');
  final trackLength = (midi[18] << 24) |
      (midi[19] << 16) |
      (midi[20] << 8) |
      midi[21];
  checkEq(trackLength, midi.length - 22, 'MIDI 轨道长度一致');
  final hasTempo = _containsSequence(midi, <int>[0xFF, 0x51, 0x03]);
  check(hasTempo, 'MIDI 应包含 tempo meta 事件 (FF 51 03)');
  final hasNoteOn = _containsSequence(midi, <int>[0x90, 69, 100]);
  check(hasNoteOn, 'MIDI 应包含 A4(69) 的 note-on 事件');
  final hasTrackEnd = _containsSequence(midi, <int>[0xFF, 0x2F, 0x00]);
  check(hasTrackEnd, 'MIDI 应包含文件尾 (FF 2F 00)');
  // 解析音符数
  final notes = _midiNoteCount(midi);
  check(notes > 0, 'MIDI 应至少包含 1 个音符');
  stdout.writeln('  MIDI 大小：${midi.length} 字节，音符数：$notes，'
      '魔数：$magic');

  // 音高检测正确性：440Hz 应映射到 69
  final pcm = AudioPcm(
    AudioPcmUtils.sineWave(440, sampleRate: 22050),
    22050,
  );
  final detected = AudioMidiEngine.extractNotes(pcm, minNoteMs: 100, bpm: 120);
  check(detected.isNotEmpty, '应检测到至少 1 个音符');
  if (detected.isNotEmpty) {
    checkEq(detected.first.midiNote, 69, '440Hz 应检测为 MIDI 69');
    stdout.writeln('  检测音符：$detected');
  }

  // 无 ffmpeg 后端 → PluginRequired
  const nullEngine = AudioMidiEngine();
  final events = await _drain((context) => nullEngine.convert(context),
      EngineContext(
        inputPath: input.path,
        outputPath: '${work.path}/tone_null.mid',
        targetFormat: 'midi',
      ));
  final plugin = events.whereType<PluginRequired>().toList();
  check(plugin.isNotEmpty, 'NullFfmpegBackend 应产生 PluginRequired');
  if (plugin.isNotEmpty) {
    checkEq(plugin.first.pluginId, 'ffmpeg', 'PluginRequired 插件 id');
  }
}

Future<void> verifySpectrogram(Directory work) async {
  section('spectrogram：正弦 440Hz → PNG 频谱图');
  final engine = SpectrogramEngine(backend: FakeWavBackend());
  checkEq(engine.id, 'spectrogram', '引擎 id');
  final input = File('${work.path}/tone2.bin');
  await input.writeAsBytes(Uint8List.fromList(List<int>.generate(64, (i) => i)));

  final pngPath = '${work.path}/spectrogram.png';
  await runEngine(
    engine,
    EngineContext(
      inputPath: input.path,
      outputPath: pngPath,
      targetFormat: 'png',
      params: const {'width': 640, 'height': 320},
    ),
    label: 'AUDIO→PNG',
  );
  final bytes = await File(pngPath).readAsBytes();
  final image = img.decodePng(bytes);
  check(image != null, '频谱图 PNG 应可解码');
  if (image != null) {
    checkEq(image.width, 640, '频谱图宽度');
    checkEq(image.height, 320, '频谱图高度');
    final colors = <int>{};
    var maxLuminance = 0.0;
    for (var y = 0; y < image.height; y += 4) {
      for (var x = 0; x < image.width; x += 4) {
        final pixel = image.getPixel(x, y);
        colors.add((pixel.r.toInt() << 16) |
            (pixel.g.toInt() << 8) |
            pixel.b.toInt());
        final luminance = 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
        if (luminance > maxLuminance) maxLuminance = luminance;
      }
    }
    check(colors.length >= 3, '频谱图应为多色（${colors.length} 种采样色）');
    check(maxLuminance > 120, '频谱图应有明显能量峰（最大亮度 $maxLuminance）');
    stdout.writeln('  频谱图：${image.width}×${image.height}，'
        '采样色数：${colors.length}，最大亮度：${maxLuminance.toStringAsFixed(1)}');
  }
  stdout.writeln('  频谱图大小：${bytes.length} 字节');

  // jpg 输出
  final jpgPath = '${work.path}/spectrogram.jpg';
  await runEngine(
    engine,
    EngineContext(
      inputPath: input.path,
      outputPath: jpgPath,
      targetFormat: 'jpg',
      params: const {'width': 320, 'height': 160, 'quality': 80},
    ),
    label: 'AUDIO→JPG',
  );
  final jpg = img.decodeJpg(await File(jpgPath).readAsBytes());
  check(jpg != null, 'JPG 应可解码');
  if (jpg != null) {
    checkEq(jpg.width, 320, 'JPG 宽度');
  }
  stdout.writeln('  JPG 大小：${await File(jpgPath).length()} 字节');

  // 无 ffmpeg 后端 → PluginRequired
  const nullEngine = SpectrogramEngine();
  final events = await _drain((context) => nullEngine.convert(context),
      EngineContext(
        inputPath: input.path,
        outputPath: '${work.path}/spectrogram_null.png',
        targetFormat: 'png',
      ));
  final plugin = events.whereType<PluginRequired>().toList();
  check(plugin.isNotEmpty, 'NullFfmpegBackend 应产生 PluginRequired');
  if (plugin.isNotEmpty) {
    checkEq(plugin.first.pluginId, 'ffmpeg', 'PluginRequired 插件 id');
  }
}

Future<List<EngineProgress>> _drain(
  Stream<EngineProgress> Function(EngineContext context) run,
  EngineContext context,
) async {
  final events = <EngineProgress>[];
  await for (final event in run(context)) {
    events.add(event);
  }
  return events;
}

bool _containsSequence(Uint8List bytes, List<int> needle) {
  for (var i = 0; i + needle.length <= bytes.length; i++) {
    var matched = true;
    for (var j = 0; j < needle.length; j++) {
      if (bytes[i + j] != needle[j]) {
        matched = false;
        break;
      }
    }
    if (matched) return true;
  }
  return false;
}

/// 统计 MIDI 中的 note-on 事件数（velocity > 0）。
int _midiNoteCount(Uint8List bytes) {
  var count = 0;
  for (var i = 0; i + 2 < bytes.length; i++) {
    if (bytes[i] == 0x90 && bytes[i + 2] > 0) count++;
  }
  return count;
}

Future<void> main() async {
  stdout.writeln('OmniForge 跨类型引擎自检');
  final work = await Directory.systemTemp.createTemp('omniforge_verify_');
  stdout.writeln('工作目录：${work.path}');
  try {
    await verifyGeoRender(work);
    await verifyEmbroidery(work);
    await verifyAudioMidi(work);
    await verifySpectrogram(work);
  } on Object catch (error, stackTrace) {
    stderr
      ..writeln('\n未捕获错误：$error')
      ..writeln(stackTrace);
    _failures.add('未捕获错误：$error');
  } finally {
    try {
      await work.delete(recursive: true);
    } catch (_) {
      // 清理失败不影响结论
    }
  }

  stdout.writeln('\n断言总数：$_checks，失败：${_failures.length}');
  if (_failures.isNotEmpty) {
    stderr.writeln('自检失败：');
    for (final failure in _failures) {
      stderr.writeln('  - $failure');
    }
    exit(1);
  }
  stdout.writeln('✓ 全部自检通过');
}
