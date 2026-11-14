# THIRD_PARTY_NOTICES

OmniForge 应用代码以 MIT 许可证发布。应用打包、链接或调用以下第三方组件，
其许可证与义务一并列明。分发二进制时请保留本文件及对应许可证全文。

## 1. FFmpeg（经 FFmpegKitNext 提供）

- 用途：音视频解码 / 编码 / 转封装 / 抽帧 / 字幕抽取（`lib/engine/engines/ffmpeg_engine.dart`
  经 `lib/engine/ffmpeg_kit_backend.dart` 调用）。
- 形式：随应用分发的预编译原生库（Android `.so`、Windows `.dll`、macOS/iOS `.dylib`/framework、
  Linux `.so`），由 FFmpegKitNext 自编并经 `third_party/ffmpeg_kit_next` 插件打包；应用**不调用 ffmpeg 命令行**。
- 版本：FFmpeg 8.x（FFmpegKitNext v9.0.2 / FFmpeg 8.1.x 内核）。
- 许可证：**LGPL v3**（所选为 full build 的 LGPL 变体，未启用 `--enable-gpl`）。
  - LGPL 文本：https://www.gnu.org/licenses/lgpl-3.0.html
  - FFmpeg 源码：https://ffmpeg.org/download.html
  - 构建脚本 / 原生包：https://github.com/anton-karpenko/ffmpeg-kit-flutter-new
- LGPL 义务提示：
  - 以动态库形式链接（本应用即如此），用户可自行替换为兼容版本的 FFmpeg 库；
  - 分发时需附许可证文本与本声明，并提供获取对应 FFmpeg 源码的途径；
  - 不得移除库中的版权与许可证声明。

### 1.1 鸿蒙（OHOS）音视频后端（@ohos/ffmpeg-kit）

- 用途：鸿蒙平台上替代 ffmpeg_kit 提供音视频转换能力。调用链：
  `lib/engine/engines/ffmpeg_engine.dart` → `lib/engine/ffmpeg_ohos_backend.dart`
  → MethodChannel `omniforge/ffmpeg` → ArkTS 桥接
  `ohos/entry/src/main/ets/plugins/FFmpegBridge.ets` → NAPI 原生库。
- 形式：ohpm 依赖 `@ohos/ffmpeg-kit` **v1.0.1**（FFmpegKit 的 OpenHarmony 移植，
  随包提供预编译 `libs/arm64-v8a/libffmpegkit_napi.so`，内含 libav* 全套），
  **应用不启动命令行进程、不依赖系统 ffmpeg 可执行文件**。
- 许可证：
  - 移植层：上游仓库 README / LICENSE 标注 **MIT**；ohpm 发布包 `oh-package.json5`
    的 `license` 字段写作 **LGPL-3.0**。两者不一致，保守按 MIT + LGPL 双重义务处理，
    升级依赖时需复核实际许可证文本。
  - 内含 FFmpeg：**LGPL v3**（full build，未启用 `--enable-gpl`），义务与 §1 相同。
- 源码 / 下载地址：
  - 移植仓库：https://gitcode.com/CPF-ApplicationTPC/ohos_ffmpeg_kit
  - ohpm 包名 / 版本：`@ohos/ffmpeg-kit` / `1.0.1`
  - FFmpeg 源码：https://ffmpeg.org/download.html
  - FFmpegKit 上游（参考）：https://github.com/arthenica/ffmpeg-kit
- 说明：FFmpegKit 上游（arthenica/ffmpeg-kit、其后继 arthenica/ffmpeg-kit-next）已停止
  发布公开二进制包且未提供 OHOS 产物，鸿蒙能力由上述移植项目提供（C++ + NAPI，
  原生 ThreadPool 执行，非 fork/exec）。
- 义务提示：动态库链接、可替换；分发时附 LGPL 文本与本声明并提供 FFmpeg 对应源码获取
  途径；保留移植层与 FFmpeg 的版权声明。详见 `docs/OHOS_FFMPEG.md` §8。

### 1.2 原生转换插件（用户导入，不随应用分发）

- 设置页「转换插件」允许用户导入 `.so` / `.dll` / `.dylib`，统一 ABI：
  `int omniforge_convert(const char* input, const char* output,
  const char* paramsJson, char* errbuf, int errlen)`。
- 插件由用户/第三方提供，其许可证由各自作者决定；应用仅做加载与调用，
  不在仓库或安装包内分发任何插件二进制。

## 2. Dart / Flutter 依赖（pub.dev）

| 包 | 许可证 | 用途 |
| --- | --- | --- |
| flutter / flutter_riverpod | BSD-3-Clause / MIT | 框架与状态管理 |
| image | MIT | 图片编解码 |
| archive | MIT | zip / tar / gzip |
| xml | MIT | OOXML / EPUB / GPX 等 |
| pdf | Apache-2.0 | PDF 生成 |
| crypto | BSD-3-Clause | 哈希 |
| markdown | BSD-3-Clause | Markdown → HTML |
| csv | MIT | CSV 解析 |
| path | BSD-3-Clause | 路径处理 |
| yaml | MIT | 格式表加载 |
| ffi（间接） | Apache-2.0 | 原生库绑定 |

完整依赖清单与版本见 `pubspec.lock`；各包许可证文本位于 pub 缓存包目录内。

## 3. 明确不提供的功能

NCM / KGM / QMC 等私有加密音乐格式的解密不在本项目中实现（涉及绕过版权保护），
相关格式在格式表中标记为 `plugin` 并给出说明。
