# THIRD_PARTY_NOTICES

OmniForge 应用代码以 MIT 许可证发布。应用打包、链接或调用以下第三方组件，
其许可证与义务一并列明。分发二进制时请保留本文件及对应许可证全文。

## 1. FFmpeg（经 ffmpeg_kit_flutter_new_full 提供）

- 用途：音视频解码 / 编码 / 转封装 / 抽帧 / 字幕抽取（`lib/engine/engines/ffmpeg_engine.dart`
  经 `lib/engine/ffmpeg_kit_backend.dart` 调用）。
- 形式：随应用分发的预编译原生库（Android `.so`、Windows `.dll`、macOS/iOS `.dylib`/framework、
  Linux `.so`），由 `ffmpeg_kit_flutter_new_full` 打包；应用**不调用 ffmpeg 命令行**。
- 版本：FFmpeg 6.x（以 `ffmpeg_kit_flutter_new_full 2.5.8` 内置版本为准）。
- 许可证：**LGPL v3**（所选为 full build 的 LGPL 变体，未启用 `--enable-gpl`）。
  - LGPL 文本：https://www.gnu.org/licenses/lgpl-3.0.html
  - FFmpeg 源码：https://ffmpeg.org/download.html
  - 构建脚本 / 原生包：https://github.com/anton-karpenko/ffmpeg-kit-flutter-new
- LGPL 义务提示：
  - 以动态库形式链接（本应用即如此），用户可自行替换为兼容版本的 FFmpeg 库；
  - 分发时需附许可证文本与本声明，并提供获取对应 FFmpeg 源码的途径；
  - 不得移除库中的版权与许可证声明。

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
