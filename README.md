# OmniForge 万能锻造炉

100% 离线、跨平台的万能文件转换器。19 大类、95 个格式条目、36 个转换引擎
（31 个零依赖纯 Dart 引擎 + 原生 FFmpeg 库 + 可选原生插件），支持直转与多跳链路。
Flutter + Material 3，Android / Windows / macOS / Linux / iOS / 鸿蒙（OHOS）全平台。

## 功能

| 类别 | 可以做什么 |
| --- | --- |
| 图片 | jpg / png / webp / gif / bmp / tiff / ico / psd / exr 互转，缩放、质量参数，图片 → PDF |
| 跨类型（图像侧） | 图片 → SVG 矢量描摹、图片 → 调色板（ase/aco/gpl/json）、图片 → docx 嵌图、任意图片 → ASCII / 盲文艺术 txt、图片 → 绣花文件（dst/pes/jef） |
| 音频 / 视频 | 原生 FFmpeg 库（`ffmpeg_kit_flutter_new_full`）转码：mp4 / mkv / mov / avi / webm / mp3 / wav / flac / aac / m4a / ogg |
| 跨类型（音视频侧） | 视频 → GIF / 图片 / 内嵌字幕（srt）；音频 → 视频（波形封面）、音频 → 波形图 PNG、音频 → 频谱图 PNG、音频 → MIDI（自相关基频提取） |
| 文档 | docx / rtf / html / md / txt 互转，文本 → PDF，PDF → 文本 |
| 电子书 | epub ↔ txt / md / html（按 spine 顺序解析章节） |
| 表格 | csv / json / xml / xlsx 互转（内置最小 OOXML 读写，无需 Office） |
| 幻灯片 | pptx / odp → txt / md / html / pdf（按 `sldIdLst` 真实页序解析，图片从 rels 提取） |
| 字体 | ttf ↔ woff、otf ↔ woff（WOFF1 zlib 表 + checksum 重算；woff2 需插件） |
| 3D / 网格 | obj / stl / gltf / glb / ply / off 互转，GLB 容器与 glTF 2.0 内嵌 base64 |
| 跨类型（3D 侧） | 3D / 网格 → PNG / JPG（内置软件光栅化：z-buffer + Lambert + 线框）、网格 → GeoJSON（凸包 + 质心） |
| 纹理 | dds(DXT1/3/5) / ktx / tga → png / jpg / webp 等，图片 → 纹理（未压缩 DDS） |
| 调色板 | ase / aco / gpl / json 互转（Lab → sRGB 正确换算） |
| 哈希 | md5 / sha1 / sha256 / sha512 / crc32 / base64 |
| 字幕 | srt / ass / vtt / lrc 互转 |
| GPS | gpx / kml / tcx / geojson 互转 |
| 跨类型（GPS 侧） | 轨迹 → PNG / SVG 图（等距圆柱投影、起终点标记） |
| 跨类型（文本侧） | 任意文件 → 二维码 PNG（自实现 ISO 18004 编码器）、任意文件 → 头像图标 PNG、任意格式 → md5 / sha / crc32 / base64 |
| 播放列表 | m3u / m3u8 / cue 互转 |
| 压缩包 | zip ↔ tar.gz |
| Minecraft | mcworld / mcpack（含 Java 版变体）重打包 |
| 绣花 | dst / pes / jef 互转、绣花 → PNG 预览、图片 → 绣花（蛇形扫描转针迹） |
| 加密音乐 / 模型类能力 | OCR、语音识别、TTS、WOFF2、PDF 渲染、扩展压缩包由**原生插件**提供（导入后离线运行）；**不提供** NCM / KGM / QMC 等私有加密格式的解密 |

所有转换都在本机完成，不联网、不上传、不调用外部命令行程序；
需要大型模型或第三方库的能力走原生插件（Android `.so` / Windows `.dll` / macOS·iOS `.dylib`）。

## 架构

```
assets/formats.yaml        19 类 / 95 个格式条目 / 49 条显式链路（ready / plugin / planned）
lib/engine/
  i_engine.dart            引擎接口 + EngineContext + 进度事件 + 取消令牌
  engine_utils.dart        SimpleEngine 模板基类、参数读取、文件工具
  engine_registry.dart     引擎注册与可用性（ready / pluginRequired / missing）
  conversion_planner.dart  BFS 最短路：显式 flows + accepts_from 隐式边，直转 / 多跳
  conversion_service.dart  多步串联执行、临时文件中转、进度聚合、取消
  common/                  可复用的转换算法库（见 docs/ENGINE_LIBRARY.md）
    binary_io.dart          字节序读写、hex
    package_io.dart         ZIP 容器（docx / xlsx / epub / mcworld 共用）
    text_format.dart        HTML / Markdown / 纯文本互转工具
  ffmpeg_backend.dart      原生库抽象（FfmpegBackend + NullFfmpegBackend）
  ffmpeg_kit_backend.dart  Android / iOS / macOS / Windows / Linux 原生 FFmpeg 实现
  ffmpeg_ohos_backend.dart 鸿蒙 @ohos/ffmpeg-kit NAPI 桥接
  plugin/                  原生插件清单 / 安装注册表（动态库 + 统一 ABI）
  engines/                 35 个纯 Dart 引擎 + 1 个原生 FFmpeg 引擎 + 6 个插件引擎：
                           图像 / 纹理 / 3D 渲染 / 网格 / 文档 / 表格 / 电子书 / PDF /
                           字幕 / GPS 渲染 / 播放列表 / 压缩包 / 哈希 / 调色板 / 字体 /
                           幻灯片 / 绣花 / MIDI / 频谱 / 二维码 / 头像 / ASCII / GeoJSON
lib/features/home/         配置页（按可达链路出选项、按 ParamDef 动态渲染参数）
lib/features/settings/     设置页 + 转换插件管理页（导入 / 卸载原生插件）
```

## 原生库与许可

- 音视频转码通过 `ffmpeg_kit_flutter_new_full`（LGPL 版 FFmpeg full build）随包内置的
  `.so` (Android) / `.dll` (Windows) / `.dylib` (macOS) 完成，经平台通道直接调用原生接口，
  **不启动 ffmpeg 命令行**，也不依赖用户机器上安装 FFmpeg。
- 项目自身代码为 MIT；内置 FFmpeg 为 LGPL v3，分发时请保留其许可文本与源码获取方式
  （详见 `THIRD_PARTY_NOTICES.md`）。

## 构建

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release --split-per-abi
```

桌面端：`flutter build windows` / `flutter build macos` / `flutter build linux`。

## 自检

```bash
dart run tool/check_formats.dart   # 格式表结构校验
dart run tool/check_engines.dart   # 引擎注册 / 链路可达性 / 真实转换冒烟
```

## 开发状态

- ✅ 转换引擎、规划器、执行服务、配置页、插件页、格式表全部接入
- ✅ 68 个格式条目可直接转换，19 个需要插件（诚实提示），8 个规划中
- ✅ 跨类型矩阵：图片 ↔ SVG / 调色板 / docx / 绣花 / ASCII、3D ↔ 图片 / GeoJSON、
      音频 ↔ 视频 / 波形 / 频谱 / MIDI、视频 → 字幕、GPS ↔ 图片 / SVG、任意文件 → 哈希 / 二维码 / 头像
- 🚧 woff2（brotli）、OCR、ASR、TTS、PDF 渲染、rar/7z 走原生插件子系统（导入即用）
