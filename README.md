# OmniForge 万能锻造炉

100% 离线、跨平台的万能文件转换器。19 大类格式、88 种格式，真实转换引擎（不是空壳）。
Flutter + Material 3，Android / Windows / macOS / Linux / iOS 全平台。

## 功能

| 类别 | 可以做什么 |
| --- | --- |
| 图片 | jpg / png / webp / gif / bmp / tiff / ico 互转，缩放、质量参数，图片 → PDF |
| 音频 / 视频 | 原生 FFmpeg 库（`ffmpeg_kit_flutter_new_full`）转码：mp4 / mkv / mov / avi / webm / mp3 / wav / flac / aac / m4a / ogg，视频 → GIF、视频 → 字幕、视频/音频 → 图片 |
| 文档 | docx / rtf / html / md / txt 互转，文本 → PDF，PDF → 文本 |
| 电子书 | epub ↔ txt / md / html（按 spine 顺序解析章节） |
| 表格 | csv / json / xml / xlsx 互转（内置最小 OOXML 读写，无需 Office） |
| 幻灯片 | pptx / odp / pdf（需要 LibreOffice 插件时给出明确提示，不做假转换） |
| 3D / 网格 | obj / stl / gltf / glb / ply / off 互转，GLB 容器与 glTF 2.0 内嵌 base64 |
| 纹理 | dds(DXT1/3/5) / ktx / tga → png / jpg / webp 等，图片 → 纹理（未压缩 DDS） |
| 调色板 | ase / aco / gpl / json 互转（Lab → sRGB 正确换算） |
| 哈希 | md5 / sha1 / sha256 / sha512 / crc32 / base64 |
| 字幕 | srt / ass / vtt / lrc 互转 |
| GPS | gpx / kml / tcx / geojson 互转 |
| 播放列表 | m3u / m3u8 / cue 互转 |
| 压缩包 | zip ↔ tar.gz |
| Minecraft | mcworld / mcpack（含 Java 版变体）重打包 |
| 字体 / 绣花 / MIDI / 加密音乐 | 诚实标记为需要插件；**不提供** NCM / KGM / QMC 等私有加密格式的解密 |

所有转换都在本机完成，不联网、不上传、不调用外部命令行程序。

## 架构

```
assets/formats.yaml        19 类 / 88 格式 / 30 条链路（状态：ready / plugin / planned）
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
  engines/                 18 个纯 Dart 引擎 + 1 个原生 FFmpeg 引擎
lib/features/home/         配置页（按可达链路出选项、按 ParamDef 动态渲染参数）
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

- ✅ 转换引擎、规划器、执行服务、配置页、格式表全部接入
- ✅ 51 种格式可直接转换，24 种需要插件（诚实提示），13 种规划中
- 🚧 字体（woff2/brotli）、绣花、MIDI、幻灯片、加密音乐需要后续插件
