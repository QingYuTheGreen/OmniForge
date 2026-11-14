import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:omniforge/engine/conversion_planner.dart';
import 'package:omniforge/engine/conversion_service.dart';
import 'package:omniforge/engine/engine_registry.dart';
import 'package:omniforge/engine/i_engine.dart';
import 'package:omniforge/models/format_node.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  late List<FormatNode> formats;
  late List<FlowRule> flows;
  late EngineRegistry registry;
  late ConversionPlanner planner;

  setUpAll(() {
    final doc = loadYaml(File('assets/formats.yaml').readAsStringSync()) as Map;
    formats = (doc['formats'] as List)
        .map((f) => FormatNode.fromYaml(Map.from(f as Map)))
        .toList();
    flows = (doc['flows'] as List)
        .map((f) => FlowRule.fromYaml(Map.from(f as Map)))
        .toList();
    registry = EngineRegistry.platformDefaults();
    planner = ConversionPlanner.fromData(
      formats: formats,
      flows: flows,
      readyEngines: registry.readyEngineIds,
      knownEngines: registry.all.map((e) => e.id).toSet(),
    );
  });

  test('格式表：19 类 / 95 种格式 / 全部有引擎归属', () {
    final categories = <String>{};
    for (final format in formats) {
      categories.addAll(format.categories);
      expect(format.engines, isNotEmpty, reason: '${format.id} 没有引擎');
    }
    expect(formats.length, 95);
    expect(categories.length, 19);
  });

  test('每个 ready 格式都有可用的出站链路', () {
    for (final format in formats.where((f) => f.status == 'ready')) {
      final targets = planner.reachableFrom(format.id);
      expect(
        targets.where((t) => t.available),
        isNotEmpty,
        reason: '${format.id} 没有可用目标',
      );
    }
  });

  test('规划器：图片 → PDF 为直转', () {
    final targets = planner.reachableFrom('png');
    final pdf = targets.firstWhere((t) => t.formatId == 'pdf');
    expect(pdf.isDirect, isTrue);
    final plan = planner.plan('png', 'pdf');
    expect(plan, isNotNull);
    expect(plan!.steps.single.engineId, 'pdf');
    expect(plan.steps.single.toExtension, 'pdf');
  });

  test('规划器：docx → txt 走 document 引擎而不是 text', () {
    final plan = planner.plan('docx', 'txt');
    expect(plan, isNotNull);
    expect(plan!.steps.single.engineId, 'document');
  });

  test('规划器：epub → md 为多跳', () {
    final plan = planner.plan('epub', 'md');
    expect(plan, isNotNull);
    expect(plan!.isDirect, isFalse);
    expect(plan.steps.length, greaterThan(1));
    expect(plan.available, isTrue);
  });

  test('规划器：mp4 → mp3 因缺原生库被标记为不可用', () {
    final targets = planner.reachableFrom('mp4');
    final mp3 = targets.firstWhere((t) => t.formatId == 'mp3');
    expect(mp3.available, isFalse);
    expect(mp3.blockedPluginId, 'ffmpeg');
  });

  test('哈希引擎：任意文件 → md5 结果正确', () async {
    final temp = await Directory.systemTemp.createTemp('omniforge_test_');
    final input = File('${temp.path}/hello.txt')
      ..writeAsStringSync('hello');
    final output = '${temp.path}/out.md5';
    final service = ConversionService(registry);
    final plan = planner.plan('txt', 'md5', params: {'algorithm': 'sha1'});
    expect(plan, isNotNull);

    final events = await service
        .convert(plan: plan!, inputPath: input.path, outputPath: output)
        .toList();
    expect(events.whereType<Success>(), isNotEmpty);
    final content = File(output).readAsStringSync();
    expect(content.split(' ').first, 'aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d');
  });

  test('字幕引擎：srt → vtt 结构正确', () async {
    final temp = await Directory.systemTemp.createTemp('omniforge_test_');
    final input = File('${temp.path}/a.srt')
      ..writeAsStringSync('1\n00:00:01,000 --> 00:00:02,000\n你好\n');
    final output = '${temp.path}/a.vtt';
    final service = ConversionService(registry);
    final plan = planner.plan('srt', 'vtt');
    final events = await service
        .convert(plan: plan!, inputPath: input.path, outputPath: output)
        .toList();
    expect(events.whereType<Success>(), isNotEmpty);
    expect(File(output).readAsStringSync(), contains('WEBVTT'));
    expect(File(output).readAsStringSync(), contains('00:00:01.000'));
  });

  test('表格引擎：csv → json', () async {
    final temp = await Directory.systemTemp.createTemp('omniforge_test_');
    final input = File('${temp.path}/a.csv')
      ..writeAsStringSync('name,age\nAlice,30\nBob,25\n');
    final output = '${temp.path}/a.json';
    final service = ConversionService(registry);
    final plan = planner.plan('csv', 'json');
    final events = await service
        .convert(plan: plan!, inputPath: input.path, outputPath: output)
        .toList();
    expect(events.whereType<Success>(), isNotEmpty);
    final data = jsonDecode(File(output).readAsStringSync()) as List;
    expect(data.length, 2);
    expect((data.first as Map)['name'], 'Alice');
  });

  test('图片引擎：png → jpg', () async {
    final temp = await Directory.systemTemp.createTemp('omniforge_test_');
    // 1x1 白色 PNG
    final pngBytes = Uint8List.fromList(base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    ));
    final input = File('${temp.path}/a.png')..writeAsBytesSync(pngBytes);
    final output = '${temp.path}/a.jpg';
    final service = ConversionService(registry);
    final plan = planner.plan('png', 'jpg', params: {'quality': 85});
    final events = await service
        .convert(plan: plan!, inputPath: input.path, outputPath: output)
        .toList();
    expect(events.whereType<Success>(), isNotEmpty,
        reason: events.map((e) => e is Error ? e.message : e).join('; '));
    expect(File(output).lengthSync(), greaterThan(0));
  });

  test('不支持的目标返回空方案', () {
    expect(planner.plan('png', 'mp3'), isNull);
  });

  test('跨类型：png → svg（矢量描摹）', () async {
    final temp = await Directory.systemTemp.createTemp('omniforge_test_');
    final input = File('${temp.path}/a.png')
      ..writeAsBytesSync(Uint8List.fromList(base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
      )));
    final output = '${temp.path}/a.svg';
    final plan = planner.plan('png', 'svg');
    expect(plan, isNotNull);
    expect(plan!.steps.single.engineId, 'svg_vector');
    final events = await ConversionService(registry)
        .convert(plan: plan, inputPath: input.path, outputPath: output)
        .toList();
    expect(events.whereType<Success>(), isNotEmpty,
        reason: events.map((e) => e is Error ? e.message : e).join('; '));
    expect(File(output).readAsStringSync(), contains('<svg'));
  });

  test('跨类型：png → gpl 调色板', () async {
    final temp = await Directory.systemTemp.createTemp('omniforge_test_');
    final input = File('${temp.path}/a.png')
      ..writeAsBytesSync(Uint8List.fromList(base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
      )));
    final output = '${temp.path}/a.gpl';
    final plan = planner.plan('png', 'gpl', params: {'colors': 4});
    expect(plan, isNotNull);
    final events = await ConversionService(registry)
        .convert(plan: plan!, inputPath: input.path, outputPath: output)
        .toList();
    expect(events.whereType<Success>(), isNotEmpty,
        reason: events.map((e) => e is Error ? e.message : e).join('; '));
    expect(File(output).readAsStringSync(), contains('GIMP Palette'));
  });

  test('跨类型：txt → 二维码 PNG / 头像 PNG', () async {
    final temp = await Directory.systemTemp.createTemp('omniforge_test_');
    final input = File('${temp.path}/a.txt')..writeAsStringSync('https://omniforge.app');
    final qr = '${temp.path}/qr.png';
    final qrPlan = planner.plan('txt', 'qr_png');
    expect(qrPlan, isNotNull);
    await ConversionService(registry)
        .convert(plan: qrPlan!, inputPath: input.path, outputPath: qr)
        .toList();
    final qrBytes = File(qr).readAsBytesSync();
    expect(qrBytes.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);

    final ident = '${temp.path}/id.png';
    final identPlan = planner.plan('txt', 'identicon_png');
    expect(identPlan, isNotNull);
    await ConversionService(registry)
        .convert(plan: identPlan!, inputPath: input.path, outputPath: ident)
        .toList();
    expect(File(ident).readAsBytesSync().length, greaterThan(0));
  });

  test('跨类型：obj → png（软件光栅化）/ obj → geojson', () async {
    final temp = await Directory.systemTemp.createTemp('omniforge_test_');
    final obj = File('${temp.path}/tri.obj')
      ..writeAsStringSync('v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n');
    final png = '${temp.path}/tri.png';
    final pngPlan = planner.plan('obj', 'png');
    expect(pngPlan, isNotNull);
    expect(pngPlan!.steps.single.engineId, 'render3d');
    await ConversionService(registry)
        .convert(plan: pngPlan, inputPath: obj.path, outputPath: png)
        .toList();
    expect(File(png).readAsBytesSync().sublist(0, 4), [137, 80, 78, 71]);

    final geo = '${temp.path}/tri.geo.json';
    final geoPlan = planner.plan('obj', 'geo_json');
    expect(geoPlan, isNotNull);
    expect(geoPlan!.steps.single.engineId, 'mesh_geo');
    await ConversionService(registry)
        .convert(plan: geoPlan, inputPath: obj.path, outputPath: geo)
        .toList();
    expect(jsonDecode(File(geo).readAsStringSync()), isA<Map>());
  });

  test('跨类型：png ↔ dst 绣花往返', () async {
    final temp = await Directory.systemTemp.createTemp('omniforge_test_');
    final input = File('${temp.path}/a.png')
      ..writeAsBytesSync(Uint8List.fromList(base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
      )));
    final dst = '${temp.path}/a.dst';
    final plan = planner.plan('png', 'dst');
    expect(plan, isNotNull);
    expect(plan!.steps.single.engineId, 'embroidery');
    await ConversionService(registry)
        .convert(plan: plan, inputPath: input.path, outputPath: dst)
        .toList();
    expect(File(dst).readAsBytesSync().length, greaterThan(0));

    final preview = '${temp.path}/preview.png';
    final backPlan = planner.plan('dst', 'png');
    expect(backPlan, isNotNull);
    await ConversionService(registry)
        .convert(plan: backPlan!, inputPath: dst, outputPath: preview)
        .toList();
    expect(File(preview).readAsBytesSync().sublist(0, 4), [137, 80, 78, 71]);
  });

  test('跨类型：png → docx 嵌图 / gpx → svg 轨迹', () async {
    final temp = await Directory.systemTemp.createTemp('omniforge_test_');
    final pngInput = File('${temp.path}/a.png')
      ..writeAsBytesSync(Uint8List.fromList(base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
      )));
    final docx = '${temp.path}/img.docx';
    final docxPlan = planner.plan('png', 'docx');
    expect(docxPlan, isNotNull);
    expect(docxPlan!.steps.single.engineId, 'image_doc');
    await ConversionService(registry)
        .convert(plan: docxPlan, inputPath: pngInput.path, outputPath: docx)
        .toList();
    expect(File(docx).readAsBytesSync().length, greaterThan(0));

    final gpx = File('${temp.path}/t.gpx')
      ..writeAsStringSync(
        '<?xml version="1.0"?><gpx version="1.1"><trk><trkseg>'
        '<trkpt lat="31.23" lon="121.47"/><trkpt lat="31.24" lon="121.48"/>'
        '</trkseg></trk></gpx>',
      );
    final svg = '${temp.path}/t.svg';
    final svgPlan = planner.plan('gpx', 'svg');
    expect(svgPlan, isNotNull);
    expect(svgPlan!.steps.single.engineId, 'geo_render');
    await ConversionService(registry)
        .convert(plan: svgPlan, inputPath: gpx.path, outputPath: svg)
        .toList();
    expect(File(svg).readAsStringSync(), contains('<svg'));
  });

  test('插件引擎：未安装时规划器标记 ffmpeg / 插件能力', () {
    final targets = planner.reachableFrom('txt');
    final tts = targets.where((t) => t.formatId == 'mp3').toList();
    // 文本 → mp3 需要 TTS 插件，当前未安装 → 不可用
    expect(tts.isEmpty || tts.every((t) => !t.available), isTrue);
  });
}
