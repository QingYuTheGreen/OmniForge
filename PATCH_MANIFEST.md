# PATCH_MANIFEST — OmniForge 增量包（v0.7.0 · 正式转换引擎）

> 给接手的 AI：这是**增量包**，不是完整工程。按「怎么用」覆盖到对应基线即可，不要单独构建它。

## 一、这个包是什么

- 工程：OmniForge（Flutter 跨平台文件转换器，`com.file.omniforge.app`）
- **增量基线：commit `22f00d3`（v0.6.0，19 类 88 种格式空壳）**
- 内容：基线 → 当前状态的全部差异
- 生成时间：2026-11-14
- 本轮主题：**把空壳换成真实转换**——18 个纯 Dart 引擎 + 1 个原生 FFmpeg 引擎，
  格式规划器（BFS 直转/多跳）、执行服务（多步串联 / 进度聚合 / 取消）、
  配置页按可达链路出选项并动态渲染参数，全部离线、不调用命令行。

## 二、怎么用

1. 拿到基线：`git clone` 后 `git checkout 22f00d3`。
2. 把本包文件**覆盖**到工程根目录（结构与工程一致，同名直接覆盖）。
3. `flutter pub get`（新增 9 个依赖与 1 个原生插件；国内可设
   `PUB_HOSTED_URL=https://pub.flutter-io.cn`）→ `flutter analyze`（期望 0 error）→
   `flutter test` → `flutter build apk --release --split-per-abi`。
4. 原生 FFmpeg 由 `ffmpeg_kit_flutter_new_full` 随包提供 `.so/.dll/.dylib`，
   首次构建会下载各平台预编译产物（体积较大），无需用户机器安装 FFmpeg。

## 三、这轮改了什么

### 1. 引擎层（新增 `lib/engine/`）

- `i_engine.dart`：`IEngine` 接口、`EngineContext`（输入/输出/目标格式/参数/取消令牌）、
  `EngineProgress`（Progress / Success / Error / PluginRequired，`PluginRequired` 带 `note`）、
  `CancelToken`。
- `engine_utils.dart`：`SimpleEngine` 模板基类（统一进度、输出存在校验、异常转 Error）、
  参数读取（string/int/double/bool）、文件读写（UTF-8 容错）、`PluginEngine` 占位引擎。
- `engine_registry.dart`：引擎注册 + 可用性（`ready` / `pluginRequired` / `missing`）、
  `pluginInfoOf`、`EngineIds` 常量；`platformDefaults({FfmpegBackend?})` 便于测试注入。
- `conversion_planner.dart`：把 `flows:` 显式边与 `accepts_from` 隐式边合并成图，
  BFS 求最短路（≤3 跳），代价优先可用性再跳数；输出 `ConversionPlan`（含每步 `toExtension`
  与参数默认值）与 `reachableFrom()` 目标列表。
- `conversion_service.dart`：按步骤串联执行，中间结果写临时文件，整体进度聚合，
  任一步 `PluginRequired` / `Error` 立即中止并透传，最后清理临时目录。
- `engine_providers.dart`：Riverpod 提供 registry / planner / service（planner 从
  `RegistryManager` 的 yaml 数据构建）。
- `ffmpeg_kit_backend.dart`：`FfmpegKitBackend` 用 `ffmpeg_kit_flutter_new_full` 的原生库
  执行转码，`FFprobeKit` 取时长算进度，`FFmpegSession.cancel()` 支持取消；**不含任何 Process/CLI**。
- `common/`：可复用算法库（`binary_io.dart` 字节序读写、`package_io.dart` ZIP 封装、
  `text_format.dart` HTML/Markdown/纯文本互转），被多个引擎共享。
- `engines/`：hash、subtitle、playlist、gps、color、table、spreadsheet、text、document、
  ebook、pdf、image、texture、mesh、mesh_io、model3d、archive、minecraft、ffmpeg，
  以及 `ffmpeg_backend.dart` 的抽象后端。

### 2. `assets/formats.yaml` 全量重写

- `stage: shell` → `stage: ready`；格式状态改为真实三态：**51 ready / 24 plugin / 13 planned**。
- 引擎 id 与代码对齐：`audio/video → ffmpeg`、`gif → image`、`office → document/slides/spreadsheet`、
  `palette → color`、`xlsx → spreadsheet+table`、`json → table+color`、
  `txt → text/document/ebook/pdf`、`pdf → pdf`（只接受 image 输入）。
