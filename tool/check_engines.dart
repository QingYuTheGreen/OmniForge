// 转换链路自检：不依赖 Flutter，验证「格式表 → 规划器 → 引擎」是否闭环。
//
// 用法：dart run tool/check_engines.dart
import 'dart:io';

import 'package:omniforge/engine/conversion_planner.dart';
import 'package:omniforge/engine/conversion_service.dart';
import 'package:omniforge/engine/engine_registry.dart';
import 'package:omniforge/engine/i_engine.dart';
import 'package:omniforge/models/format_node.dart';
import 'package:yaml/yaml.dart';

void main() async {
  final yamlText = File('assets/formats.yaml').readAsStringSync();
  final root = loadYaml(yamlText) as Map;
  final formats = (root['formats'] as List)
      .map((e) => FormatNode.fromYaml(Map.from(e as Map)))
      .toList();
  final flows = (root['flows'] as List)
      .map((e) => FlowRule.fromYaml(Map.from(e as Map)))
      .toList();

  final registry = EngineRegistry.platformDefaults();
  final planner = ConversionPlanner.fromData(
    formats: formats,
    flows: flows,
    readyEngines: registry.readyEngineIds,
    knownEngines: registry.all.map((e) => e.id).toSet(),
  );

  var problems = 0;

  // 1. 每个 format 的 engines 必须都在注册表里
  for (final format in formats) {
    for (final engine in format.engines) {
      if (!registry.contains(engine)) {
        stderr.writeln('✗ 格式 ${format.id} 引用了未注册的引擎 $engine');
        problems++;
      }
    }
  }

  // 2. 每种 ready 格式都应至少有一个可达目标
  for (final format in formats.where((f) => f.status == 'ready')) {
    final targets = planner.reachableFrom(format.id);
    if (targets.isEmpty) {
      stderr.writeln('✗ ready 格式 ${format.id} 没有任何可达目标');
      problems++;
    }
  }

  print('引擎：${registry.all.length} 个，可直接运行 ${registry.readyEngineIds.length} 个');

  // 3. 抽样打印跨类链路
  const samples = [
    ('mp4', 'mp3'),
    ('png', 'pdf'),
    ('docx', 'txt'),
    ('epub', 'md'),
    ('pdf', 'txt'),
    ('md', 'html'),
    ('xlsx', 'json'),
    ('csv', 'xlsx'),
    ('obj', 'stl'),
    ('obj', 'ply'),
    ('ase', 'json'),
    ('txt', 'md5'),
    ('srt', 'ass'),
    ('gpx', 'kml'),
    ('zip', 'tar_gz'),
    ('mcworld', 'mcpack'),
  ];
  for (final (source, target) in samples) {
    final plan = planner.plan(source, target);
    if (plan == null) {
      stderr.writeln('✗ 无法规划 $source → $target');
      problems++;
      continue;
    }
    final flag = plan.available ? '✓' : '△';
    print('$flag ${plan.describe}');
  }

  // 4. 真实转换冒烟：生成临时文件 → 引擎执行 → 检查输出
  final temp = await Directory.systemTemp.createTemp('omniforge_smoke_');
  final service = ConversionService(registry);
  try {
    final cases = <(String, String, List<int> Function()?, String)>[
      ('srt', 'vtt', null, 'vtt'),
      ('gpx', 'kml', null, 'gpx'),
      ('md', 'html', null, 'html'),
      ('csv', 'json', null, 'json'),
      ('txt', 'md5', null, 'md5'),
      ('ply', 'off', null, 'off'),
    ];
    for (final (source, target, content, extension) in cases) {
      final input = File('${temp.path}/input.$source');
      final output = '${temp.path}/out_$target.$extension';
      final plan = planner.plan(source, target);
      if (plan == null || !plan.available) {
        continue;
      }
      final data = content?.call() ??
          _sampleFor(source);
      if (data == null) continue;
      await input.writeAsBytes(data);
      final events = await service
          .convert(
            plan: plan,
            inputPath: input.path,
            outputPath: output,
          )
          .toList();
      final ok = events.whereType<Success>().isNotEmpty &&
          File(output).existsSync() &&
          File(output).lengthSync() > 0;
      if (!ok) {
        stderr.writeln('✗ 转换 $source → $target 失败：$events');
        problems++;
      } else {
        print('✓ 真实转换 $source → $target (${File(output).lengthSync()} B)');
      }
    }
  } finally {
    await temp.delete(recursive: true);
  }

  if (problems > 0) {
    stderr.writeln('自检失败：$problems 个问题');
    exitCode = 1;
  } else {
    print('✓ 引擎与链路自检通过');
  }
}

List<int>? _sampleFor(String format) {
  switch (format) {
    case 'gpx':
      return '''<?xml version="1.0"?>
<gpx version="1.1" creator="OmniForge"><trk><trkseg>
<trkpt lat="31.23" lon="121.47"><ele>4.0</ele></trkpt>
<trkpt lat="31.24" lon="121.48"><ele>5.0</ele></trkpt>
</trkseg></trk></gpx>'''
          .codeUnits;
    case 'md':
      return '# 标题\n\n这是 **OmniForge** 的转换测试。\n'.codeUnits;
    case 'csv':
      return 'name,value\nalpha,1\nbeta,2\n'.codeUnits;
    case 'txt':
      return 'OmniForge 离线转换测试\n'.codeUnits;
    case 'ply':
      return 'ply\nformat ascii 1.0\nelement vertex 3\nproperty float x\nproperty float y\nproperty float z\nelement face 1\nproperty list uchar int vertex_indices\nend_header\n0 0 0\n1 0 0\n0 1 0\n3 0 1 2\n'
          .codeUnits;
    case 'srt':
      return '1\n00:00:01,000 --> 00:00:02,000\n你好\n'.codeUnits;
    default:
      return null;
  }
}
