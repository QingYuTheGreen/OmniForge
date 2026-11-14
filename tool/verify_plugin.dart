// 原生转换插件子系统自检（纯 Dart，不依赖 Flutter / 真实 .so）。
//
// 覆盖：
// 1. 内置目录：数量、id 唯一、体积、平台库文件名约定；
// 2. 注册表：missing → 安装 → installed → 卸载 → missing；
// 3. 引擎：插件缺失时给出 PluginRequired；库损坏时优雅降级（Error / PluginRequired），
//    且 stream 必须正常结束、不抛未捕获异常。
//
// 用法：dart run tool/verify_plugin.dart
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';

import 'package:omniforge/engine/engines/native_plugin_engine.dart';
import 'package:omniforge/engine/i_engine.dart';
import 'package:omniforge/engine/plugin/native_plugin_registry.dart';
import 'package:omniforge/engine/plugin/plugin_catalog.dart';
import 'package:omniforge/engine/plugin/plugin_manifest.dart';
import 'package:path/path.dart' as p;

int _passed = 0;
int _failed = 0;

void check(bool condition, String description) {
  if (condition) {
    _passed++;
    print('  ✓ $description');
  } else {
    _failed++;
    stderr.writeln('  ✗ $description');
  }
}

Future<void> main() async {
  final temp = Directory.systemTemp.createTempSync('omniforge_plugin_verify_');
  try {
    _checkCatalog();
    await _checkRegistry(temp);
    await _checkEngine(temp);
    await _checkManifestFromMap();
  } finally {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  }

  print('\n结果：$_passed 项通过，$_failed 项失败');
  if (_failed > 0) {
    exit(1);
  }
}

// ─────────────────────────── 1. 目录 ───────────────────────────

void _checkCatalog() {
  print('目录检查：');
  const builtIn = PluginCatalog.builtIn;
  check(builtIn.length >= 6, '内置插件数量 ≥ 6（实际 ${builtIn.length}）');

  final ids = builtIn.map((manifest) => manifest.id).toList();
  check(ids.toSet().length == ids.length, '插件 id 唯一（${ids.join(', ')}）');

  var validEntries = true;
  for (final manifest in builtIn) {
    final ok = manifest.id.isNotEmpty &&
        manifest.sizeMb > 0 &&
        manifest.platforms.isNotEmpty &&
        manifest.engineIds.isNotEmpty &&
        manifest.fileName.isNotEmpty &&
        manifest.symbol.isNotEmpty;
    if (!ok) {
      stderr.writeln('  ✗ 插件 ${manifest.id} 清单字段不完整');
      validEntries = false;
    }
  }
  check(validEntries, '每个插件都有 id / sizeMb / platforms / engineIds / fileName');

  for (final expected in <String>[
    'ocr',
    'asr',
    'tts',
    'woff2',
    'pdf_render',
    'archive_pro',
  ]) {
    check(PluginCatalog.byId(expected) != null, '目录包含插件 $expected（byId）');
  }

  check(PluginCatalog.byEngineId('ocr')?.id == 'ocr',
      'byEngineId("ocr") 命中 ocr 插件');
  check(PluginCatalog.byEngineId('unknown_engine') == null,
      'byEngineId(未知引擎) 返回 null');
  check(PluginCatalog.byId('unknown_plugin') == null, 'byId(未知插件) 返回 null');
  check(PluginCatalog.forPlatform('windows').length == builtIn.length,
      'forPlatform("windows") 覆盖全部插件');

  final ocr = PluginCatalog.byId('ocr')!;
  check(ocr.libraryFileName('android') == 'libomniforge_ocr.so',
      'Android 库文件名 = libomniforge_ocr.so');
  check(ocr.libraryFileName('linux') == 'libomniforge_ocr.so',
      'Linux 库文件名 = libomniforge_ocr.so');
  check(ocr.libraryFileName('windows') == 'omniforge_ocr.dll',
      'Windows 库文件名 = omniforge_ocr.dll');
  check(ocr.libraryFileName('ios') == 'libomniforge_ocr.dylib',
      'iOS 库文件名 = libomniforge_ocr.dylib');
  check(ocr.libraryFileName('macos') == 'libomniforge_ocr.dylib',
      'macOS 库文件名 = libomniforge_ocr.dylib');
  check(ocr.supportsPlatform('Darwin'), '平台别名 Darwin 归一化为 macOS');
  check(!ocr.supportsPlatform('web'), 'OCR 插件不支持 web 平台');
}

// ─────────────────────────── 2. 注册表 ───────────────────────────

