// 跨类型转换自检：验证 v0.8.0 新增引擎与链路（不依赖 flutter test）。
//
// 用法：dart run tool/check_crosstype.dart
// 失败时退出码为 1。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:omniforge/engine/conversion_planner.dart';
import 'package:omniforge/engine/conversion_service.dart';
import 'package:omniforge/engine/engine_registry.dart';
import 'package:omniforge/engine/plugin/native_plugin_registry.dart';
import 'package:omniforge/engine/i_engine.dart';
import 'package:omniforge/models/format_node.dart';
import 'package:yaml/yaml.dart';

const String _png1x1 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

int _failures = 0;

void _check(String label, bool ok, [String detail = '']) {
  if (ok) {
    stdout.writeln('✓ $label${detail.isEmpty ? '' : '（$detail）'}');
  } else {
    _failures++;
    stderr.writeln('✗ $label${detail.isEmpty ? '' : '（$detail）'}');
  }
}

Future<(bool, String)> _run(
  ConversionService service,
  ConversionPlanner planner,
  String source,
  String target,
  String inputPath,
  String outputPath, {
  Map<String, dynamic> params = const {},
}) async {
  final plan = planner.plan(source, target, params: params);
  if (plan == null) return (false, '无可用方案');
  final events = await service
      .convert(plan: plan, inputPath: inputPath, outputPath: outputPath)
      .toList();
  final success = events.whereType<Success>().isNotEmpty;
  if (success) {
    final file = File(outputPath);
    if (!file.existsSync()) return (false, '输出文件不存在');
    return (true, '${file.lengthSync()} B');
  }
  final error = events.whereType<Error>().firstOrNull;
  final plugin = events.whereType<PluginRequired>().firstOrNull;
  return (
    false,
    error?.message ??
        (plugin != null ? '需要插件 ${plugin.pluginId}' : '未知失败'),
  );
}

Future<void> main() async {
  final doc = loadYaml(File('assets/formats.yaml').readAsStringSync()) as Map;
  final formats = (doc['formats'] as List)
      .map((f) => FormatNode.fromYaml(Map.from(f as Map)))
      .toList();
  final flows = (doc['flows'] as List)
      .map((f) => FlowRule.fromYaml(Map.from(f as Map)))
      .toList();
  // 注入一个空的插件目录：插件引擎会注册但状态为「未安装」，
  // 用于验证插件能力的链路可见性与诚实提示。
  final pluginDir = await Directory.systemTemp.createTemp('omniforge_plugins_');
  final registry = EngineRegistry.platformDefaults(
    plugins: NativePluginRegistry(installDir: pluginDir),
  );
  final planner = ConversionPlanner.fromData(
    formats: formats,
    flows: flows,
    readyEngines: registry.readyEngineIds,
    knownEngines: registry.all.map((e) => e.id).toSet(),
  );
  final service = ConversionService(registry);
  final temp = await Directory.systemTemp.createTemp('omniforge_cross_');

  try {
    final png = File('${temp.path}/a.png')
      ..writeAsBytesSync(Uint8List.fromList(base64Decode(_png1x1)));
    final obj = File('${temp.path}/tri.obj')
      ..writeAsStringSync('v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n');
    final gpx = File('${temp.path}/t.gpx')
      ..writeAsStringSync(
        '<?xml version="1.0"?><gpx version="1.1"><trk><trkseg>'
        '<trkpt lat="31.23" lon="121.47"/><trkpt lat="31.24" lon="121.48"/>'
        '</trkseg></trk></gpx>',
      );
    final txt = File('${temp.path}/a.txt')..writeAsStringSync('OmniForge 万能锻造炉');

    // 图片侧
    var r = await _run(service, planner, 'png', 'svg', png.path, '${temp.path}/a.svg');
    _check('png → svg（矢量描摹）', r.$1 && File('${temp.path}/a.svg').readAsStringSync().contains('<svg'), r.$2);

    r = await _run(service, planner, 'png', 'gpl', png.path, '${temp.path}/a.gpl', params: {'colors': 4});
    _check('png → gpl（调色板提取）', r.$1 && File('${temp.path}/a.gpl').readAsStringSync().contains('GIMP Palette'), r.$2);

    r = await _run(service, planner, 'png', 'docx', png.path, '${temp.path}/a.docx');
    _check('png → docx（图片嵌入）', r.$1, r.$2);

    r = await _run(service, planner, 'png', 'dst', png.path, '${temp.path}/a.dst');
    _check('png → dst（绣花）', r.$1, r.$2);

    r = await _run(service, planner, 'png', 'ascii_art', png.path, '${temp.path}/a-ascii.txt');
    _check('png → ascii_art', r.$1 && File('${temp.path}/a-ascii.txt').existsSync(), r.$2);

    // 3D 侧
    r = await _run(service, planner, 'obj', 'png', obj.path, '${temp.path}/tri.png');
    _check('obj → png（软件光栅化）', r.$1 && File('${temp.path}/tri.png').readAsBytesSync().sublist(0, 4).toString() == '[137, 80, 78, 71]', r.$2);

    r = await _run(service, planner, 'obj', 'geo_json', obj.path, '${temp.path}/tri.geo.json');
    _check('obj → geo_json（凸包）', r.$1 && jsonDecode(File('${temp.path}/tri.geo.json').readAsStringSync()) is Map, r.$2);

    // GPS 侧
    r = await _run(service, planner, 'gpx', 'svg', gpx.path, '${temp.path}/t.svg');
    _check('gpx → svg（轨迹渲染）', r.$1 && File('${temp.path}/t.svg').readAsStringSync().contains('<svg'), r.$2);

    r = await _run(service, planner, 'gpx', 'png', gpx.path, '${temp.path}/t.png');
    _check('gpx → png', r.$1, r.$2);

    // 文本侧
    r = await _run(service, planner, 'txt', 'qr_png', txt.path, '${temp.path}/qr.png');
    _check('txt → qr_png（自实现 QR）', r.$1 && File('${temp.path}/qr.png').readAsBytesSync().sublist(0, 4).toString() == '[137, 80, 78, 71]', r.$2);

    r = await _run(service, planner, 'txt', 'identicon_png', txt.path, '${temp.path}/id.png');
    _check('txt → identicon_png', r.$1, r.$2);

    // 绣花反向
    r = await _run(service, planner, 'dst', 'png', '${temp.path}/a.dst', '${temp.path}/stitch.png');
    _check('dst → png（绣花预览）', r.$1, r.$2);

    // 幻灯片 / 字体：无真实样本，仅验证链路可达
    _check(
      'pptx → txt 链路可达',
      planner.plan('pptx', 'txt')?.available == true,
      planner.plan('pptx', 'txt')?.steps.map((s) => s.engineId).join(' → ') ?? 'null',
    );
    _check(
      'ttf → woff 链路可达',
      planner.plan('ttf', 'woff')?.available == true,
      planner.plan('ttf', 'woff')?.steps.map((s) => s.engineId).join(' → ') ?? 'null',
    );

    // 插件能力必须诚实提示，不能假成功
    final ttsPlan = planner.plan('txt', 'mp3');
    _check(
      'txt → mp3 标记为需要插件',
      ttsPlan != null && !ttsPlan.available,
      ttsPlan?.blockedPluginId ?? 'null',
    );
  } finally {
    await temp.delete(recursive: true);
    await pluginDir.delete(recursive: true);
  }

  if (_failures > 0) {
    stderr.writeln('\n✗ 跨类型自检失败：$_failures 项');
    exit(1);
  }
  stdout.writeln('\n✓ 跨类型引擎与链路自检通过');
}
