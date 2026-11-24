// 生成《格式转换矩阵》文档：从 assets/formats.yaml + 引擎注册表 + 规划器实际计算得出。
// 运行：dart run tool/gen_conversion_matrix.dart > docs/CONVERSION_MATRIX.md
import 'dart:io';

import 'package:omniforge/engine/conversion_planner.dart';
import 'package:omniforge/engine/engine_registry.dart';
import 'package:omniforge/models/format_node.dart';
import 'package:yaml/yaml.dart';

void main() {
  final root = loadYaml(File('assets/formats.yaml').readAsStringSync()) as YamlMap;
  final categories = <FormatCategory>[];
  for (final c in (root['categories'] as YamlList)) {
    final m = c as YamlMap;
    categories.add(FormatCategory(
      key: m['key'] as String,
      name: m['name'] as String,
      icon: (m['icon'] ?? '') as String,
      order: (m['order'] as num?)?.toInt() ?? 0,
    ));
  }
  final formats = <FormatNode>[];
  for (final f in (root['formats'] as YamlList)) {
    final n = FormatNode.fromYaml(f as YamlMap);
    if (n.id.isNotEmpty) formats.add(n);
  }
  final flows = <FlowRule>[];
  for (final f in ((root['flows'] as YamlList?) ?? YamlList())) {
    final r = FlowRule.fromYaml(f as YamlMap);
    if (r.source.isNotEmpty) flows.add(r);
  }

  final registry = EngineRegistry.platformDefaults();
  final planner = ConversionPlanner.fromData(
    formats: formats,
    flows: flows,
    readyEngines: registry.readyEngineIds,
    knownEngines: registry.all.map((e) => e.id).toSet(),
  );

  final catOf = <String, String>{};
  for (final n in formats) {
    catOf[n.id] = n.category;
  }
  final catName = {for (final c in categories) c.key: c.name};

  final buf = StringBuffer();
  void w([String s = '']) => buf.writeln(s);

  w('# 格式转换矩阵（由代码生成）');
  w();
  w('> 本文档由 `tool/gen_conversion_matrix.dart` 从 `assets/formats.yaml`、');
  w('> `lib/engine/engine_registry.dart`、`lib/engine/conversion_planner.dart` 实际计算生成，');
  w('> 与运行时 App 内「输出格式」列表完全一致。修改 YAML 或引擎后重新生成即可。');
  w();
  w('- 生成命令：`dart run tool/gen_conversion_matrix.dart > docs/CONVERSION_MATRIX.md`');
  w('- 格式条目：${formats.length}；类别：${categories.length}；显式链路：${flows.length}；'
      '已注册引擎：${registry.all.length}（可直接运行 ${registry.readyEngineIds.length}）');
  w();
  w('## 0. 转换是怎么算出来的');
  w();
  w('所有转换都归约为一个公式：**读取源格式 → 中间表示（IR）→ 写出目标格式**。');
  w('App 不猜「格式对格式」的 if-else 大表，而是把每个引擎注册成图里的一条有向边，');
  w('再用 BFS 找一条最省的路径：');
  w();
  w('1. **显式边（flows）**：YAML `flows:` 里写明「源格式组 → 目标格式组，由某引擎负责」，');
  w('   带该链路的默认参数（如 `image_to_image` 的 width/height/quality）。');
  w('2. **隐式边（引擎读写能力表）**：`lib/engine/engine_capabilities.dart` 为每个引擎声明');
  w('   「能读哪些格式 id → 能写哪些格式 id」，只有两者都成立才建边；不按类别名猜，');
  w('   所以不会出现「公文包 → 二维码 → PNG」这种引擎根本无法执行的链路。');
  w('3. **多跳**：没有直转时最多拼接 2 跳，例如 `epub → txt → md`、`docx → pdf`（经 txt）。');
  w('4. **代价函数**：`不可用引擎 ×100 + 跳数 ×10 + 隐式边 ×2`，即优先用可运行引擎、优先少跳、');
  w('   优先走 YAML 显式声明的链路（同跳数时显式边胜过隐式边）。');
  w('5. 每条边最终落到一个 `IEngine` 实现；多步由 `ConversionService` 用临时文件中转，');
  w('   进度按步数加权聚合，任一步失败即中断。');
  w();
  w('**可用性标记**：✅ 引擎可直接运行；⏳ 当前环境缺少内置原生库（正常安装包内置，不会出现）');

  w();

  // 类别 × 类别 可达数量矩阵
  final catKeys = categories.map((c) => c.key).toList();
  final counts = <String, Map<String, int>>{};
  final details = <String, List<String>>{};
  var totalPairs = 0;
  for (final src in formats) {
    final reach = planner.reachableFrom(src.id);
    for (final t in reach) {
      if (t.formatId == src.id) continue;
      counts.putIfAbsent(catOf[src.id]!, () => {});
      counts[catOf[src.id]!]![catOf[t.formatId]!] =
          (counts[catOf[src.id]!]![catOf[t.formatId]!] ?? 0) + 1;
      totalPairs++;
    }
    details[src.id] = reach.map((t) => t.formatId).toList();
  }

  w('## 1. 类别 × 类别 可达数量（行=源，列=目标，数字=可达格式数）');
  w();
  w('| 源 \\ 目标 | ${catKeys.map((k) => catName[k] ?? k).join(' | ')} |');
  w('| --- | ${catKeys.map((_) => '---').join(' | ')} |');
  for (final s in catKeys) {
    final row = catKeys.map((t) => '${counts[s]?[t] ?? 0}').join(' | ');
    w('| ${catName[s] ?? s} | $row |');
  }
  w();
  w('可达 (源,目标) 组合总数（不含同格式自身）：**$totalPairs**');
  w();

  // 每种源格式
  w('## 2. 每种格式能转成什么（含引擎链路）');
  w();
  for (final cat in categories) {
    final list = formats.where((f) => f.category == cat.key).toList();
    if (list.isEmpty) continue;
    w('### ${cat.name}（${cat.key}）');
    w();
    for (final src in list) {
      final reach = planner.reachableFrom(src.id);
      final ext = src.extensions.isEmpty ? '?' : src.extensions.first;
      w('');
      w('#### `${src.id}`（.${ext.replaceFirst('.', '')}）'
          ' - ${src.status == 'ready' ? '✅ 可读' : '❌ 暂不支持'}');
      w();
      final direct = <ReachableTarget>[];
      final multi = <ReachableTarget>[];
      for (final t in reach) {
        if (t.formatId == src.id) continue;
        (t.isDirect ? direct : multi).add(t);
      }
      if (direct.isEmpty && multi.isEmpty) {
        w('- （无出边：该格式没有可用的写出引擎，或上游读取能力未接入）');
        continue;
      }
      if (direct.isNotEmpty) {
        w('- **直转**：');
        for (final t in direct) {
          final plan = planner.plan(src.id, t.formatId)!;
          final eng = plan.engineIds.join('+');
          final flag = plan.available ? '✅' : '⏳';
          w('  - `${src.id}` → `${t.formatId}` $flag `$eng`');
        }
      }
      if (multi.isNotEmpty) {
        w('- **多跳**（最多 2 跳）：');
        for (final t in multi) {
          final plan = planner.plan(src.id, t.formatId)!;
          final flag = plan.available ? '✅' : '⏳';
          w('  - `${src.id}` → `${t.formatId}` $flag ${plan.describe}');
        }
      }
    }
    w();
  }

  // 引擎清单
  w('## 3. 引擎清单与算法');
  w();
  w('| 引擎 id | 读 | 写 | 算法要点 |');
  w('| --- | --- | --- | --- |');
  const engineNotes = <String, String>{
    'image': 'jpg/png/webp/gif/bmp/tiff/ico/psd/tga/pvr/exr | jpg/png/webp/gif/bmp/tiff/ico/tga | 纯 Dart 解码 + 缩放 + 编码；jpg/bmp 输出时 alpha 铺白底',
    'texture': 'dds/ktx/tga | png/jpg/webp/bmp/tga/dds | 解析 DDS(BC1/BC2/BC3)、KTX(DXT1/DXT3/DXT5/RGBA8/RGB8) 并软件解码；可写出未压缩 BGRA8 DDS',
    'text': 'txt/md/html | txt/md/html | 纯文本 HTML/Markdown 互转（内置 stripHtml / htmlToMarkdown）',
    'document': 'docx/rtf/txt/html/md | docx/rtf/txt/md/html | OOXML 段落与表格解析、RTF 控制字扫描；写出最简 OOXML/RTF',
    'spreadsheet': 'xlsx/csv/json/xml | xlsx/csv/json/xml | 表格 IR（表头+行）互转；xlsx 走 OOXML inlineStr',
    'table': 'csv/json/xml/xlsx | csv/json/xml/xlsx | 与 spreadsheet 同一套表格 IR，按目标格式选择写出器',
    'ebook': 'epub | txt/md/html/epub | 按 container.xml/opf spine 顺序抽正文；写出 EPUB3',
    'pdf': 'png/jpg/txt/md/html/pdf | pdf/txt | 图片/文本 → PDF（pdf 包排版，含中文字体探测）；PDF → 文本（解压内容流 + Tj/TJ 提取）',
    'image_doc': '任意图片 | docx | DrawingML 内嵌 PNG（EMU = px×9525）',
    'image_palette': '任意图片 | ase/aco/gpl/json | 量化取主色后写调色板',
    'palette_image': 'ase/aco/gpl/json | png | 调色板 → 色卡 PNG（可设列数/格子尺寸）',
    'svg_vector': '任意位图 | svg | 位图矢量描摹（轮廓/色块简化）',
    'ascii_art': '图片 | ascii_art/braille_art | 亮度映射字符；盲文用 2×4 点阵编码',
    'qr': '任意文件 | qr_png | 纯 Dart QR 编码（字节模式、版本 1–10、L/M/Q/H、8 种掩码罚分择优）',
    'identicon': '任意文件 | identicon_png | md5 → 5×5 对称图案 + HSL 配色',
    'gps': 'gpx/kml/tcx/geojson | 同左 | 轨迹点 IR 互转',
    'geo_render': 'gpx/kml/tcx/geojson | svg/png | 经纬度正交投影绘制轨迹线',
    'subtitle': 'srt/ass/vtt/lrc | 同左 | 字幕 IR（起止时间+文本）互转',
    'playlist': 'm3u/m3u8/cue | 同左 | 曲目 IR 互转（CUE 用累计时长换算 INDEX）',
    'hash': '任意文件 | md5/sha/crc/base64 | crypto 摘要 / CRC32 / base64 文本',
    'archive': 'zip/tar/tar.gz/gz | 同左 | archive 包 Zip/Tar/GZip 编解码；rar/7z 暂不支持',
    'minecraft': 'mcworld/mcpack(_java)/zip | 同左 | 资源包/行为包目录重排 + manifest.json',
    'color': 'ase/aco/gpl/json | 同左 | ASE(u16/f32/UTF-16BE)、ACO(Lab→sRGB)、GPL 解析与写出',
    'font': 'ttf/otf/woff | ttf/otf/woff | sfnt 表目录重建 + WOFF1 zlib 表 + checksum 重算（无损）；woff2 暂不支持',
    'slides': 'pptx/odp | txt/md/html/pdf | 按 presentation.xml sldIdLst 真实页序取文本与图片',
    'embroidery': 'dst/pes/jef/png/jpg | dst/pes/jef/png | 绣花针迹 IR 互转；位图按阈值描边成针迹',
    'render3d': 'obj/stl/ply/off/gltf/glb | png/jpg | 软件光栅化（正交投影 + z-buffer + Lambert）',
    'mesh_geo': 'obj/stl/ply/off/gltf/glb | geojson | 单调链凸包 → Polygon + 质心 Point',
    'audio_midi': 'wav 等（经 FFmpeg 解码） | midi | 基频自相关提取 → 音符/时值',
    'spectrogram': '音频（经 FFmpeg 解码） | png/jpg | 汉宁窗 + radix-2 FFT 绘制时频图',
    'ffmpeg': 'mp3/wav/flac/aac/m4a/ogg/mp4/mkv/mov/avi/webm/flv | 同左 + gif/srt/png/jpg | FFmpegKitNext 原生库（无命令行）：转码/抽帧/抽字幕/波形视频',
  };
  for (final e in registry.all) {
    final note = engineNotes[e.id];
    if (note != null && note.isNotEmpty) w('| `${e.id}` | ${note.split(' | ')[0]} | ${note.split(' | ')[1]} | ${note.split(' | ')[2]} |');
  }
  w();
  w('> 未列出的 `model3d` / `mesh` 引擎：obj/stl/ply/off/gltf/glb 之间互转（glTF 走 JSON/GLB 容器，');
  w('> 采用自写 `lib/engine/engines/mesh_io.dart` 解析与写出）。');
  w();
  w('## 4. 暂不支持 / 暂不可达的部分');
  w();
  w('所有转换能力都随安装包内置：纯 Dart 算法引擎 + 编译进包的 FFmpegKitNext 原生库，');
  w('不存在外置安装插件的路径。下表里的格式仅仅是因为缺少内置解码器/模型而暂未接入。');
  w();
  final unsupported = formats
      .where((f) => f.status == 'planned')
      .map((f) => f.id)
      .toList();
  if (unsupported.isNotEmpty) {
    w('| 格式 | 原因 |');
    w('| --- | --- |');
    for (final id in unsupported) {
      w('| `$id` | 需要额外的内置解码器/模型，当前版本暂不支持 |');
    }
    w();
  }
  final plannedFormats = formats.where((f) => f.status == 'planned').map((f) => f.id).toList();
  if (plannedFormats.isNotEmpty) {
    w('- 不可达：${plannedFormats.map((p) => '`$p`').join('、')}');
  }
  w();

  stdout.write(buf.toString());
}
