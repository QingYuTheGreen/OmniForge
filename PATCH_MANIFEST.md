# PATCH_MANIFEST — OmniForge 增量包（v0.8.0 · 跨类型转换 + 原生插件 + 鸿蒙）

> 给接手的 AI：这是**增量包**，按「怎么用」覆盖到对应基线即可，不要单独构建它。

## 一、这个包是什么

- 工程：OmniForge（Flutter 跨平台文件转换器，`com.file.omniforge.app`）
- **增量基线：commit `400fda3`（v0.7.0，18 个引擎 + 原生 FFmpeg）**
- 内容：基线 → 当前状态的全部差异
- 生成时间：2026-11-14
- 本轮主题：**把「同类型互转」扩展到「跨类型矩阵」**——新增 16 个纯 Dart 引擎
  （矢量描摹 / 调色板提取 / 图片转 docx / 3D 渲染 / 凸包 GeoJSON / 波形 / 频谱 /
  MIDI / 幻灯片 / 字体 / 二维码 / 头像 / ASCII 艺术 / 轨迹渲染 / 绣花 / 色卡），
  新增**原生插件子系统**（dlopen + 统一 ABI + 设置页导入），并为**鸿蒙**补上
  原生音视频后端（`@ohos/ffmpeg-kit`）。完全离线，不使用任何命令行进程。

## 二、怎么用

1. 拿到基线：`git checkout 400fda3`。
2. 把本包文件覆盖到工程根目录（结构与工程一致）。
3. `flutter pub get`（国内可设 `PUB_HOSTED_URL=https://pub.flutter-io.cn`）
   → `flutter analyze`（期望 0 error）→ `flutter test` → 打包。
4. 鸿蒙：`cd ohos && ohpm install` 后按 `docs/OHOS_FFMPEG.md` 构建；
   其余平台音视频由 `ffmpeg_kit_flutter_new_full` 随包原生库提供。
5. 插件能力（OCR / ASR / TTS / WOFF2 / PDF 渲染 / rar·7z）在设置页
   「转换插件」导入对应 `.so/.dll/.dylib` 后即可离线使用。

## 三、这轮改了什么

### 1. 新增转换引擎（`lib/engine/engines/`，全部纯 Dart）

| 引擎 id | 能力 | 关键参数 |
| --- | --- | --- |
| `svg_vector` | 位图 → SVG 矢量描摹 | max_size / colors / tolerance |
| `image_palette` | 图片 → ase / aco / gpl / json 调色板 | colors |
| `image_doc` | 图片 → docx（DrawingML 内嵌 PNG，EMU 精确尺寸） | width / align / caption |
| `render3d` | 3D/网格 → PNG/JPG（软件光栅化：z-buffer + Lambert + 线框） | width / height / rot_x / rot_y / wireframe |
| `mesh_geo` | 3D/网格 → GeoJSON（单调链凸包 + 质心） | rot_y |
| `geo_render` | gpx/kml/tcx/geojson → SVG/PNG（等距圆柱投影） | width / height / padding / stroke / dots |
| `embroidery` | dst / pes / jef 互转、绣花 → PNG 预览、图片 → 绣花 | scale / threshold / max_stitches |
| `slides` | pptx / odp → txt / md / html / pdf（按 sldIdLst 真实页序） | page_size / font_path |
| `font` | ttf ↔ woff、otf ↔ woff（WOFF1 zlib 表 + checksum 重算） | — |
| `qr` | 任意文本/文件 → 二维码 PNG（自实现 ISO/IEC 18004） | size / margin / ec |
| `identicon` | 任意文本/文件 → 头像 PNG（md5 对称 + HSL） | size / margin / background |
| `ascii_art` | 图片 → ASCII / 盲文艺术 TXT | width / charset / invert / threshold |
| `palette_image` | ase/aco/gpl/json → 色卡 PNG | columns / cell / background |
| `audio_midi` | 音频 → MIDI（自相关基频提取） | silence / tempo |
| `spectrogram` | 音频 → 频谱图 PNG（radix-2 FFT + viridis） | width / height |
| `audio_utils` / `audio_pcm_utils` | WAV 解析/编码、波形绘制、FFT（共享库） | — |

音视频引擎（`ffmpeg`）扩展：音频 → 视频（波形封面）、音频 → 波形 PNG、
视频 → 内嵌字幕 srt、视频 → 图片。

### 2. 原生插件子系统（`lib/engine/plugin/` + `engines/native_plugin_engine.dart`）

- `PluginManifest` / `PluginCatalog.builtIn`（6 个：ocr 38MB、asr 240MB、tts 68MB、
  woff2 2MB、pdf_render 12MB、archive_pro 8MB）。
- `NativePluginRegistry`：`<installDir>/plugins/<id>/<平台库文件名>`，原子安装（tmp→rename）、
  卸载、状态（missing / installed / incompatible）。