- 修正 `accepts_from` 的假链路（去掉没有真实实现的交叉声明），flows 重排为 **30 条**
  （补 video→subtitle、texture↔image、pdf→text、image→pdf、document/text 互转等），
  参数改为真实生效的 `width/height/quality/fps/start/duration/margin/algorithm`。
- 需要插件的格式显式标注 `status: plugin` + `note`（字体 / 绣花 / MIDI / 幻灯片 / 加密音乐），
  `ncm/kgm/qmc` 明确说明**不提供解密**。

### 3. 数据层

- `lib/models/format_node.dart`：修 `ParamDef.fromYaml` 的类型解析 bug——原来用
  `name.toUpperCase()` 对比 `switch$`，永远匹配不到，所有参数都退化成 text；
  改为 `_parseType()` 正确识别 slider / switch / dropdown / text。
- `pubspec.yaml`：新增 `image`、`archive`、`xml`、`crypto`、`markdown`、`pdf`、`csv`、`path`、
  `ffmpeg_kit_flutter_new_full`（注释说明选型理由：LGPL full build、原生库、不调命令行）。

### 4. UI

- `lib/features/home/config_page.dart` 重写：去掉写死的 GIF 参数卡与全量格式列表，
  改为 `ConversionPlanner.reachableFrom()`——按分类分组展示**真正可达**的目标，
  多跳目标标注「· N 步」，缺插件的目标置灰并标注「需插件 X」；
  参数按目标格式 / flow 的 `ParamDef` 动态渲染（slider / switch / dropdown / text）；
  「开始转换」在未选目标时禁用；底部显示引擎与格式统计。
- `lib/features/home/home_provider.dart` 重写：删除 `Timer` 模拟进度与写空文件，
  改为真实 `ConversionService` 流水线；每项记录 `targetFormat`/`params`，
  支持真取消（`CancelToken`）、失败重试、`PluginRequired` 友好提示。

### 5. 测试 / 工具 / 文档

- `test/engine_test.dart`（新增，纯 Dart）：格式表完整性、ready 格式可达性、
  规划器样例（png→pdf 直转、docx→txt 走 document、epub→md 多跳、mp4→mp3 缺 ffmpeg）、
  真实转换冒烟（txt→sha1、srt→vtt、csv→json、png→jpg）。
- `test/format_catalog_test.dart`：阶段断言改为 `ready`，配置页测试改为验证
  「输入格式」行 + 未识别提示 + 按钮禁用。
- `tool/check_engines.dart`（新增）：加载 yaml → 构建 registry/planner →
  校验引擎注册与链路可达 → 打印 16 组样例计划 → 跑 6 组真实转换。
- `README.md` 重写、`docs/ENGINE_LIBRARY.md` 新增（选型与算法依据）、
  `THIRD_PARTY_NOTICES.md` 新增（FFmpeg LGPL 说明）。

## 四、验证记录

- `dart analyze lib test tool`：**0 error**（余下均为既有 info/warning）
- `dart run tool/check_formats.dart`：19 类 / 88 格式 / 30 flow 结构自检通过
- `dart run tool/check_engines.dart`：25 个引擎（17 个可直接运行），
  16 组样例计划全部命中预期（含 ffmpeg 缺库时正确标记不可用），
  6 组真实转换（srt→vtt、gpx→kml、md→html、csv→json、txt→md5、ply→off）输出非空，
  「✓ 引擎与链路自检通过」
- 本机（aarch64）无法运行 Flutter 框架，`flutter test` / 打包留给 GitHub Actions（x64）

## 五、注意 / 下一轮

- 字体（woff2/brotli）、绣花（pes/dst/jef）、MIDI、幻灯片（pptx/odp）、加密音乐（ncm/kgm/qmc）
  仍是 `plugin` 状态，选中会提示需要插件，不会产出损坏文件。
- DDS 目前只解 DXT1/3/5 与未压缩格式；BC5/ATI2、ASTC、KTX2 需纹理插件。
- PDF 文本抽取是轻量实现（只处理 Flate 压缩内容流与 Tj/TJ），扫描件 / 加密 PDF 不支持。
- 新增格式：`common/` 补算法 → `engines/` 加薄引擎 → yaml 登记 → 跑 `check_engines.dart`。