Future<void> _checkRegistry(Directory temp) async {
  print('\n注册表检查：');
  final installDir = Directory(p.join(temp.path, 'install'));
  final registry = NativePluginRegistry(installDir: installDir);
  final ocr = PluginCatalog.byId('ocr')!;

  check(registry.manifests.length == PluginCatalog.builtIn.length,
      '注册表默认加载全部内置清单');
  check(registry.manifestForId('ocr') == ocr, 'manifestForId("ocr") 命中');
  check(registry.manifestForEngine('ocr')?.id == 'ocr',
      'manifestForEngine("ocr") 命中');

  // 初始 missing
  check(registry.stateOf('ocr') == PluginInstallState.missing,
      '未安装时 stateOf("ocr") == missing');
  check(registry.pathOf('ocr') == null, '未安装时 pathOf("ocr") == null');
  check(registry.stateOf('unknown_plugin') == PluginInstallState.missing,
      '未知插件 stateOf == missing');

  // 不支持的平台 → incompatible
  final webRegistry = NativePluginRegistry(
    installDir: installDir,
    platform: 'web',
  );
  check(webRegistry.stateOf('ocr') == PluginInstallState.incompatible,
      '平台不支持时 stateOf("ocr") == incompatible');

  // 安装（从假库文件拷贝，覆盖原子写路径）
  final source = File(p.join(temp.path, 'fake_ocr.so'))
    ..writeAsBytesSync(List<int>.generate(64, (index) => index));
  await registry.install('ocr', source);
  check(registry.stateOf('ocr') == PluginInstallState.installed,
      'install() 后 stateOf("ocr") == installed');
  final installedPath = registry.pathOf('ocr');
  check(installedPath != null && File(installedPath).existsSync(),
      'pathOf("ocr") 指向真实存在的库文件');
  check(
      installedPath != null &&
          p.basename(installedPath) == ocr.libraryFileName(registry.platform),
      '安装文件名符合平台约定（${installedPath == null ? 'null' : p.basename(installedPath)}）');
  check(!File('$installedPath.tmp').existsSync(), '安装后不残留 .tmp 临时文件');
  check(
      p.equals(
          p.dirname(installedPath!), p.join(installDir.path, 'plugins', 'ocr')),
      '安装目录为 <installDir>/plugins/ocr');

  // 手工删除库文件后回到 missing
  final tampered = File(installedPath)..deleteSync();
  check(
      !tampered.existsSync() &&
          registry.stateOf('ocr') == PluginInstallState.missing,
      '库文件被删除后回到 missing');

  // 手工写入（模拟下载后已落盘）→ installed
  await registry.pluginDir('ocr').create(recursive: true);
  File(installedPath).writeAsBytesSync(List<int>.filled(32, 0x7f));
  check(registry.stateOf('ocr') == PluginInstallState.installed,
      '手工写入库文件后 stateOf == installed');

  // 卸载
  await registry.uninstall('ocr');
  check(registry.stateOf('ocr') == PluginInstallState.missing,
      'uninstall() 后 stateOf("ocr") == missing');
  check(!registry.pluginDir('ocr').existsSync(), 'uninstall() 删除插件目录');
  await registry.uninstall('ocr'); // 重复卸载应静默
  check(true, '重复 uninstall() 不抛异常');
}

// ─────────────────────────── 3. 引擎 ───────────────────────────