- `NativePluginEngine`：`DynamicLibrary.open` + 统一 ABI
  `int omniforge_convert(input, output, paramsJson, errbuf, errlen)`；
  原生调用跑在 `Isolate.run`；未安装时返回 `PluginRequired` 而不是失败。
- 设置页新增「转换插件」管理页（导入 / 重新导入 / 卸载）。

### 3. 鸿蒙原生音视频后端

- `lib/engine/ffmpeg_ohos_backend.dart`：MethodChannel `omniforge/ffmpeg`
  （execute / cancel / probeDuration + progress/log/complete 回推）。
- `lib/engine/ffmpeg_backend_factory.dart`：按平台选 `FfmpegKitBackend` / `FfmpegOhosBackend`。
- `ohos/entry/src/main/ets/plugins/FFmpegBridge.ets`：基于 `@ohos/ffmpeg-kit` v1.0.1
  **真实的函数式 NAPI API**（`ffmpegSession` / `asyncFFmpegSessionExecute` /
  `enableStatisticsCallback` / `cancelSession` / `abstractSessionGetReturnCode`…），
  回调经 emitter 回主线程再回 Dart。
- 说明与风险见 `docs/OHOS_FFMPEG.md`；许可见 `THIRD_PARTY_NOTICES.md` §1.1。

### 4. 格式表（`assets/formats.yaml`，95 个格式条目 / 49 条显式 flows）

- 新增 `woff`，并补 6 个「形态类」伪格式（`qr_png`、`identicon_png`、`ascii_art`、
  `braille_art`、`waveform_png`、`spectrogram_png`）——与普通图片共享扩展名但与
  普通格式分开登记，避免源文件识别歧义。
- 真实化各格式 `engines` / `status` / `accepts_from`（68 ready / 19 plugin / 8 planned）。
- 显式 flows 补齐跨类型：image_to_svg / image_to_palette / image_to_docx /
  model3d_to_image / mesh_to_image / model3d_to_geojson / audio_to_waveform /
  audio_to_spectrogram / audio_to_video / video_to_image / audio_to_midi /
  embroidery_to_image / image_to_embroidery / gps_to_image / gps_to_svg /
  slides_to_text / text_to_tts / image_to_ocr / audio_to_asr / pdf_to_image / archive_extract。

### 5. 规划器修正（`lib/engine/conversion_planner.dart`）

- 代价函数：`不可用引擎×100 + 跳数×10 + 隐式边×2` → 同跳数优先显式 flows，
  避免「pptx → txt」被绕到「任意文件 → 二维码 PNG → PDF」这类万能边。
- 显式 flow 覆盖同 (source, target, engine) 的隐式边。

### 6. 依赖与服务层

- `engine_providers.dart`：`pluginInstallDirProvider`（main.dart 用 path_provider 注入）、
  `nativePluginRegistryProvider`、`engineRegistryProvider`（注入原生后端 + 插件注册表）。
- `engine_registry.dart`：36 个引擎（35 纯 Dart/原生 FFmpeg + 6 插件引擎），
  `platformDefaults({ffmpegBackend, plugins})`。

## 四、验证记录

```bash
dart analyze lib test tool            # 0 error / 0 warning（仅 info 级 lint）
dart run tool/check_formats.dart      # ✓ 结构自检全部通过
dart run tool/check_engines.dart      # 36 个引擎 / 31 个可直接运行，链路 + 6 组真实转换通过
dart run tool/check_crosstype.dart    # 15 项跨类型真实转换 + 插件诚实提示，全部通过
```

- 真实输出样本：png→svg 191B、png→gpl 79B、png→docx 1931B、png→dst 521B、
  obj→png 4885B（PNG 魔数）、obj→geojson 1276B、gpx→svg 457B、gpx→png 7041B、
  txt→qr_png 2586B、txt→identicon_png 1537B、dst→png 82B。
- 子代理自检脚本亦在 `tool/verify_*.dart`（art/img/geo/office/plugin/media/r3d），
  合计 200+ 条断言。

## 五、注意 / 下一轮

1. **本机无 Flutter（aarch64 容器）**，`flutter test` / 打包只能在 CI；上述校验用
   arm64 Dart SDK + 手工 package_config 完成。
2. **CI 工作流**：`.github/workflows/ci.yml` 仍未推送（PAT 缺 `workflow` scope），
   需带 workflow 权限的 PAT 才能提交；`build.yml` 也需权限才能修
   linux（`libjson-glib-dev`）/linux-arm64/windows-arm64（上游无 aarch64 产物）/
   ohos（工具链下载）的降级策略。
3. 已知限制：视频 → 字幕只抽内嵌轨（语音识别需 asr 插件）；PDF → 文本仅覆盖
   常见文本内容流；woff2 需插件；PES 不写缩略图段；复音音频转 MIDI 会退化。
4. 插件二进制不随仓库分发：ABI 与导入方式见 `THIRD_PARTY_NOTICES.md` §1.2。
