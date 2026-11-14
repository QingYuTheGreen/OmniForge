# 转换算法库（ENGINE_LIBRARY）

本项目对「转换方法」采取两条原则（来自产品要求）：

1. **有成熟现成库的，直接用现成库**，不自写；
2. **没有现成 Dart/Flutter 库的，把转换算法写成可复用库**（独立于 UI、可单测、可被多个引擎共享），
   并注明算法依据（官方规范 / 公开技术文章），代码复用率优先。

## 一、采用的上游库

| 领域 | 采用 | 理由 |
| --- | --- | --- |
| 图片编解码 | `image` 4.x | 纯 Dart、跨平台、社区使用最广；支持 png/jpg/gif/webp/bmp/tiff/ico/tga/psd/pvr/exr 解码 |
| ZIP / tar / gzip | `archive` 4.x | 纯 Dart，OOXML/EPUB/Minecraft 都依赖它 |
| XML | `xml` 7.x | OOXML、EPUB、GPX/KML/TCX、SVG 容器通用 |
| PDF 生成 | `pdf` 3.x | 纯 Dart 生成 PDF，可内嵌 TTF 字体 |
| 哈希 | `crypto` 3.x | 官方包，md5/sha1/sha256/sha512 |
| Markdown → HTML | `markdown` 7.x | 官方包 |
| CSV | `csv` 6.x | 社区标准 |
| 音视频 | `ffmpeg_kit_flutter_new_full` 2.5.8 | 随包内置 LGPL FFmpeg 原生库（so/dll/dylib），跨 Android/iOS/macOS/Windows/Linux，不调用命令行 |

### 评估后放弃的库（避免踩坑）

| 候选 | 放弃原因 |
| --- | --- |
| `html2md` | SDK 约束 `<3.0.0`，无法在 Dart 3 编译 |
| `excel` 4.0.6 | 依赖 `archive ^3.6.1`，与 `image` 需要的 `archive ^4.0.10` 冲突 |
| `pdf_text` 0.5.0 | 2021 年后停更，只做纯 Dart 文本抽取，质量不如自写的小型解析器 |
| `ffmpeg_kit_flutter` | 上游已归档（isDiscontinued） |
| 任何把 `ffmpeg` 可执行文件打到包里的方案 | 移动端无进程权限且违反"不调用命令行"的要求 |

## 二、自写算法库（`lib/engine/common/`）

这些模块没有可用的 Dart 库，因此按公开规范实现，并被多个引擎共享：

- `binary_io.dart`：`ByteReader` / `ByteWriter`（u8/u16/u32/f32/UTF-16BE、hex）。
  被纹理（DDS/KTX 头）、调色板（ASE/ACO 二进制）、哈希输出复用。
- `package_io.dart`：`ZipPackage`（读/写/按名取文本），被 docx、xlsx、epub、
  Minecraft 存档、压缩包五个引擎共享，避免重复的 `ZipDecoder` 样板。
- `text_format.dart`：HTML ↔ 文本 ↔ Markdown 的纯函数库（`stripHtml`、
  `htmlToMarkdown`、`textToHtml`、`splitParagraphs`、`escapeHtml`、`escapeXml`），
  被文本、文档、电子书、PDF 引擎共享。

## 三、各格式算法依据

| 格式 | 实现依据 |
| --- | --- |
| DDS | Microsoft DirectDraw Surface 规范：DXT1/3/5 块压缩解码（4×4 块、颜色插值、alpha 模式），未压缩 RGB24/RGBA32 掩码解析；写出为未压缩 BGRA8 DDS 头（124 字节头 + 128 偏移像素数据） |
| KTX | Khronos KTX 1.x 规范：12 字节标识、`endianness`、`glInternalFormat`、像素数据起始 64+KV 字节 |
| ASE | Adobe Swatch Exchange：`ASEF` 魔数、块类型 `0x0001` 颜色 / `0xC001` 组、UTF-16BE 名称、RGB 为 float32 |
| ACO | Adobe Color：版本 1、颜色空间字段与 Lab → sRGB（D50 白点）换算 |
| GPL | GIMP 调色板纯文本格式 |
| DXT 细节 | 参考公开实现说明（如 Microsoft D3D 文档、Wikipedia S3TC 条目、Doom9/Wolfire 纹理工具文章）；本实现为独立编写，未拷代码 |
| OOXML docx | ECMA-376：`word/document.xml` 段落 `w:p` / 文本 `w:t` / 样式 `w:pStyle`；写出最小包（`[Content_Types].xml`、`_rels`、`word/*`、`docProps/core.xml`） |
| OOXML xlsx | ECMA-376：`xl/sharedStrings.xml`、`xl/worksheets/sheet1.xml`（inlineStr / shared string / 数值），写出最小包 |
| EPUB | EPUB 3：`META-INF/container.xml` → `content.opf`（manifest + spine）→ 按 spine 读章节，`stripHtml` 后输出 |
| RTF | RTF 1.x 控制字扫描：`\par` `\line` `\tab` `\'hh` `\uN`，写出 `\u<code>?` 以兼容中文 |
| PDF 读文本 | PDF 1.7：扫描 `stream`/`endstream`，`ZLib` 解压内容流，抽取 `(...)Tj` / `[...]TJ` 字符串（含八进制转义） |
| glTF / GLB | Khronos glTF 2.0：accessor（5126 float / 5125 uint32）、bufferView、mesh primitive modes；GLB 12 字节头 + JSON/BIN 分块 |
| STL | 二进制 80 字节头 + 50 字节三角面；ASCII `facet normal` 解析 |
| PLY | ascii / binary_little_endian，`element vertex/face` + `property list` |
| OFF | 头行 `OFF` + 顶点/面计数 |
| SRT / VTT / ASS / LRC | 各自官方/事实标准时间轴与块语法（ASS 用 `Dialogue` 逗号分段、`\N` 换行、`{...}` 标签剥离） |
| GPX / KML / TCX / GeoJSON | OGC GPX 1.1、KML 2.2、Garmin TCX 2（Trackpoint 元素）、RFC 7946 |
| M3U / M3U8 / CUE | `#EXTINF` 扩展 M3U；CUE `FILE`/`TRACK`/`INDEX 01 mm:ss:ff` 时间换算 |
| Minecraft 包 | Bedrock `manifest.json`（含稳定 UUID）+ `resource_packs/` `behavior_packs/` 目录约定 |
| 哈希 / base64 | MD5/SHA（`crypto`）、CRC32（IEEE 多项式查表）、Base64（`dart:convert`） |

> 私有加密格式（NCM / KGM / QMC）**不做解密**：这类格式的解密属于绕过版权保护，
> 项目明确拒绝实现，UI 会给出说明而不是输出损坏文件。

## 四、复用方式

```dart
// 任意格式 → 任意格式：交给规划器和执行服务
final plan = planner.plan('docx', 'md');
final events = service.convert(plan: plan!, inputPath: ..., outputPath: ...);

// 单独复用算法库（无需引擎/UI）
final package = ZipPackage.decode(bytes);
final text = HtmlToMarkdown.convert(html);   // text_format.dart 内的纯函数
```

新增格式时：在 `common/` 里补充算法 → 在 `engines/` 里加薄引擎（继承 `SimpleEngine`）
→ 在 `assets/formats.yaml` 登记 → 跑 `dart run tool/check_engines.dart`。