Future<void> _checkEngine(Directory temp) async {
  print('\n引擎检查：');
  final installDir = Directory(p.join(temp.path, 'engine_install'));
  final registry = NativePluginRegistry(installDir: installDir);
  final ocr = PluginCatalog.byId('ocr')!;

  final input = File(p.join(temp.path, 'input.png'))
    ..writeAsBytesSync(<int>[1, 2, 3]);
  final output = p.join(temp.path, 'out', 'result.txt');
  final context = EngineContext(
    inputPath: input.path,
    outputPath: output,
    targetFormat: 'txt',
    sourceFormat: 'png',
    params: <String, dynamic>{'lang': 'chi_sim'},
  );

  // 默认 id / requiredPluginId / override
  final missingEngine = NativePluginEngine(manifest: ocr, registry: registry);
  check(missingEngine.id == 'ocr', '默认引擎 id == 清单 engineIds.first');
  check(missingEngine.requiredPluginId == 'ocr', 'requiredPluginId == 插件 id');
  final overrideEngine = NativePluginEngine(
    manifest: ocr,
    registry: registry,
    engineIdOverride: 'ocr_pro',
  );
  check(overrideEngine.id == 'ocr_pro', 'engineIdOverride 覆盖引擎 id');

  // (a) 插件缺失 → PluginRequired(ocr, sizeMb)，stream 正常结束
  final missingEvents = await _collect(missingEngine.convert(context));
  final requiredEvents = missingEvents.whereType<PluginRequired>().toList();
  check(requiredEvents.length == 1, '缺失插件时恰好产生 1 个 PluginRequired');
  check(requiredEvents.isNotEmpty && requiredEvents.first.pluginId == 'ocr',
      'PluginRequired.pluginId == "ocr"');
  check(requiredEvents.isNotEmpty && requiredEvents.first.sizeMb == ocr.sizeMb,
      'PluginRequired.sizeMb == ${ocr.sizeMb}');
  check(
      requiredEvents.isNotEmpty &&
          (requiredEvents.first.note?.isNotEmpty ?? false),
      'PluginRequired 附带安装提示 note');
  check(!missingEvents.any((event) => event is Success), '缺失插件时不会误报 Success');

  // (b) 插件「已安装」但库是假文件：dlopen 失败，必须优雅降级
  final fakeLibrary = File(p.join(temp.path, 'fake_engine.so'))
    ..writeAsBytesSync(List<int>.generate(128, (index) => index * 3 % 256));
  await registry.install('ocr', fakeLibrary);
  check(registry.stateOf('ocr') == PluginInstallState.installed,
      '引擎测试前状态为 installed');

  final brokenEngine = NativePluginEngine(manifest: ocr, registry: registry);
  List<EngineProgress> brokenEvents;
  try {
    brokenEvents = await _collect(brokenEngine.convert(context));
    check(true, '库损坏时 convert stream 正常结束（未抛未捕获异常）');
  } catch (error) {
    brokenEvents = const <EngineProgress>[];
    check(false, '库损坏时 convert stream 抛出了异常：$error');
  }
  final graceful = brokenEvents.whereType<PluginRequired>().toList();
  final errors = brokenEvents.whereType<Error>().toList();
  check(graceful.isNotEmpty || errors.isNotEmpty,
      '库损坏时得到 PluginRequired 或 Error 提示');
  check(!brokenEvents.any((event) => event is Success), '库损坏时不会误报 Success');
  final degradedMessage = graceful.isNotEmpty
      ? (graceful.first.note ?? '')
      : (errors.isNotEmpty ? errors.first.message : '');
  print('    降级提示：$degradedMessage');

  // 参数 JSON 编码：非 JSON 可序列化参数不能抛未捕获异常
  final weirdContext = EngineContext(
    inputPath: input.path,
    outputPath: output,
    targetFormat: 'txt',
    params: <String, dynamic>{'callback': Object()},
  );
  final weirdEvents = await _collect(brokenEngine.convert(weirdContext));
  check(
      weirdEvents.any((event) => event is Error) ||
          weirdEvents.any((event) => event is PluginRequired),
      '不可序列化参数被转成 Error / PluginRequired');

  // (c) 平台不支持 → PluginRequired（note 指明当前平台）
  final webRegistry = NativePluginRegistry(
    installDir: Directory(p.join(temp.path, 'engine_install_web')),
    platform: 'web',
  );
  final incompatibleEvents = await _collect(
    NativePluginEngine(manifest: ocr, registry: webRegistry).convert(context),
  );
  final incompatibleRequired =
      incompatibleEvents.whereType<PluginRequired>().toList();
  check(
      incompatibleRequired.length == 1 &&
          (incompatibleRequired.first.note?.contains('web') ?? false),
      '平台不支持时引擎返回带平台说明的 PluginRequired');
}

/// 收集转换事件；超时视为 stream 未正常结束（失败）。
Future<List<EngineProgress>> _collect(Stream<EngineProgress> stream) {
  return stream.toList().timeout(
    const Duration(seconds: 30),
    onTimeout: () {
      throw TimeoutException('转换 stream 30 秒内没有结束');
    },
  );
}

// ─────────────────────── 4. 清单解析 ───────────────────────

Future<void> _checkManifestFromMap() async {
  print('\n清单解析检查：');
  final manifest = PluginManifest.fromMap(<String, dynamic>{
    'id': 'demo',
    'name': '示例插件',
    'description': '测试用',
    'sizeMb': 7,
    'platforms': <String>['android', 'windows'],
    'engineIds': <String>['demo'],
  });
  check(manifest.id == 'demo', 'fromMap 解析 id');
  check(manifest.sizeMb == 7, 'fromMap 解析 sizeMb');
  check(manifest.fileName == 'omniforge_demo', 'fromMap 缺省 fileName 派生');
  check(manifest.symbol == 'omniforge_convert', 'fromMap 缺省入口符号');
  check(manifest.libraryFileName('windows') == 'omniforge_demo.dll',
      'fromMap 后平台库文件名正确');

  var rejected = false;
  try {
    PluginManifest.fromMap(<String, dynamic>{
      'id': '',
      'sizeMb': 3,
      'platforms': <String>['linux'],
      'engineIds': <String>['x'],
    });
  } on FormatException {
    rejected = true;
  }
  check(rejected, 'fromMap 拒绝空 id');

  rejected = false;
  try {
    PluginManifest.fromMap(<String, dynamic>{
      'id': 'x',
      'sizeMb': 0,
      'platforms': <String>['linux'],
      'engineIds': <String>['x'],
    });
  } on FormatException {
    rejected = true;
  }
  check(rejected, 'fromMap 拒绝 sizeMb <= 0');
}
