# 格式转换矩阵（由代码生成）

> 本文档由 `tool/gen_conversion_matrix.dart` 从 `assets/formats.yaml`、
> `lib/engine/engine_registry.dart`、`lib/engine/conversion_planner.dart` 实际计算生成，
> 与运行时 App 内「输出格式」列表完全一致。修改 YAML 或引擎后重新生成即可。

- 生成命令：`dart run tool/gen_conversion_matrix.dart > docs/CONVERSION_MATRIX.md`
- 格式条目：95；类别：19；显式链路：43；已注册引擎：33（可直接运行 32）

## 0. 转换是怎么算出来的

所有转换都归约为一个公式：**读取源格式 → 中间表示（IR）→ 写出目标格式**。
App 不猜「格式对格式」的 if-else 大表，而是把每个引擎注册成图里的一条有向边，
再用 BFS 找一条最省的路径：

1. **显式边（flows）**：YAML `flows:` 里写明「源格式组 → 目标格式组，由某引擎负责」，
   带该链路的默认参数（如 `image_to_image` 的 width/height/quality）。
2. **隐式边（引擎读写能力表）**：`lib/engine/engine_capabilities.dart` 为每个引擎声明
   「能读哪些格式 id → 能写哪些格式 id」，只有两者都成立才建边；不按类别名猜，
   所以不会出现「公文包 → 二维码 → PNG」这种引擎根本无法执行的链路。
3. **多跳**：没有直转时最多拼接 2 跳，例如 `epub → txt → md`、`docx → pdf`（经 txt）。
4. **代价函数**：`不可用引擎 ×100 + 跳数 ×10 + 隐式边 ×2`，即优先用可运行引擎、优先少跳、
   优先走 YAML 显式声明的链路（同跳数时显式边胜过隐式边）。
5. 每条边最终落到一个 `IEngine` 实现；多步由 `ConversionService` 用临时文件中转，
   进度按步数加权聚合，任一步失败即中断。

**可用性标记**：✅ 引擎可直接运行；⏳ 当前环境缺少内置原生库（正常安装包内置，不会出现）

## 1. 类别 × 类别 可达数量（行=源，列=目标，数字=可达格式数）

| 源 \ 目标 | 图像 | 音频 | 视频 | 电子书 | 文档 | 幻灯片 | 表格 | 字体 | 调色板 | 3D 模型 | 纹理 | 网格 | 哈希计算 | 绣花 | GPS | 字幕 | 播放列表 | 压缩包 | 我的世界专区 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 图像 | 85 | 0 | 0 | 0 | 42 | 0 | 28 | 0 | 21 | 0 | 21 | 0 | 44 | 21 | 0 | 0 | 0 | 0 | 0 |
| 音频 | 53 | 42 | 42 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 40 | 0 | 0 | 7 | 0 | 0 | 0 |
| 视频 | 84 | 42 | 30 | 0 | 12 | 0 | 6 | 0 | 18 | 0 | 18 | 0 | 24 | 18 | 0 | 18 | 0 | 0 | 0 |
| 电子书 | 6 | 0 | 0 | 0 | 6 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 12 | 0 | 0 | 0 | 0 | 0 | 0 |
| 文档 | 12 | 0 | 0 | 0 | 30 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 24 | 0 | 0 | 0 | 0 | 0 | 0 |
| 幻灯片 | 4 | 0 | 0 | 0 | 12 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 8 | 0 | 0 | 0 | 0 | 0 | 0 |
| 表格 | 21 | 0 | 0 | 0 | 2 | 0 | 12 | 0 | 12 | 0 | 3 | 0 | 16 | 3 | 0 | 0 | 0 | 0 | 0 |
| 字体 | 10 | 0 | 0 | 0 | 0 | 0 | 0 | 20 | 0 | 0 | 0 | 0 | 20 | 0 | 0 | 0 | 0 | 0 | 0 |
| 调色板 | 36 | 0 | 0 | 0 | 6 | 0 | 12 | 0 | 6 | 0 | 9 | 0 | 12 | 9 | 0 | 0 | 0 | 0 | 0 |
| 3D 模型 | 52 | 0 | 0 | 0 | 8 | 0 | 4 | 0 | 12 | 16 | 12 | 8 | 24 | 12 | 0 | 0 | 0 | 0 | 0 |
| 纹理 | 40 | 0 | 0 | 0 | 6 | 0 | 3 | 0 | 9 | 0 | 6 | 0 | 20 | 9 | 0 | 0 | 0 | 0 | 0 |
| 网格 | 24 | 0 | 0 | 0 | 4 | 0 | 2 | 0 | 6 | 10 | 6 | 2 | 8 | 6 | 0 | 0 | 0 | 0 | 0 |
| 哈希计算 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 绣花 | 36 | 0 | 0 | 0 | 6 | 0 | 3 | 0 | 9 | 0 | 9 | 0 | 12 | 6 | 0 | 0 | 0 | 0 | 0 |
| GPS | 48 | 0 | 0 | 0 | 8 | 0 | 4 | 0 | 12 | 0 | 12 | 0 | 16 | 12 | 12 | 0 | 0 | 0 | 0 |
| 字幕 | 8 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 16 | 0 | 0 | 12 | 0 | 0 | 0 |
| 播放列表 | 6 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 12 | 0 | 0 | 0 | 6 | 0 | 0 |
| 压缩包 | 8 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 16 | 0 | 0 | 0 | 0 | 2 | 8 |
| 我的世界专区 | 8 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 16 | 0 | 0 | 0 | 0 | 0 | 12 |

可达 (源,目标) 组合总数（不含同格式自身）：**1685**

## 2. 每种格式能转成什么（含引擎链路）

### 图像（image）


#### `jpg`（.jpg） - ✅ 可读

- **直转**：
  - `jpg` → `aco` ✅ `image_palette`
  - `jpg` → `ascii_art` ✅ `ascii_art`
  - `jpg` → `ase` ✅ `image_palette`
  - `jpg` → `base64` ✅ `hash`
  - `jpg` → `bmp` ✅ `image`
  - `jpg` → `braille_art` ✅ `ascii_art`
  - `jpg` → `crc` ✅ `hash`
  - `jpg` → `dds` ✅ `texture`
  - `jpg` → `docx` ✅ `image_doc`
  - `jpg` → `dst` ✅ `embroidery`
  - `jpg` → `gif` ✅ `image`
  - `jpg` → `gpl` ✅ `image_palette`
  - `jpg` → `ico` ✅ `image`
  - `jpg` → `identicon_png` ✅ `identicon`
  - `jpg` → `jef` ✅ `embroidery`
  - `jpg` → `json` ✅ `image_palette`
  - `jpg` → `ktx` ✅ `texture`
  - `jpg` → `md5` ✅ `hash`
  - `jpg` → `pdf` ✅ `pdf`
  - `jpg` → `pes` ✅ `embroidery`
  - `jpg` → `png` ✅ `image`
  - `jpg` → `qr_png` ✅ `qr`
  - `jpg` → `sha` ✅ `hash`
  - `jpg` → `svg` ✅ `svg_vector`
  - `jpg` → `tga` ✅ `texture`
  - `jpg` → `tiff` ✅ `image`
  - `jpg` → `webp` ✅ `image`
- **多跳**（最多 2 跳）：
  - `jpg` → `csv` ✅ jpg --[image_palette]--> json --[spreadsheet]--> csv
  - `jpg` → `html` ✅ jpg --[image_doc]--> docx --[document]--> html
  - `jpg` → `md` ✅ jpg --[image_doc]--> docx --[document]--> md
  - `jpg` → `rtf` ✅ jpg --[image_doc]--> docx --[document]--> rtf
  - `jpg` → `txt` ✅ jpg --[pdf]--> pdf --[pdf]--> txt
  - `jpg` → `xlsx` ✅ jpg --[image_palette]--> json --[spreadsheet]--> xlsx
  - `jpg` → `xml` ✅ jpg --[image_palette]--> json --[spreadsheet]--> xml

#### `png`（.png） - ✅ 可读

- **直转**：
  - `png` → `aco` ✅ `image_palette`
  - `png` → `ascii_art` ✅ `ascii_art`
  - `png` → `ase` ✅ `image_palette`
  - `png` → `base64` ✅ `hash`
  - `png` → `bmp` ✅ `image`
  - `png` → `braille_art` ✅ `ascii_art`
  - `png` → `crc` ✅ `hash`
  - `png` → `dds` ✅ `texture`
  - `png` → `docx` ✅ `image_doc`
  - `png` → `dst` ✅ `embroidery`
  - `png` → `gif` ✅ `image`
  - `png` → `gpl` ✅ `image_palette`
  - `png` → `ico` ✅ `image`
  - `png` → `identicon_png` ✅ `identicon`
  - `png` → `jef` ✅ `embroidery`
  - `png` → `jpg` ✅ `image`
  - `png` → `json` ✅ `image_palette`
  - `png` → `ktx` ✅ `texture`
  - `png` → `md5` ✅ `hash`
  - `png` → `pdf` ✅ `pdf`
  - `png` → `pes` ✅ `embroidery`
  - `png` → `qr_png` ✅ `qr`
  - `png` → `sha` ✅ `hash`
  - `png` → `svg` ✅ `svg_vector`
  - `png` → `tga` ✅ `texture`
  - `png` → `tiff` ✅ `image`
  - `png` → `webp` ✅ `image`
- **多跳**（最多 2 跳）：
  - `png` → `csv` ✅ png --[image_palette]--> json --[spreadsheet]--> csv
  - `png` → `html` ✅ png --[image_doc]--> docx --[document]--> html
  - `png` → `md` ✅ png --[image_doc]--> docx --[document]--> md
  - `png` → `rtf` ✅ png --[image_doc]--> docx --[document]--> rtf
  - `png` → `txt` ✅ png --[pdf]--> pdf --[pdf]--> txt
  - `png` → `xlsx` ✅ png --[image_palette]--> json --[spreadsheet]--> xlsx
  - `png` → `xml` ✅ png --[image_palette]--> json --[spreadsheet]--> xml

#### `webp`（.webp） - ✅ 可读

- **直转**：
  - `webp` → `aco` ✅ `image_palette`
  - `webp` → `ascii_art` ✅ `ascii_art`
  - `webp` → `ase` ✅ `image_palette`
  - `webp` → `base64` ✅ `hash`
  - `webp` → `bmp` ✅ `image`
  - `webp` → `braille_art` ✅ `ascii_art`
  - `webp` → `crc` ✅ `hash`
  - `webp` → `dds` ✅ `texture`
  - `webp` → `docx` ✅ `image_doc`
  - `webp` → `dst` ✅ `embroidery`
  - `webp` → `gif` ✅ `image`
  - `webp` → `gpl` ✅ `image_palette`
  - `webp` → `ico` ✅ `image`
  - `webp` → `identicon_png` ✅ `identicon`
  - `webp` → `jef` ✅ `embroidery`
  - `webp` → `jpg` ✅ `image`
  - `webp` → `json` ✅ `image_palette`
  - `webp` → `ktx` ✅ `texture`
  - `webp` → `md5` ✅ `hash`
  - `webp` → `pdf` ✅ `pdf`
  - `webp` → `pes` ✅ `embroidery`
  - `webp` → `png` ✅ `image`
  - `webp` → `qr_png` ✅ `qr`
  - `webp` → `sha` ✅ `hash`
  - `webp` → `svg` ✅ `svg_vector`
  - `webp` → `tga` ✅ `texture`
  - `webp` → `tiff` ✅ `image`
- **多跳**（最多 2 跳）：
  - `webp` → `csv` ✅ webp --[image_palette]--> json --[spreadsheet]--> csv
  - `webp` → `html` ✅ webp --[image_doc]--> docx --[document]--> html
  - `webp` → `md` ✅ webp --[image_doc]--> docx --[document]--> md
  - `webp` → `rtf` ✅ webp --[image_doc]--> docx --[document]--> rtf
  - `webp` → `txt` ✅ webp --[pdf]--> pdf --[pdf]--> txt
  - `webp` → `xlsx` ✅ webp --[image_palette]--> json --[spreadsheet]--> xlsx
  - `webp` → `xml` ✅ webp --[image_palette]--> json --[spreadsheet]--> xml

#### `heic`（.heic） - ❌ 暂不支持

- **直转**：
  - `heic` → `base64` ✅ `hash`
  - `heic` → `crc` ✅ `hash`
  - `heic` → `identicon_png` ✅ `identicon`
  - `heic` → `md5` ✅ `hash`
  - `heic` → `qr_png` ✅ `qr`
  - `heic` → `sha` ✅ `hash`

#### `svg`（.svg） - ✅ 可读

- **直转**：
  - `svg` → `base64` ✅ `hash`
  - `svg` → `crc` ✅ `hash`
  - `svg` → `identicon_png` ✅ `identicon`
  - `svg` → `md5` ✅ `hash`
  - `svg` → `qr_png` ✅ `qr`
  - `svg` → `sha` ✅ `hash`

#### `gif`（.gif） - ✅ 可读

- **直转**：
  - `gif` → `aco` ✅ `image_palette`
  - `gif` → `ascii_art` ✅ `ascii_art`
  - `gif` → `ase` ✅ `image_palette`
  - `gif` → `base64` ✅ `hash`
  - `gif` → `bmp` ✅ `image`
  - `gif` → `braille_art` ✅ `ascii_art`
  - `gif` → `crc` ✅ `hash`
  - `gif` → `dds` ✅ `texture`
  - `gif` → `docx` ✅ `image_doc`
  - `gif` → `dst` ✅ `embroidery`
  - `gif` → `gpl` ✅ `image_palette`
  - `gif` → `ico` ✅ `image`
  - `gif` → `identicon_png` ✅ `identicon`
  - `gif` → `jef` ✅ `embroidery`
  - `gif` → `jpg` ✅ `image`
  - `gif` → `json` ✅ `image_palette`
  - `gif` → `ktx` ✅ `texture`
  - `gif` → `md5` ✅ `hash`
  - `gif` → `pdf` ✅ `pdf`
  - `gif` → `pes` ✅ `embroidery`
  - `gif` → `png` ✅ `image`
  - `gif` → `qr_png` ✅ `qr`
  - `gif` → `sha` ✅ `hash`
  - `gif` → `svg` ✅ `svg_vector`
  - `gif` → `tga` ✅ `texture`
  - `gif` → `tiff` ✅ `image`
  - `gif` → `webp` ✅ `image`
- **多跳**（最多 2 跳）：
  - `gif` → `csv` ✅ gif --[image_palette]--> json --[spreadsheet]--> csv
  - `gif` → `html` ✅ gif --[image_doc]--> docx --[document]--> html
  - `gif` → `md` ✅ gif --[image_doc]--> docx --[document]--> md
  - `gif` → `rtf` ✅ gif --[image_doc]--> docx --[document]--> rtf
  - `gif` → `txt` ✅ gif --[image_doc]--> docx --[document]--> txt
  - `gif` → `xlsx` ✅ gif --[image_palette]--> json --[spreadsheet]--> xlsx
  - `gif` → `xml` ✅ gif --[image_palette]--> json --[spreadsheet]--> xml

#### `bmp`（.bmp） - ✅ 可读

- **直转**：
  - `bmp` → `aco` ✅ `image_palette`
  - `bmp` → `ascii_art` ✅ `ascii_art`
  - `bmp` → `ase` ✅ `image_palette`
  - `bmp` → `base64` ✅ `hash`
  - `bmp` → `braille_art` ✅ `ascii_art`
  - `bmp` → `crc` ✅ `hash`
  - `bmp` → `dds` ✅ `texture`
  - `bmp` → `docx` ✅ `image_doc`
  - `bmp` → `dst` ✅ `embroidery`
  - `bmp` → `gif` ✅ `image`
  - `bmp` → `gpl` ✅ `image_palette`
  - `bmp` → `ico` ✅ `image`
  - `bmp` → `identicon_png` ✅ `identicon`
  - `bmp` → `jef` ✅ `embroidery`
  - `bmp` → `jpg` ✅ `image`
  - `bmp` → `json` ✅ `image_palette`
  - `bmp` → `ktx` ✅ `texture`
  - `bmp` → `md5` ✅ `hash`
  - `bmp` → `pdf` ✅ `pdf`
  - `bmp` → `pes` ✅ `embroidery`
  - `bmp` → `png` ✅ `image`
  - `bmp` → `qr_png` ✅ `qr`
  - `bmp` → `sha` ✅ `hash`
  - `bmp` → `svg` ✅ `svg_vector`
  - `bmp` → `tga` ✅ `texture`
  - `bmp` → `tiff` ✅ `image`
  - `bmp` → `webp` ✅ `image`
- **多跳**（最多 2 跳）：
  - `bmp` → `csv` ✅ bmp --[image_palette]--> json --[spreadsheet]--> csv
  - `bmp` → `html` ✅ bmp --[image_doc]--> docx --[document]--> html
  - `bmp` → `md` ✅ bmp --[image_doc]--> docx --[document]--> md
  - `bmp` → `rtf` ✅ bmp --[image_doc]--> docx --[document]--> rtf
  - `bmp` → `txt` ✅ bmp --[pdf]--> pdf --[pdf]--> txt
  - `bmp` → `xlsx` ✅ bmp --[image_palette]--> json --[spreadsheet]--> xlsx
  - `bmp` → `xml` ✅ bmp --[image_palette]--> json --[spreadsheet]--> xml

#### `tiff`（.tiff） - ✅ 可读

- **直转**：
  - `tiff` → `aco` ✅ `image_palette`
  - `tiff` → `ascii_art` ✅ `ascii_art`
  - `tiff` → `ase` ✅ `image_palette`
  - `tiff` → `base64` ✅ `hash`
  - `tiff` → `bmp` ✅ `image`
  - `tiff` → `braille_art` ✅ `ascii_art`
  - `tiff` → `crc` ✅ `hash`
  - `tiff` → `dds` ✅ `texture`
  - `tiff` → `docx` ✅ `image_doc`
  - `tiff` → `dst` ✅ `embroidery`
  - `tiff` → `gif` ✅ `image`
  - `tiff` → `gpl` ✅ `image_palette`
  - `tiff` → `ico` ✅ `image`
  - `tiff` → `identicon_png` ✅ `identicon`
  - `tiff` → `jef` ✅ `embroidery`
  - `tiff` → `jpg` ✅ `image`
  - `tiff` → `json` ✅ `image_palette`
  - `tiff` → `ktx` ✅ `texture`
  - `tiff` → `md5` ✅ `hash`
  - `tiff` → `pdf` ✅ `pdf`
  - `tiff` → `pes` ✅ `embroidery`
  - `tiff` → `png` ✅ `image`
  - `tiff` → `qr_png` ✅ `qr`
  - `tiff` → `sha` ✅ `hash`
  - `tiff` → `svg` ✅ `svg_vector`
  - `tiff` → `tga` ✅ `texture`
  - `tiff` → `webp` ✅ `image`
- **多跳**（最多 2 跳）：
  - `tiff` → `csv` ✅ tiff --[image_palette]--> json --[spreadsheet]--> csv
  - `tiff` → `html` ✅ tiff --[image_doc]--> docx --[document]--> html
  - `tiff` → `md` ✅ tiff --[image_doc]--> docx --[document]--> md
  - `tiff` → `rtf` ✅ tiff --[image_doc]--> docx --[document]--> rtf
  - `tiff` → `txt` ✅ tiff --[pdf]--> pdf --[pdf]--> txt
  - `tiff` → `xlsx` ✅ tiff --[image_palette]--> json --[spreadsheet]--> xlsx
  - `tiff` → `xml` ✅ tiff --[image_palette]--> json --[spreadsheet]--> xml

#### `ico`（.ico） - ✅ 可读

- **直转**：
  - `ico` → `aco` ✅ `image_palette`
  - `ico` → `ascii_art` ✅ `ascii_art`
  - `ico` → `ase` ✅ `image_palette`
  - `ico` → `base64` ✅ `hash`
  - `ico` → `bmp` ✅ `image`
  - `ico` → `braille_art` ✅ `ascii_art`
  - `ico` → `crc` ✅ `hash`
  - `ico` → `dds` ✅ `texture`
  - `ico` → `docx` ✅ `image_doc`
  - `ico` → `dst` ✅ `embroidery`
  - `ico` → `gif` ✅ `image`
  - `ico` → `gpl` ✅ `image_palette`
  - `ico` → `identicon_png` ✅ `identicon`
  - `ico` → `jef` ✅ `embroidery`
  - `ico` → `jpg` ✅ `image`
  - `ico` → `json` ✅ `image_palette`
  - `ico` → `ktx` ✅ `texture`
  - `ico` → `md5` ✅ `hash`
  - `ico` → `pdf` ✅ `pdf`
  - `ico` → `pes` ✅ `embroidery`
  - `ico` → `png` ✅ `image`
  - `ico` → `qr_png` ✅ `qr`
  - `ico` → `sha` ✅ `hash`
  - `ico` → `svg` ✅ `svg_vector`
  - `ico` → `tga` ✅ `texture`
  - `ico` → `tiff` ✅ `image`
  - `ico` → `webp` ✅ `image`
- **多跳**（最多 2 跳）：
  - `ico` → `csv` ✅ ico --[image_palette]--> json --[spreadsheet]--> csv
  - `ico` → `html` ✅ ico --[image_doc]--> docx --[document]--> html
  - `ico` → `md` ✅ ico --[image_doc]--> docx --[document]--> md
  - `ico` → `rtf` ✅ ico --[image_doc]--> docx --[document]--> rtf
  - `ico` → `txt` ✅ ico --[image_doc]--> docx --[document]--> txt
  - `ico` → `xlsx` ✅ ico --[image_palette]--> json --[spreadsheet]--> xlsx
  - `ico` → `xml` ✅ ico --[image_palette]--> json --[spreadsheet]--> xml

#### `hdr`（.hdr） - ❌ 暂不支持

- **直转**：
  - `hdr` → `base64` ✅ `hash`
  - `hdr` → `crc` ✅ `hash`
  - `hdr` → `identicon_png` ✅ `identicon`
  - `hdr` → `md5` ✅ `hash`
  - `hdr` → `qr_png` ✅ `qr`
  - `hdr` → `sha` ✅ `hash`

#### `exr`（.exr） - ❌ 暂不支持

- **直转**：
  - `exr` → `base64` ✅ `hash`
  - `exr` → `crc` ✅ `hash`
  - `exr` → `identicon_png` ✅ `identicon`
  - `exr` → `md5` ✅ `hash`
  - `exr` → `qr_png` ✅ `qr`
  - `exr` → `sha` ✅ `hash`

#### `qr_png`（.png） - ✅ 可读

- （无出边：该格式没有可用的写出引擎，或上游读取能力未接入）

#### `identicon_png`（.png） - ✅ 可读

- （无出边：该格式没有可用的写出引擎，或上游读取能力未接入）

#### `ascii_art`（.txt） - ✅ 可读

- （无出边：该格式没有可用的写出引擎，或上游读取能力未接入）

#### `braille_art`（.txt） - ✅ 可读

- （无出边：该格式没有可用的写出引擎，或上游读取能力未接入）

#### `waveform_png`（.png） - ✅ 可读

- （无出边：该格式没有可用的写出引擎，或上游读取能力未接入）

#### `spectrogram_png`（.png） - ✅ 可读

- （无出边：该格式没有可用的写出引擎，或上游读取能力未接入）

### 音频（audio）


#### `mp3`（.mp3） - ✅ 可读

- **直转**：
  - `mp3` → `base64` ✅ `hash`
  - `mp3` → `crc` ✅ `hash`
  - `mp3` → `identicon_png` ✅ `identicon`
  - `mp3` → `md5` ✅ `hash`
  - `mp3` → `midi` ✅ `audio_midi`
  - `mp3` → `qr_png` ✅ `qr`
  - `mp3` → `sha` ✅ `hash`
  - `mp3` → `spectrogram_png` ✅ `spectrogram`
  - `mp3` → `aac` ⏳ `ffmpeg`
  - `mp3` → `avi` ⏳ `ffmpeg`
  - `mp3` → `flac` ⏳ `ffmpeg`
  - `mp3` → `flv` ⏳ `ffmpeg`
  - `mp3` → `m4a` ⏳ `ffmpeg`
  - `mp3` → `mkv` ⏳ `ffmpeg`
  - `mp3` → `mov` ⏳ `ffmpeg`
  - `mp3` → `mp4` ⏳ `ffmpeg`
  - `mp3` → `ogg` ⏳ `ffmpeg`
  - `mp3` → `wav` ⏳ `ffmpeg`
  - `mp3` → `waveform_png` ⏳ `ffmpeg`
  - `mp3` → `webm` ⏳ `ffmpeg`
- **多跳**（最多 2 跳）：
  - `mp3` → `gif` ⏳ mp3 --[ffmpeg]--> mp4 --[ffmpeg]--> gif
  - `mp3` → `jpg` ⏳ mp3 --[ffmpeg]--> mp4 --[ffmpeg]--> jpg
  - `mp3` → `png` ⏳ mp3 --[ffmpeg]--> mp4 --[ffmpeg]--> png
  - `mp3` → `srt` ⏳ mp3 --[ffmpeg]--> mp4 --[ffmpeg]--> srt

#### `wav`（.wav） - ✅ 可读

- **直转**：
  - `wav` → `base64` ✅ `hash`
  - `wav` → `crc` ✅ `hash`
  - `wav` → `identicon_png` ✅ `identicon`
  - `wav` → `md5` ✅ `hash`
  - `wav` → `midi` ✅ `audio_midi`
  - `wav` → `qr_png` ✅ `qr`
  - `wav` → `sha` ✅ `hash`
  - `wav` → `spectrogram_png` ✅ `spectrogram`
  - `wav` → `aac` ⏳ `ffmpeg`
  - `wav` → `avi` ⏳ `ffmpeg`
  - `wav` → `flac` ⏳ `ffmpeg`
  - `wav` → `flv` ⏳ `ffmpeg`
  - `wav` → `m4a` ⏳ `ffmpeg`
  - `wav` → `mkv` ⏳ `ffmpeg`
  - `wav` → `mov` ⏳ `ffmpeg`
  - `wav` → `mp3` ⏳ `ffmpeg`
  - `wav` → `mp4` ⏳ `ffmpeg`
  - `wav` → `ogg` ⏳ `ffmpeg`
  - `wav` → `waveform_png` ⏳ `ffmpeg`
  - `wav` → `webm` ⏳ `ffmpeg`
- **多跳**（最多 2 跳）：
  - `wav` → `gif` ⏳ wav --[ffmpeg]--> mp4 --[ffmpeg]--> gif
  - `wav` → `jpg` ⏳ wav --[ffmpeg]--> mp4 --[ffmpeg]--> jpg
  - `wav` → `png` ⏳ wav --[ffmpeg]--> mp4 --[ffmpeg]--> png
  - `wav` → `srt` ⏳ wav --[ffmpeg]--> mp4 --[ffmpeg]--> srt

#### `flac`（.flac） - ✅ 可读

- **直转**：
  - `flac` → `base64` ✅ `hash`
  - `flac` → `crc` ✅ `hash`
  - `flac` → `identicon_png` ✅ `identicon`
  - `flac` → `md5` ✅ `hash`
  - `flac` → `midi` ✅ `audio_midi`
  - `flac` → `qr_png` ✅ `qr`
  - `flac` → `sha` ✅ `hash`
  - `flac` → `spectrogram_png` ✅ `spectrogram`
  - `flac` → `aac` ⏳ `ffmpeg`
  - `flac` → `avi` ⏳ `ffmpeg`
  - `flac` → `flv` ⏳ `ffmpeg`
  - `flac` → `m4a` ⏳ `ffmpeg`
  - `flac` → `mkv` ⏳ `ffmpeg`
  - `flac` → `mov` ⏳ `ffmpeg`
  - `flac` → `mp3` ⏳ `ffmpeg`
  - `flac` → `mp4` ⏳ `ffmpeg`
  - `flac` → `ogg` ⏳ `ffmpeg`
  - `flac` → `wav` ⏳ `ffmpeg`
  - `flac` → `waveform_png` ⏳ `ffmpeg`
  - `flac` → `webm` ⏳ `ffmpeg`
- **多跳**（最多 2 跳）：
  - `flac` → `gif` ⏳ flac --[ffmpeg]--> mp4 --[ffmpeg]--> gif
  - `flac` → `jpg` ⏳ flac --[ffmpeg]--> mp4 --[ffmpeg]--> jpg
  - `flac` → `png` ⏳ flac --[ffmpeg]--> mp4 --[ffmpeg]--> png
  - `flac` → `srt` ⏳ flac --[ffmpeg]--> mp4 --[ffmpeg]--> srt

#### `aac`（.aac） - ✅ 可读

- **直转**：
  - `aac` → `base64` ✅ `hash`
  - `aac` → `crc` ✅ `hash`
  - `aac` → `identicon_png` ✅ `identicon`
  - `aac` → `md5` ✅ `hash`
  - `aac` → `midi` ✅ `audio_midi`
  - `aac` → `qr_png` ✅ `qr`
  - `aac` → `sha` ✅ `hash`
  - `aac` → `spectrogram_png` ✅ `spectrogram`
  - `aac` → `avi` ⏳ `ffmpeg`
  - `aac` → `flac` ⏳ `ffmpeg`
  - `aac` → `flv` ⏳ `ffmpeg`
  - `aac` → `m4a` ⏳ `ffmpeg`
  - `aac` → `mkv` ⏳ `ffmpeg`
  - `aac` → `mov` ⏳ `ffmpeg`
  - `aac` → `mp3` ⏳ `ffmpeg`
  - `aac` → `mp4` ⏳ `ffmpeg`
  - `aac` → `ogg` ⏳ `ffmpeg`
  - `aac` → `wav` ⏳ `ffmpeg`
  - `aac` → `waveform_png` ⏳ `ffmpeg`
  - `aac` → `webm` ⏳ `ffmpeg`
- **多跳**（最多 2 跳）：
  - `aac` → `gif` ⏳ aac --[ffmpeg]--> mp4 --[ffmpeg]--> gif
  - `aac` → `jpg` ⏳ aac --[ffmpeg]--> mp4 --[ffmpeg]--> jpg
  - `aac` → `png` ⏳ aac --[ffmpeg]--> mp4 --[ffmpeg]--> png
  - `aac` → `srt` ⏳ aac --[ffmpeg]--> mp4 --[ffmpeg]--> srt

#### `m4a`（.m4a） - ✅ 可读

- **直转**：
  - `m4a` → `base64` ✅ `hash`
  - `m4a` → `crc` ✅ `hash`
  - `m4a` → `identicon_png` ✅ `identicon`
  - `m4a` → `md5` ✅ `hash`
  - `m4a` → `midi` ✅ `audio_midi`
  - `m4a` → `qr_png` ✅ `qr`
  - `m4a` → `sha` ✅ `hash`
  - `m4a` → `spectrogram_png` ✅ `spectrogram`
  - `m4a` → `aac` ⏳ `ffmpeg`
  - `m4a` → `avi` ⏳ `ffmpeg`
  - `m4a` → `flac` ⏳ `ffmpeg`
  - `m4a` → `flv` ⏳ `ffmpeg`
  - `m4a` → `mkv` ⏳ `ffmpeg`
  - `m4a` → `mov` ⏳ `ffmpeg`
  - `m4a` → `mp3` ⏳ `ffmpeg`
  - `m4a` → `mp4` ⏳ `ffmpeg`
  - `m4a` → `ogg` ⏳ `ffmpeg`
  - `m4a` → `wav` ⏳ `ffmpeg`
  - `m4a` → `waveform_png` ⏳ `ffmpeg`
  - `m4a` → `webm` ⏳ `ffmpeg`
- **多跳**（最多 2 跳）：
  - `m4a` → `gif` ⏳ m4a --[ffmpeg]--> mp4 --[ffmpeg]--> gif
  - `m4a` → `jpg` ⏳ m4a --[ffmpeg]--> mp4 --[ffmpeg]--> jpg
  - `m4a` → `png` ⏳ m4a --[ffmpeg]--> mp4 --[ffmpeg]--> png
  - `m4a` → `srt` ⏳ m4a --[ffmpeg]--> mp4 --[ffmpeg]--> srt

#### `ogg`（.ogg） - ✅ 可读

- **直转**：
  - `ogg` → `base64` ✅ `hash`
  - `ogg` → `crc` ✅ `hash`
  - `ogg` → `identicon_png` ✅ `identicon`
  - `ogg` → `md5` ✅ `hash`
  - `ogg` → `midi` ✅ `audio_midi`
  - `ogg` → `qr_png` ✅ `qr`
  - `ogg` → `sha` ✅ `hash`
  - `ogg` → `spectrogram_png` ✅ `spectrogram`
  - `ogg` → `aac` ⏳ `ffmpeg`
  - `ogg` → `avi` ⏳ `ffmpeg`
  - `ogg` → `flac` ⏳ `ffmpeg`
  - `ogg` → `flv` ⏳ `ffmpeg`
  - `ogg` → `m4a` ⏳ `ffmpeg`
  - `ogg` → `mkv` ⏳ `ffmpeg`
  - `ogg` → `mov` ⏳ `ffmpeg`
  - `ogg` → `mp3` ⏳ `ffmpeg`
  - `ogg` → `mp4` ⏳ `ffmpeg`
  - `ogg` → `wav` ⏳ `ffmpeg`
  - `ogg` → `waveform_png` ⏳ `ffmpeg`
  - `ogg` → `webm` ⏳ `ffmpeg`
- **多跳**（最多 2 跳）：
  - `ogg` → `gif` ⏳ ogg --[ffmpeg]--> mp4 --[ffmpeg]--> gif
  - `ogg` → `jpg` ⏳ ogg --[ffmpeg]--> mp4 --[ffmpeg]--> jpg
  - `ogg` → `png` ⏳ ogg --[ffmpeg]--> mp4 --[ffmpeg]--> png
  - `ogg` → `srt` ⏳ ogg --[ffmpeg]--> mp4 --[ffmpeg]--> srt

#### `midi`（.mid） - ✅ 可读

- **直转**：
  - `midi` → `base64` ✅ `hash`
  - `midi` → `crc` ✅ `hash`
  - `midi` → `identicon_png` ✅ `identicon`
  - `midi` → `md5` ✅ `hash`
  - `midi` → `qr_png` ✅ `qr`
  - `midi` → `sha` ✅ `hash`
  - `midi` → `mkv` ⏳ `ffmpeg`
  - `midi` → `mov` ⏳ `ffmpeg`
  - `midi` → `mp4` ⏳ `ffmpeg`
  - `midi` → `webm` ⏳ `ffmpeg`
- **多跳**（最多 2 跳）：
  - `midi` → `aac` ⏳ midi --[ffmpeg]--> mp4 --[ffmpeg]--> aac
  - `midi` → `avi` ⏳ midi --[ffmpeg]--> mp4 --[ffmpeg]--> avi
  - `midi` → `flac` ⏳ midi --[ffmpeg]--> mp4 --[ffmpeg]--> flac
  - `midi` → `flv` ⏳ midi --[ffmpeg]--> mp4 --[ffmpeg]--> flv
  - `midi` → `gif` ⏳ midi --[ffmpeg]--> mp4 --[ffmpeg]--> gif
  - `midi` → `jpg` ⏳ midi --[ffmpeg]--> mp4 --[ffmpeg]--> jpg
  - `midi` → `m4a` ⏳ midi --[ffmpeg]--> mp4 --[ffmpeg]--> m4a
  - `midi` → `mp3` ⏳ midi --[ffmpeg]--> mp4 --[ffmpeg]--> mp3
  - `midi` → `ogg` ⏳ midi --[ffmpeg]--> mp4 --[ffmpeg]--> ogg
  - `midi` → `png` ⏳ midi --[ffmpeg]--> mp4 --[ffmpeg]--> png
  - `midi` → `srt` ⏳ midi --[ffmpeg]--> mp4 --[ffmpeg]--> srt
  - `midi` → `wav` ⏳ midi --[ffmpeg]--> mp4 --[ffmpeg]--> wav

#### `ncm`（.ncm） - ❌ 暂不支持

- **直转**：
  - `ncm` → `base64` ✅ `hash`
  - `ncm` → `crc` ✅ `hash`
  - `ncm` → `identicon_png` ✅ `identicon`
  - `ncm` → `md5` ✅ `hash`
  - `ncm` → `qr_png` ✅ `qr`
  - `ncm` → `sha` ✅ `hash`

#### `kgm`（.kgm） - ❌ 暂不支持

- **直转**：
  - `kgm` → `base64` ✅ `hash`
  - `kgm` → `crc` ✅ `hash`
  - `kgm` → `identicon_png` ✅ `identicon`
  - `kgm` → `md5` ✅ `hash`
  - `kgm` → `qr_png` ✅ `qr`
  - `kgm` → `sha` ✅ `hash`

#### `qmc`（.qmc） - ❌ 暂不支持

- **直转**：
  - `qmc` → `base64` ✅ `hash`
  - `qmc` → `crc` ✅ `hash`
  - `qmc` → `identicon_png` ✅ `identicon`
  - `qmc` → `md5` ✅ `hash`
  - `qmc` → `qr_png` ✅ `qr`
  - `qmc` → `sha` ✅ `hash`

### 视频（video）


#### `mp4`（.mp4） - ✅ 可读

- **直转**：
  - `mp4` → `base64` ✅ `hash`
  - `mp4` → `crc` ✅ `hash`
  - `mp4` → `identicon_png` ✅ `identicon`
  - `mp4` → `md5` ✅ `hash`
  - `mp4` → `qr_png` ✅ `qr`
  - `mp4` → `sha` ✅ `hash`
  - `mp4` → `aac` ⏳ `ffmpeg`
  - `mp4` → `avi` ⏳ `ffmpeg`
  - `mp4` → `flac` ⏳ `ffmpeg`
  - `mp4` → `flv` ⏳ `ffmpeg`
  - `mp4` → `gif` ⏳ `ffmpeg`
  - `mp4` → `jpg` ⏳ `ffmpeg`
  - `mp4` → `m4a` ⏳ `ffmpeg`
  - `mp4` → `mkv` ⏳ `ffmpeg`
  - `mp4` → `mov` ⏳ `ffmpeg`
  - `mp4` → `mp3` ⏳ `ffmpeg`
  - `mp4` → `ogg` ⏳ `ffmpeg`
  - `mp4` → `png` ⏳ `ffmpeg`
  - `mp4` → `srt` ⏳ `ffmpeg`
  - `mp4` → `wav` ⏳ `ffmpeg`
  - `mp4` → `webm` ⏳ `ffmpeg`
- **多跳**（最多 2 跳）：
  - `mp4` → `aco` ⏳ mp4 --[ffmpeg]--> gif --[image_palette]--> aco
  - `mp4` → `ascii_art` ⏳ mp4 --[ffmpeg]--> gif --[ascii_art]--> ascii_art
  - `mp4` → `ase` ⏳ mp4 --[ffmpeg]--> gif --[image_palette]--> ase
  - `mp4` → `ass` ⏳ mp4 --[ffmpeg]--> srt --[subtitle]--> ass
  - `mp4` → `bmp` ⏳ mp4 --[ffmpeg]--> gif --[image]--> bmp
  - `mp4` → `braille_art` ⏳ mp4 --[ffmpeg]--> gif --[ascii_art]--> braille_art
  - `mp4` → `dds` ⏳ mp4 --[ffmpeg]--> png --[texture]--> dds
  - `mp4` → `docx` ⏳ mp4 --[ffmpeg]--> gif --[image_doc]--> docx
  - `mp4` → `dst` ⏳ mp4 --[ffmpeg]--> png --[embroidery]--> dst
  - `mp4` → `gpl` ⏳ mp4 --[ffmpeg]--> gif --[image_palette]--> gpl
  - `mp4` → `ico` ⏳ mp4 --[ffmpeg]--> gif --[image]--> ico
  - `mp4` → `jef` ⏳ mp4 --[ffmpeg]--> png --[embroidery]--> jef
  - `mp4` → `json` ⏳ mp4 --[ffmpeg]--> gif --[image_palette]--> json
  - `mp4` → `ktx` ⏳ mp4 --[ffmpeg]--> gif --[texture]--> ktx
  - `mp4` → `lrc` ⏳ mp4 --[ffmpeg]--> srt --[subtitle]--> lrc
  - `mp4` → `midi` ⏳ mp4 --[ffmpeg]--> mp3 --[audio_midi]--> midi
  - `mp4` → `pdf` ⏳ mp4 --[ffmpeg]--> png --[pdf]--> pdf
  - `mp4` → `pes` ⏳ mp4 --[ffmpeg]--> png --[embroidery]--> pes
  - `mp4` → `spectrogram_png` ⏳ mp4 --[ffmpeg]--> mp3 --[spectrogram]--> spectrogram_png
  - `mp4` → `svg` ⏳ mp4 --[ffmpeg]--> gif --[svg_vector]--> svg
  - `mp4` → `tga` ⏳ mp4 --[ffmpeg]--> png --[texture]--> tga
  - `mp4` → `tiff` ⏳ mp4 --[ffmpeg]--> gif --[image]--> tiff
  - `mp4` → `vtt` ⏳ mp4 --[ffmpeg]--> srt --[subtitle]--> vtt
  - `mp4` → `waveform_png` ⏳ mp4 --[ffmpeg]--> mp3 --[ffmpeg]--> waveform_png
  - `mp4` → `webp` ⏳ mp4 --[ffmpeg]--> gif --[image]--> webp

#### `mkv`（.mkv） - ✅ 可读

- **直转**：
  - `mkv` → `base64` ✅ `hash`
  - `mkv` → `crc` ✅ `hash`
  - `mkv` → `identicon_png` ✅ `identicon`
  - `mkv` → `md5` ✅ `hash`
  - `mkv` → `qr_png` ✅ `qr`
  - `mkv` → `sha` ✅ `hash`
  - `mkv` → `aac` ⏳ `ffmpeg`
  - `mkv` → `avi` ⏳ `ffmpeg`
  - `mkv` → `flac` ⏳ `ffmpeg`
  - `mkv` → `flv` ⏳ `ffmpeg`
  - `mkv` → `gif` ⏳ `ffmpeg`
  - `mkv` → `jpg` ⏳ `ffmpeg`
  - `mkv` → `m4a` ⏳ `ffmpeg`
  - `mkv` → `mov` ⏳ `ffmpeg`
  - `mkv` → `mp3` ⏳ `ffmpeg`
  - `mkv` → `mp4` ⏳ `ffmpeg`
  - `mkv` → `ogg` ⏳ `ffmpeg`
  - `mkv` → `png` ⏳ `ffmpeg`
  - `mkv` → `srt` ⏳ `ffmpeg`
  - `mkv` → `wav` ⏳ `ffmpeg`
  - `mkv` → `webm` ⏳ `ffmpeg`
- **多跳**（最多 2 跳）：
  - `mkv` → `aco` ⏳ mkv --[ffmpeg]--> gif --[image_palette]--> aco
  - `mkv` → `ascii_art` ⏳ mkv --[ffmpeg]--> gif --[ascii_art]--> ascii_art
  - `mkv` → `ase` ⏳ mkv --[ffmpeg]--> gif --[image_palette]--> ase
  - `mkv` → `ass` ⏳ mkv --[ffmpeg]--> srt --[subtitle]--> ass
  - `mkv` → `bmp` ⏳ mkv --[ffmpeg]--> gif --[image]--> bmp
  - `mkv` → `braille_art` ⏳ mkv --[ffmpeg]--> gif --[ascii_art]--> braille_art
  - `mkv` → `dds` ⏳ mkv --[ffmpeg]--> png --[texture]--> dds
  - `mkv` → `docx` ⏳ mkv --[ffmpeg]--> gif --[image_doc]--> docx
  - `mkv` → `dst` ⏳ mkv --[ffmpeg]--> png --[embroidery]--> dst
  - `mkv` → `gpl` ⏳ mkv --[ffmpeg]--> gif --[image_palette]--> gpl
  - `mkv` → `ico` ⏳ mkv --[ffmpeg]--> gif --[image]--> ico
  - `mkv` → `jef` ⏳ mkv --[ffmpeg]--> png --[embroidery]--> jef
  - `mkv` → `json` ⏳ mkv --[ffmpeg]--> gif --[image_palette]--> json
  - `mkv` → `ktx` ⏳ mkv --[ffmpeg]--> gif --[texture]--> ktx
  - `mkv` → `lrc` ⏳ mkv --[ffmpeg]--> srt --[subtitle]--> lrc
  - `mkv` → `midi` ⏳ mkv --[ffmpeg]--> mp3 --[audio_midi]--> midi
  - `mkv` → `pdf` ⏳ mkv --[ffmpeg]--> png --[pdf]--> pdf
  - `mkv` → `pes` ⏳ mkv --[ffmpeg]--> png --[embroidery]--> pes
  - `mkv` → `spectrogram_png` ⏳ mkv --[ffmpeg]--> mp3 --[spectrogram]--> spectrogram_png
  - `mkv` → `svg` ⏳ mkv --[ffmpeg]--> gif --[svg_vector]--> svg
  - `mkv` → `tga` ⏳ mkv --[ffmpeg]--> png --[texture]--> tga
  - `mkv` → `tiff` ⏳ mkv --[ffmpeg]--> gif --[image]--> tiff
  - `mkv` → `vtt` ⏳ mkv --[ffmpeg]--> srt --[subtitle]--> vtt
  - `mkv` → `waveform_png` ⏳ mkv --[ffmpeg]--> mp3 --[ffmpeg]--> waveform_png
  - `mkv` → `webp` ⏳ mkv --[ffmpeg]--> gif --[image]--> webp

#### `mov`（.mov） - ✅ 可读

- **直转**：
  - `mov` → `base64` ✅ `hash`
  - `mov` → `crc` ✅ `hash`
  - `mov` → `identicon_png` ✅ `identicon`
  - `mov` → `md5` ✅ `hash`
  - `mov` → `qr_png` ✅ `qr`
  - `mov` → `sha` ✅ `hash`
  - `mov` → `aac` ⏳ `ffmpeg`
  - `mov` → `avi` ⏳ `ffmpeg`
  - `mov` → `flac` ⏳ `ffmpeg`
  - `mov` → `flv` ⏳ `ffmpeg`
  - `mov` → `gif` ⏳ `ffmpeg`
  - `mov` → `jpg` ⏳ `ffmpeg`
  - `mov` → `m4a` ⏳ `ffmpeg`
  - `mov` → `mkv` ⏳ `ffmpeg`
  - `mov` → `mp3` ⏳ `ffmpeg`
  - `mov` → `mp4` ⏳ `ffmpeg`
  - `mov` → `ogg` ⏳ `ffmpeg`
  - `mov` → `png` ⏳ `ffmpeg`
  - `mov` → `srt` ⏳ `ffmpeg`
  - `mov` → `wav` ⏳ `ffmpeg`
  - `mov` → `webm` ⏳ `ffmpeg`
- **多跳**（最多 2 跳）：
  - `mov` → `aco` ⏳ mov --[ffmpeg]--> gif --[image_palette]--> aco
  - `mov` → `ascii_art` ⏳ mov --[ffmpeg]--> gif --[ascii_art]--> ascii_art
  - `mov` → `ase` ⏳ mov --[ffmpeg]--> gif --[image_palette]--> ase
  - `mov` → `ass` ⏳ mov --[ffmpeg]--> srt --[subtitle]--> ass
  - `mov` → `bmp` ⏳ mov --[ffmpeg]--> gif --[image]--> bmp
  - `mov` → `braille_art` ⏳ mov --[ffmpeg]--> gif --[ascii_art]--> braille_art
  - `mov` → `dds` ⏳ mov --[ffmpeg]--> png --[texture]--> dds
  - `mov` → `docx` ⏳ mov --[ffmpeg]--> gif --[image_doc]--> docx
  - `mov` → `dst` ⏳ mov --[ffmpeg]--> png --[embroidery]--> dst
  - `mov` → `gpl` ⏳ mov --[ffmpeg]--> gif --[image_palette]--> gpl
  - `mov` → `ico` ⏳ mov --[ffmpeg]--> gif --[image]--> ico
  - `mov` → `jef` ⏳ mov --[ffmpeg]--> png --[embroidery]--> jef
  - `mov` → `json` ⏳ mov --[ffmpeg]--> gif --[image_palette]--> json
  - `mov` → `ktx` ⏳ mov --[ffmpeg]--> gif --[texture]--> ktx
  - `mov` → `lrc` ⏳ mov --[ffmpeg]--> srt --[subtitle]--> lrc
  - `mov` → `midi` ⏳ mov --[ffmpeg]--> mp3 --[audio_midi]--> midi
  - `mov` → `pdf` ⏳ mov --[ffmpeg]--> png --[pdf]--> pdf
  - `mov` → `pes` ⏳ mov --[ffmpeg]--> png --[embroidery]--> pes
  - `mov` → `spectrogram_png` ⏳ mov --[ffmpeg]--> mp3 --[spectrogram]--> spectrogram_png
  - `mov` → `svg` ⏳ mov --[ffmpeg]--> gif --[svg_vector]--> svg
  - `mov` → `tga` ⏳ mov --[ffmpeg]--> png --[texture]--> tga
  - `mov` → `tiff` ⏳ mov --[ffmpeg]--> gif --[image]--> tiff
  - `mov` → `vtt` ⏳ mov --[ffmpeg]--> srt --[subtitle]--> vtt
  - `mov` → `waveform_png` ⏳ mov --[ffmpeg]--> mp3 --[ffmpeg]--> waveform_png
  - `mov` → `webp` ⏳ mov --[ffmpeg]--> gif --[image]--> webp

#### `avi`（.avi） - ✅ 可读

- **直转**：
  - `avi` → `base64` ✅ `hash`
  - `avi` → `crc` ✅ `hash`
  - `avi` → `identicon_png` ✅ `identicon`
  - `avi` → `md5` ✅ `hash`
  - `avi` → `qr_png` ✅ `qr`
  - `avi` → `sha` ✅ `hash`
  - `avi` → `aac` ⏳ `ffmpeg`
  - `avi` → `flac` ⏳ `ffmpeg`
  - `avi` → `flv` ⏳ `ffmpeg`
  - `avi` → `gif` ⏳ `ffmpeg`
  - `avi` → `jpg` ⏳ `ffmpeg`
  - `avi` → `m4a` ⏳ `ffmpeg`
  - `avi` → `mkv` ⏳ `ffmpeg`
  - `avi` → `mov` ⏳ `ffmpeg`
  - `avi` → `mp3` ⏳ `ffmpeg`
  - `avi` → `mp4` ⏳ `ffmpeg`
  - `avi` → `ogg` ⏳ `ffmpeg`
  - `avi` → `png` ⏳ `ffmpeg`
  - `avi` → `wav` ⏳ `ffmpeg`
  - `avi` → `webm` ⏳ `ffmpeg`
- **多跳**（最多 2 跳）：
  - `avi` → `aco` ⏳ avi --[ffmpeg]--> gif --[image_palette]--> aco
  - `avi` → `ascii_art` ⏳ avi --[ffmpeg]--> gif --[ascii_art]--> ascii_art
  - `avi` → `ase` ⏳ avi --[ffmpeg]--> gif --[image_palette]--> ase
  - `avi` → `bmp` ⏳ avi --[ffmpeg]--> gif --[image]--> bmp
  - `avi` → `braille_art` ⏳ avi --[ffmpeg]--> gif --[ascii_art]--> braille_art
  - `avi` → `dds` ⏳ avi --[ffmpeg]--> png --[texture]--> dds
  - `avi` → `docx` ⏳ avi --[ffmpeg]--> gif --[image_doc]--> docx
  - `avi` → `dst` ⏳ avi --[ffmpeg]--> png --[embroidery]--> dst
  - `avi` → `gpl` ⏳ avi --[ffmpeg]--> gif --[image_palette]--> gpl
  - `avi` → `ico` ⏳ avi --[ffmpeg]--> gif --[image]--> ico
  - `avi` → `jef` ⏳ avi --[ffmpeg]--> png --[embroidery]--> jef
  - `avi` → `json` ⏳ avi --[ffmpeg]--> gif --[image_palette]--> json
  - `avi` → `ktx` ⏳ avi --[ffmpeg]--> gif --[texture]--> ktx
  - `avi` → `midi` ⏳ avi --[ffmpeg]--> mp3 --[audio_midi]--> midi
  - `avi` → `pdf` ⏳ avi --[ffmpeg]--> png --[pdf]--> pdf
  - `avi` → `pes` ⏳ avi --[ffmpeg]--> png --[embroidery]--> pes
  - `avi` → `spectrogram_png` ⏳ avi --[ffmpeg]--> mp3 --[spectrogram]--> spectrogram_png
  - `avi` → `srt` ⏳ avi --[ffmpeg]--> mp4 --[ffmpeg]--> srt
  - `avi` → `svg` ⏳ avi --[ffmpeg]--> gif --[svg_vector]--> svg
  - `avi` → `tga` ⏳ avi --[ffmpeg]--> png --[texture]--> tga
  - `avi` → `tiff` ⏳ avi --[ffmpeg]--> gif --[image]--> tiff
  - `avi` → `waveform_png` ⏳ avi --[ffmpeg]--> mp3 --[ffmpeg]--> waveform_png
  - `avi` → `webp` ⏳ avi --[ffmpeg]--> gif --[image]--> webp

#### `webm`（.webm） - ✅ 可读

- **直转**：
  - `webm` → `base64` ✅ `hash`
  - `webm` → `crc` ✅ `hash`
  - `webm` → `identicon_png` ✅ `identicon`
  - `webm` → `md5` ✅ `hash`
  - `webm` → `qr_png` ✅ `qr`
  - `webm` → `sha` ✅ `hash`
  - `webm` → `aac` ⏳ `ffmpeg`
  - `webm` → `avi` ⏳ `ffmpeg`
  - `webm` → `flac` ⏳ `ffmpeg`
  - `webm` → `flv` ⏳ `ffmpeg`
  - `webm` → `gif` ⏳ `ffmpeg`
  - `webm` → `jpg` ⏳ `ffmpeg`
  - `webm` → `m4a` ⏳ `ffmpeg`
  - `webm` → `mkv` ⏳ `ffmpeg`
  - `webm` → `mov` ⏳ `ffmpeg`
  - `webm` → `mp3` ⏳ `ffmpeg`
  - `webm` → `mp4` ⏳ `ffmpeg`
  - `webm` → `ogg` ⏳ `ffmpeg`
  - `webm` → `png` ⏳ `ffmpeg`
  - `webm` → `srt` ⏳ `ffmpeg`
  - `webm` → `wav` ⏳ `ffmpeg`
- **多跳**（最多 2 跳）：
  - `webm` → `aco` ⏳ webm --[ffmpeg]--> gif --[image_palette]--> aco
  - `webm` → `ascii_art` ⏳ webm --[ffmpeg]--> gif --[ascii_art]--> ascii_art
  - `webm` → `ase` ⏳ webm --[ffmpeg]--> gif --[image_palette]--> ase
  - `webm` → `ass` ⏳ webm --[ffmpeg]--> srt --[subtitle]--> ass
  - `webm` → `bmp` ⏳ webm --[ffmpeg]--> gif --[image]--> bmp
  - `webm` → `braille_art` ⏳ webm --[ffmpeg]--> gif --[ascii_art]--> braille_art
  - `webm` → `dds` ⏳ webm --[ffmpeg]--> png --[texture]--> dds
  - `webm` → `docx` ⏳ webm --[ffmpeg]--> gif --[image_doc]--> docx
  - `webm` → `dst` ⏳ webm --[ffmpeg]--> png --[embroidery]--> dst
  - `webm` → `gpl` ⏳ webm --[ffmpeg]--> gif --[image_palette]--> gpl
  - `webm` → `ico` ⏳ webm --[ffmpeg]--> gif --[image]--> ico
  - `webm` → `jef` ⏳ webm --[ffmpeg]--> png --[embroidery]--> jef
  - `webm` → `json` ⏳ webm --[ffmpeg]--> gif --[image_palette]--> json
  - `webm` → `ktx` ⏳ webm --[ffmpeg]--> gif --[texture]--> ktx
  - `webm` → `lrc` ⏳ webm --[ffmpeg]--> srt --[subtitle]--> lrc
  - `webm` → `midi` ⏳ webm --[ffmpeg]--> mp3 --[audio_midi]--> midi
  - `webm` → `pdf` ⏳ webm --[ffmpeg]--> png --[pdf]--> pdf
  - `webm` → `pes` ⏳ webm --[ffmpeg]--> png --[embroidery]--> pes
  - `webm` → `spectrogram_png` ⏳ webm --[ffmpeg]--> mp3 --[spectrogram]--> spectrogram_png
  - `webm` → `svg` ⏳ webm --[ffmpeg]--> gif --[svg_vector]--> svg
  - `webm` → `tga` ⏳ webm --[ffmpeg]--> png --[texture]--> tga
  - `webm` → `tiff` ⏳ webm --[ffmpeg]--> gif --[image]--> tiff
  - `webm` → `vtt` ⏳ webm --[ffmpeg]--> srt --[subtitle]--> vtt
  - `webm` → `waveform_png` ⏳ webm --[ffmpeg]--> mp3 --[ffmpeg]--> waveform_png
  - `webm` → `webp` ⏳ webm --[ffmpeg]--> gif --[image]--> webp

#### `flv`（.flv） - ✅ 可读

- **直转**：
  - `flv` → `base64` ✅ `hash`
  - `flv` → `crc` ✅ `hash`
  - `flv` → `identicon_png` ✅ `identicon`
  - `flv` → `md5` ✅ `hash`
  - `flv` → `qr_png` ✅ `qr`
  - `flv` → `sha` ✅ `hash`
  - `flv` → `aac` ⏳ `ffmpeg`
  - `flv` → `avi` ⏳ `ffmpeg`
  - `flv` → `flac` ⏳ `ffmpeg`
  - `flv` → `jpg` ⏳ `ffmpeg`
  - `flv` → `m4a` ⏳ `ffmpeg`
  - `flv` → `mkv` ⏳ `ffmpeg`
  - `flv` → `mov` ⏳ `ffmpeg`
  - `flv` → `mp3` ⏳ `ffmpeg`
  - `flv` → `mp4` ⏳ `ffmpeg`
  - `flv` → `ogg` ⏳ `ffmpeg`
  - `flv` → `png` ⏳ `ffmpeg`
  - `flv` → `wav` ⏳ `ffmpeg`
  - `flv` → `webm` ⏳ `ffmpeg`
- **多跳**（最多 2 跳）：
  - `flv` → `aco` ⏳ flv --[ffmpeg]--> png --[image_palette]--> aco
  - `flv` → `ascii_art` ⏳ flv --[ffmpeg]--> png --[ascii_art]--> ascii_art
  - `flv` → `ase` ⏳ flv --[ffmpeg]--> png --[image_palette]--> ase
  - `flv` → `bmp` ⏳ flv --[ffmpeg]--> png --[image]--> bmp
  - `flv` → `braille_art` ⏳ flv --[ffmpeg]--> png --[ascii_art]--> braille_art
  - `flv` → `dds` ⏳ flv --[ffmpeg]--> png --[texture]--> dds
  - `flv` → `docx` ⏳ flv --[ffmpeg]--> png --[image_doc]--> docx
  - `flv` → `dst` ⏳ flv --[ffmpeg]--> png --[embroidery]--> dst
  - `flv` → `gif` ⏳ flv --[ffmpeg]--> png --[image]--> gif
  - `flv` → `gpl` ⏳ flv --[ffmpeg]--> png --[image_palette]--> gpl
  - `flv` → `ico` ⏳ flv --[ffmpeg]--> png --[image]--> ico
  - `flv` → `jef` ⏳ flv --[ffmpeg]--> png --[embroidery]--> jef
  - `flv` → `json` ⏳ flv --[ffmpeg]--> png --[image_palette]--> json
  - `flv` → `ktx` ⏳ flv --[ffmpeg]--> png --[texture]--> ktx
  - `flv` → `midi` ⏳ flv --[ffmpeg]--> mp3 --[audio_midi]--> midi
  - `flv` → `pdf` ⏳ flv --[ffmpeg]--> png --[pdf]--> pdf
  - `flv` → `pes` ⏳ flv --[ffmpeg]--> png --[embroidery]--> pes
  - `flv` → `spectrogram_png` ⏳ flv --[ffmpeg]--> mp3 --[spectrogram]--> spectrogram_png
  - `flv` → `srt` ⏳ flv --[ffmpeg]--> mp4 --[ffmpeg]--> srt
  - `flv` → `svg` ⏳ flv --[ffmpeg]--> png --[svg_vector]--> svg
  - `flv` → `tga` ⏳ flv --[ffmpeg]--> png --[texture]--> tga
  - `flv` → `tiff` ⏳ flv --[ffmpeg]--> png --[image]--> tiff
  - `flv` → `waveform_png` ⏳ flv --[ffmpeg]--> mp3 --[ffmpeg]--> waveform_png
  - `flv` → `webp` ⏳ flv --[ffmpeg]--> png --[image]--> webp

### 电子书（ebook）


#### `epub`（.epub） - ✅ 可读

- **直转**：
  - `epub` → `base64` ✅ `hash`
  - `epub` → `crc` ✅ `hash`
  - `epub` → `identicon_png` ✅ `identicon`
  - `epub` → `md5` ✅ `hash`
  - `epub` → `qr_png` ✅ `qr`
  - `epub` → `sha` ✅ `hash`
  - `epub` → `txt` ✅ `ebook`
- **多跳**（最多 2 跳）：
  - `epub` → `docx` ✅ epub --[ebook]--> txt --[document]--> docx
  - `epub` → `html` ✅ epub --[ebook]--> txt --[document]--> html
  - `epub` → `md` ✅ epub --[ebook]--> txt --[document]--> md
  - `epub` → `pdf` ✅ epub --[ebook]--> txt --[pdf]--> pdf
  - `epub` → `rtf` ✅ epub --[ebook]--> txt --[document]--> rtf

#### `mobi`（.mobi） - ❌ 暂不支持

- **直转**：
  - `mobi` → `base64` ✅ `hash`
  - `mobi` → `crc` ✅ `hash`
  - `mobi` → `identicon_png` ✅ `identicon`
  - `mobi` → `md5` ✅ `hash`
  - `mobi` → `qr_png` ✅ `qr`
  - `mobi` → `sha` ✅ `hash`

#### `azw3`（.azw3） - ❌ 暂不支持

- **直转**：
  - `azw3` → `base64` ✅ `hash`
  - `azw3` → `crc` ✅ `hash`
  - `azw3` → `identicon_png` ✅ `identicon`
  - `azw3` → `md5` ✅ `hash`
  - `azw3` → `qr_png` ✅ `qr`
  - `azw3` → `sha` ✅ `hash`

### 文档（document）


#### `pdf`（.pdf） - ✅ 可读

- **直转**：
  - `pdf` → `base64` ✅ `hash`
  - `pdf` → `crc` ✅ `hash`
  - `pdf` → `identicon_png` ✅ `identicon`
  - `pdf` → `md5` ✅ `hash`
  - `pdf` → `qr_png` ✅ `qr`
  - `pdf` → `sha` ✅ `hash`
  - `pdf` → `txt` ✅ `pdf`
- **多跳**（最多 2 跳）：
  - `pdf` → `docx` ✅ pdf --[pdf]--> txt --[document]--> docx
  - `pdf` → `html` ✅ pdf --[pdf]--> txt --[document]--> html
  - `pdf` → `md` ✅ pdf --[pdf]--> txt --[document]--> md
  - `pdf` → `rtf` ✅ pdf --[pdf]--> txt --[document]--> rtf

#### `txt`（.txt） - ✅ 可读

- **直转**：
  - `txt` → `base64` ✅ `hash`
  - `txt` → `crc` ✅ `hash`
  - `txt` → `docx` ✅ `document`
  - `txt` → `html` ✅ `document`
  - `txt` → `identicon_png` ✅ `identicon`
  - `txt` → `md` ✅ `document`
  - `txt` → `md5` ✅ `hash`
  - `txt` → `pdf` ✅ `pdf`
  - `txt` → `qr_png` ✅ `qr`
  - `txt` → `rtf` ✅ `document`
  - `txt` → `sha` ✅ `hash`

#### `docx`（.docx） - ✅ 可读

- **直转**：
  - `docx` → `base64` ✅ `hash`
  - `docx` → `crc` ✅ `hash`
  - `docx` → `html` ✅ `document`
  - `docx` → `identicon_png` ✅ `identicon`
  - `docx` → `md` ✅ `document`
  - `docx` → `md5` ✅ `hash`
  - `docx` → `qr_png` ✅ `qr`
  - `docx` → `rtf` ✅ `document`
  - `docx` → `sha` ✅ `hash`
  - `docx` → `txt` ✅ `document`
- **多跳**（最多 2 跳）：
  - `docx` → `pdf` ✅ docx --[document]--> txt --[pdf]--> pdf

#### `md`（.md） - ✅ 可读

- **直转**：
  - `md` → `base64` ✅ `hash`
  - `md` → `crc` ✅ `hash`
  - `md` → `docx` ✅ `document`
  - `md` → `html` ✅ `document`
  - `md` → `identicon_png` ✅ `identicon`
  - `md` → `md5` ✅ `hash`
  - `md` → `pdf` ✅ `pdf`
  - `md` → `qr_png` ✅ `qr`
  - `md` → `rtf` ✅ `document`
  - `md` → `sha` ✅ `hash`
  - `md` → `txt` ✅ `document`

#### `html`（.html） - ✅ 可读

- **直转**：
  - `html` → `base64` ✅ `hash`
  - `html` → `crc` ✅ `hash`
  - `html` → `docx` ✅ `document`
  - `html` → `identicon_png` ✅ `identicon`
  - `html` → `md` ✅ `document`
  - `html` → `md5` ✅ `hash`
  - `html` → `pdf` ✅ `pdf`
  - `html` → `qr_png` ✅ `qr`
  - `html` → `rtf` ✅ `document`
  - `html` → `sha` ✅ `hash`
  - `html` → `txt` ✅ `document`

#### `rtf`（.rtf） - ✅ 可读

- **直转**：
  - `rtf` → `base64` ✅ `hash`
  - `rtf` → `crc` ✅ `hash`
  - `rtf` → `docx` ✅ `document`
  - `rtf` → `html` ✅ `document`
  - `rtf` → `identicon_png` ✅ `identicon`
  - `rtf` → `md` ✅ `document`
  - `rtf` → `md5` ✅ `hash`
  - `rtf` → `qr_png` ✅ `qr`
  - `rtf` → `sha` ✅ `hash`
  - `rtf` → `txt` ✅ `document`
- **多跳**（最多 2 跳）：
  - `rtf` → `pdf` ✅ rtf --[document]--> txt --[pdf]--> pdf

### 幻灯片（slides）


#### `pptx`（.pptx） - ✅ 可读

- **直转**：
  - `pptx` → `base64` ✅ `hash`
  - `pptx` → `crc` ✅ `hash`
  - `pptx` → `html` ✅ `slides`
  - `pptx` → `identicon_png` ✅ `identicon`
  - `pptx` → `md` ✅ `slides`
  - `pptx` → `md5` ✅ `hash`
  - `pptx` → `odp` ✅ `slides`
  - `pptx` → `pdf` ✅ `slides`
  - `pptx` → `qr_png` ✅ `qr`
  - `pptx` → `sha` ✅ `hash`
  - `pptx` → `txt` ✅ `slides`
- **多跳**（最多 2 跳）：
  - `pptx` → `docx` ✅ pptx --[slides]--> txt --[document]--> docx
  - `pptx` → `rtf` ✅ pptx --[slides]--> txt --[document]--> rtf

#### `odp`（.odp） - ✅ 可读

- **直转**：
  - `odp` → `base64` ✅ `hash`
  - `odp` → `crc` ✅ `hash`
  - `odp` → `html` ✅ `slides`
  - `odp` → `identicon_png` ✅ `identicon`
  - `odp` → `md` ✅ `slides`
  - `odp` → `md5` ✅ `hash`
  - `odp` → `pdf` ✅ `slides`
  - `odp` → `pptx` ✅ `slides`
  - `odp` → `qr_png` ✅ `qr`
  - `odp` → `sha` ✅ `hash`
  - `odp` → `txt` ✅ `slides`
- **多跳**（最多 2 跳）：
  - `odp` → `docx` ✅ odp --[slides]--> txt --[document]--> docx
  - `odp` → `rtf` ✅ odp --[slides]--> txt --[document]--> rtf

### 表格（spreadsheet）


#### `xlsx`（.xlsx） - ✅ 可读

- **直转**：
  - `xlsx` → `base64` ✅ `hash`
  - `xlsx` → `crc` ✅ `hash`
  - `xlsx` → `csv` ✅ `spreadsheet`
  - `xlsx` → `identicon_png` ✅ `identicon`
  - `xlsx` → `json` ✅ `spreadsheet`
  - `xlsx` → `md5` ✅ `hash`
  - `xlsx` → `qr_png` ✅ `qr`
  - `xlsx` → `sha` ✅ `hash`
  - `xlsx` → `xml` ✅ `spreadsheet`
- **多跳**（最多 2 跳）：
  - `xlsx` → `aco` ✅ xlsx --[spreadsheet]--> json --[color]--> aco
  - `xlsx` → `ase` ✅ xlsx --[spreadsheet]--> json --[color]--> ase
  - `xlsx` → `gpl` ✅ xlsx --[spreadsheet]--> json --[color]--> gpl
  - `xlsx` → `png` ✅ xlsx --[spreadsheet]--> json --[palette_image]--> png

#### `csv`（.csv） - ✅ 可读

- **直转**：
  - `csv` → `base64` ✅ `hash`
  - `csv` → `crc` ✅ `hash`
  - `csv` → `identicon_png` ✅ `identicon`
  - `csv` → `json` ✅ `spreadsheet`
  - `csv` → `md5` ✅ `hash`
  - `csv` → `qr_png` ✅ `qr`
  - `csv` → `sha` ✅ `hash`
  - `csv` → `xlsx` ✅ `spreadsheet`
  - `csv` → `xml` ✅ `spreadsheet`
- **多跳**（最多 2 跳）：
  - `csv` → `aco` ✅ csv --[spreadsheet]--> json --[color]--> aco
  - `csv` → `ase` ✅ csv --[spreadsheet]--> json --[color]--> ase
  - `csv` → `gpl` ✅ csv --[spreadsheet]--> json --[color]--> gpl
  - `csv` → `png` ✅ csv --[spreadsheet]--> json --[palette_image]--> png

#### `json`（.json） - ✅ 可读

- **直转**：
  - `json` → `aco` ✅ `color`
  - `json` → `ase` ✅ `color`
  - `json` → `base64` ✅ `hash`
  - `json` → `crc` ✅ `hash`
  - `json` → `csv` ✅ `spreadsheet`
  - `json` → `gpl` ✅ `color`
  - `json` → `identicon_png` ✅ `identicon`
  - `json` → `md5` ✅ `hash`
  - `json` → `png` ✅ `palette_image`
  - `json` → `qr_png` ✅ `qr`
  - `json` → `sha` ✅ `hash`
  - `json` → `xlsx` ✅ `spreadsheet`
  - `json` → `xml` ✅ `spreadsheet`
- **多跳**（最多 2 跳）：
  - `json` → `ascii_art` ✅ json --[palette_image]--> png --[ascii_art]--> ascii_art
  - `json` → `bmp` ✅ json --[palette_image]--> png --[image]--> bmp
  - `json` → `braille_art` ✅ json --[palette_image]--> png --[ascii_art]--> braille_art
  - `json` → `dds` ✅ json --[palette_image]--> png --[texture]--> dds
  - `json` → `docx` ✅ json --[palette_image]--> png --[image_doc]--> docx
  - `json` → `dst` ✅ json --[palette_image]--> png --[embroidery]--> dst
  - `json` → `gif` ✅ json --[palette_image]--> png --[image]--> gif
  - `json` → `ico` ✅ json --[palette_image]--> png --[image]--> ico
  - `json` → `jef` ✅ json --[palette_image]--> png --[embroidery]--> jef
  - `json` → `jpg` ✅ json --[palette_image]--> png --[image]--> jpg
  - `json` → `ktx` ✅ json --[palette_image]--> png --[texture]--> ktx
  - `json` → `pdf` ✅ json --[palette_image]--> png --[pdf]--> pdf
  - `json` → `pes` ✅ json --[palette_image]--> png --[embroidery]--> pes
  - `json` → `svg` ✅ json --[palette_image]--> png --[svg_vector]--> svg
  - `json` → `tga` ✅ json --[palette_image]--> png --[texture]--> tga
  - `json` → `tiff` ✅ json --[palette_image]--> png --[image]--> tiff
  - `json` → `webp` ✅ json --[palette_image]--> png --[image]--> webp

#### `xml`（.xml） - ✅ 可读

- **直转**：
  - `xml` → `base64` ✅ `hash`
  - `xml` → `crc` ✅ `hash`
  - `xml` → `csv` ✅ `spreadsheet`
  - `xml` → `identicon_png` ✅ `identicon`
  - `xml` → `json` ✅ `spreadsheet`
  - `xml` → `md5` ✅ `hash`
  - `xml` → `qr_png` ✅ `qr`
  - `xml` → `sha` ✅ `hash`
  - `xml` → `xlsx` ✅ `spreadsheet`
- **多跳**（最多 2 跳）：
  - `xml` → `aco` ✅ xml --[spreadsheet]--> json --[color]--> aco
  - `xml` → `ase` ✅ xml --[spreadsheet]--> json --[color]--> ase
  - `xml` → `gpl` ✅ xml --[spreadsheet]--> json --[color]--> gpl
  - `xml` → `png` ✅ xml --[spreadsheet]--> json --[palette_image]--> png

### 字体（font）


#### `ttf`（.ttf） - ✅ 可读

- **直转**：
  - `ttf` → `base64` ✅ `hash`
  - `ttf` → `crc` ✅ `hash`
  - `ttf` → `identicon_png` ✅ `identicon`
  - `ttf` → `md5` ✅ `hash`
  - `ttf` → `otf` ✅ `font`
  - `ttf` → `qr_png` ✅ `qr`
  - `ttf` → `sha` ✅ `hash`
  - `ttf` → `ufo` ✅ `font`
  - `ttf` → `woff` ✅ `font`
  - `ttf` → `woff2` ✅ `font`

#### `otf`（.otf） - ✅ 可读

- **直转**：
  - `otf` → `base64` ✅ `hash`
  - `otf` → `crc` ✅ `hash`
  - `otf` → `identicon_png` ✅ `identicon`
  - `otf` → `md5` ✅ `hash`
  - `otf` → `qr_png` ✅ `qr`
  - `otf` → `sha` ✅ `hash`
  - `otf` → `ttf` ✅ `font`
  - `otf` → `ufo` ✅ `font`
  - `otf` → `woff` ✅ `font`
  - `otf` → `woff2` ✅ `font`

#### `woff2`（.woff2） - ❌ 暂不支持

- **直转**：
  - `woff2` → `base64` ✅ `hash`
  - `woff2` → `crc` ✅ `hash`
  - `woff2` → `identicon_png` ✅ `identicon`
  - `woff2` → `md5` ✅ `hash`
  - `woff2` → `otf` ✅ `font`
  - `woff2` → `qr_png` ✅ `qr`
  - `woff2` → `sha` ✅ `hash`
  - `woff2` → `ttf` ✅ `font`
  - `woff2` → `ufo` ✅ `font`
- **多跳**（最多 2 跳）：
  - `woff2` → `woff` ✅ woff2 --[font]--> ttf --[font]--> woff

#### `woff`（.woff） - ✅ 可读

- **直转**：
  - `woff` → `base64` ✅ `hash`
  - `woff` → `crc` ✅ `hash`
  - `woff` → `identicon_png` ✅ `identicon`
  - `woff` → `md5` ✅ `hash`
  - `woff` → `otf` ✅ `font`
  - `woff` → `qr_png` ✅ `qr`
  - `woff` → `sha` ✅ `hash`
  - `woff` → `ttf` ✅ `font`
- **多跳**（最多 2 跳）：
  - `woff` → `ufo` ✅ woff --[font]--> ttf --[font]--> ufo
  - `woff` → `woff2` ✅ woff --[font]--> ttf --[font]--> woff2

#### `ufo`（.ufo） - ❌ 暂不支持

- **直转**：
  - `ufo` → `base64` ✅ `hash`
  - `ufo` → `crc` ✅ `hash`
  - `ufo` → `identicon_png` ✅ `identicon`
  - `ufo` → `md5` ✅ `hash`
  - `ufo` → `otf` ✅ `font`
  - `ufo` → `qr_png` ✅ `qr`
  - `ufo` → `sha` ✅ `hash`
  - `ufo` → `ttf` ✅ `font`
  - `ufo` → `woff2` ✅ `font`
- **多跳**（最多 2 跳）：
  - `ufo` → `woff` ✅ ufo --[font]--> ttf --[font]--> woff

### 调色板（palette）


#### `ase`（.ase） - ✅ 可读

- **直转**：
  - `ase` → `aco` ✅ `color`
  - `ase` → `base64` ✅ `hash`
  - `ase` → `crc` ✅ `hash`
  - `ase` → `gpl` ✅ `color`
  - `ase` → `identicon_png` ✅ `identicon`
  - `ase` → `json` ✅ `color`
  - `ase` → `md5` ✅ `hash`
  - `ase` → `png` ✅ `palette_image`
  - `ase` → `qr_png` ✅ `qr`
  - `ase` → `sha` ✅ `hash`
- **多跳**（最多 2 跳）：
  - `ase` → `ascii_art` ✅ ase --[palette_image]--> png --[ascii_art]--> ascii_art
  - `ase` → `bmp` ✅ ase --[palette_image]--> png --[image]--> bmp
  - `ase` → `braille_art` ✅ ase --[palette_image]--> png --[ascii_art]--> braille_art
  - `ase` → `csv` ✅ ase --[color]--> json --[spreadsheet]--> csv
  - `ase` → `dds` ✅ ase --[palette_image]--> png --[texture]--> dds
  - `ase` → `docx` ✅ ase --[palette_image]--> png --[image_doc]--> docx
  - `ase` → `dst` ✅ ase --[palette_image]--> png --[embroidery]--> dst
  - `ase` → `gif` ✅ ase --[palette_image]--> png --[image]--> gif
  - `ase` → `ico` ✅ ase --[palette_image]--> png --[image]--> ico
  - `ase` → `jef` ✅ ase --[palette_image]--> png --[embroidery]--> jef
  - `ase` → `jpg` ✅ ase --[palette_image]--> png --[image]--> jpg
  - `ase` → `ktx` ✅ ase --[palette_image]--> png --[texture]--> ktx
  - `ase` → `pdf` ✅ ase --[palette_image]--> png --[pdf]--> pdf
  - `ase` → `pes` ✅ ase --[palette_image]--> png --[embroidery]--> pes
  - `ase` → `svg` ✅ ase --[palette_image]--> png --[svg_vector]--> svg
  - `ase` → `tga` ✅ ase --[palette_image]--> png --[texture]--> tga
  - `ase` → `tiff` ✅ ase --[palette_image]--> png --[image]--> tiff
  - `ase` → `webp` ✅ ase --[palette_image]--> png --[image]--> webp
  - `ase` → `xlsx` ✅ ase --[color]--> json --[spreadsheet]--> xlsx
  - `ase` → `xml` ✅ ase --[color]--> json --[spreadsheet]--> xml

#### `aco`（.aco） - ✅ 可读

- **直转**：
  - `aco` → `ase` ✅ `color`
  - `aco` → `base64` ✅ `hash`
  - `aco` → `crc` ✅ `hash`
  - `aco` → `gpl` ✅ `color`
  - `aco` → `identicon_png` ✅ `identicon`
  - `aco` → `json` ✅ `color`
  - `aco` → `md5` ✅ `hash`
  - `aco` → `png` ✅ `palette_image`
  - `aco` → `qr_png` ✅ `qr`
  - `aco` → `sha` ✅ `hash`
- **多跳**（最多 2 跳）：
  - `aco` → `ascii_art` ✅ aco --[palette_image]--> png --[ascii_art]--> ascii_art
  - `aco` → `bmp` ✅ aco --[palette_image]--> png --[image]--> bmp
  - `aco` → `braille_art` ✅ aco --[palette_image]--> png --[ascii_art]--> braille_art
  - `aco` → `csv` ✅ aco --[color]--> json --[spreadsheet]--> csv
  - `aco` → `dds` ✅ aco --[palette_image]--> png --[texture]--> dds
  - `aco` → `docx` ✅ aco --[palette_image]--> png --[image_doc]--> docx
  - `aco` → `dst` ✅ aco --[palette_image]--> png --[embroidery]--> dst
  - `aco` → `gif` ✅ aco --[palette_image]--> png --[image]--> gif
  - `aco` → `ico` ✅ aco --[palette_image]--> png --[image]--> ico
  - `aco` → `jef` ✅ aco --[palette_image]--> png --[embroidery]--> jef
  - `aco` → `jpg` ✅ aco --[palette_image]--> png --[image]--> jpg
  - `aco` → `ktx` ✅ aco --[palette_image]--> png --[texture]--> ktx
  - `aco` → `pdf` ✅ aco --[palette_image]--> png --[pdf]--> pdf
  - `aco` → `pes` ✅ aco --[palette_image]--> png --[embroidery]--> pes
  - `aco` → `svg` ✅ aco --[palette_image]--> png --[svg_vector]--> svg
  - `aco` → `tga` ✅ aco --[palette_image]--> png --[texture]--> tga
  - `aco` → `tiff` ✅ aco --[palette_image]--> png --[image]--> tiff
  - `aco` → `webp` ✅ aco --[palette_image]--> png --[image]--> webp
  - `aco` → `xlsx` ✅ aco --[color]--> json --[spreadsheet]--> xlsx
  - `aco` → `xml` ✅ aco --[color]--> json --[spreadsheet]--> xml

#### `gpl`（.gpl） - ✅ 可读

- **直转**：
  - `gpl` → `aco` ✅ `color`
  - `gpl` → `ase` ✅ `color`
  - `gpl` → `base64` ✅ `hash`
  - `gpl` → `crc` ✅ `hash`
  - `gpl` → `identicon_png` ✅ `identicon`
  - `gpl` → `json` ✅ `color`
  - `gpl` → `md5` ✅ `hash`
  - `gpl` → `png` ✅ `palette_image`
  - `gpl` → `qr_png` ✅ `qr`
  - `gpl` → `sha` ✅ `hash`
- **多跳**（最多 2 跳）：
  - `gpl` → `ascii_art` ✅ gpl --[palette_image]--> png --[ascii_art]--> ascii_art
  - `gpl` → `bmp` ✅ gpl --[palette_image]--> png --[image]--> bmp
  - `gpl` → `braille_art` ✅ gpl --[palette_image]--> png --[ascii_art]--> braille_art
  - `gpl` → `csv` ✅ gpl --[color]--> json --[spreadsheet]--> csv
  - `gpl` → `dds` ✅ gpl --[palette_image]--> png --[texture]--> dds
  - `gpl` → `docx` ✅ gpl --[palette_image]--> png --[image_doc]--> docx
  - `gpl` → `dst` ✅ gpl --[palette_image]--> png --[embroidery]--> dst
  - `gpl` → `gif` ✅ gpl --[palette_image]--> png --[image]--> gif
  - `gpl` → `ico` ✅ gpl --[palette_image]--> png --[image]--> ico
  - `gpl` → `jef` ✅ gpl --[palette_image]--> png --[embroidery]--> jef
  - `gpl` → `jpg` ✅ gpl --[palette_image]--> png --[image]--> jpg
  - `gpl` → `ktx` ✅ gpl --[palette_image]--> png --[texture]--> ktx
  - `gpl` → `pdf` ✅ gpl --[palette_image]--> png --[pdf]--> pdf
  - `gpl` → `pes` ✅ gpl --[palette_image]--> png --[embroidery]--> pes
  - `gpl` → `svg` ✅ gpl --[palette_image]--> png --[svg_vector]--> svg
  - `gpl` → `tga` ✅ gpl --[palette_image]--> png --[texture]--> tga
  - `gpl` → `tiff` ✅ gpl --[palette_image]--> png --[image]--> tiff
  - `gpl` → `webp` ✅ gpl --[palette_image]--> png --[image]--> webp
  - `gpl` → `xlsx` ✅ gpl --[color]--> json --[spreadsheet]--> xlsx
  - `gpl` → `xml` ✅ gpl --[color]--> json --[spreadsheet]--> xml

### 3D 模型（model3d）


#### `obj`（.obj） - ✅ 可读

- **直转**：
  - `obj` → `base64` ✅ `hash`
  - `obj` → `crc` ✅ `hash`
  - `obj` → `geo_json` ✅ `mesh_geo`
  - `obj` → `glb` ✅ `model3d`
  - `obj` → `gltf` ✅ `model3d`
  - `obj` → `identicon_png` ✅ `identicon`
  - `obj` → `jpg` ✅ `render3d`
  - `obj` → `md5` ✅ `hash`
  - `obj` → `off` ✅ `mesh`
  - `obj` → `ply` ✅ `mesh`
  - `obj` → `png` ✅ `render3d`
  - `obj` → `qr_png` ✅ `qr`
  - `obj` → `sha` ✅ `hash`
  - `obj` → `stl` ✅ `model3d`
- **多跳**（最多 2 跳）：
  - `obj` → `aco` ✅ obj --[render3d]--> png --[image_palette]--> aco
  - `obj` → `ascii_art` ✅ obj --[render3d]--> png --[ascii_art]--> ascii_art
  - `obj` → `ase` ✅ obj --[render3d]--> png --[image_palette]--> ase
  - `obj` → `bmp` ✅ obj --[render3d]--> png --[image]--> bmp
  - `obj` → `braille_art` ✅ obj --[render3d]--> png --[ascii_art]--> braille_art
  - `obj` → `dds` ✅ obj --[render3d]--> png --[texture]--> dds
  - `obj` → `docx` ✅ obj --[render3d]--> png --[image_doc]--> docx
  - `obj` → `dst` ✅ obj --[render3d]--> png --[embroidery]--> dst
  - `obj` → `gif` ✅ obj --[render3d]--> png --[image]--> gif
  - `obj` → `gpl` ✅ obj --[render3d]--> png --[image_palette]--> gpl
  - `obj` → `ico` ✅ obj --[render3d]--> png --[image]--> ico
  - `obj` → `jef` ✅ obj --[render3d]--> png --[embroidery]--> jef
  - `obj` → `json` ✅ obj --[render3d]--> png --[image_palette]--> json
  - `obj` → `ktx` ✅ obj --[render3d]--> png --[texture]--> ktx
  - `obj` → `pdf` ✅ obj --[render3d]--> png --[pdf]--> pdf
  - `obj` → `pes` ✅ obj --[render3d]--> png --[embroidery]--> pes
  - `obj` → `svg` ✅ obj --[render3d]--> png --[svg_vector]--> svg
  - `obj` → `tga` ✅ obj --[render3d]--> png --[texture]--> tga
  - `obj` → `tiff` ✅ obj --[render3d]--> png --[image]--> tiff
  - `obj` → `webp` ✅ obj --[render3d]--> png --[image]--> webp

#### `fbx`（.fbx） - ❌ 暂不支持

- **直转**：
  - `fbx` → `base64` ✅ `hash`
  - `fbx` → `crc` ✅ `hash`
  - `fbx` → `identicon_png` ✅ `identicon`
  - `fbx` → `md5` ✅ `hash`
  - `fbx` → `qr_png` ✅ `qr`
  - `fbx` → `sha` ✅ `hash`

#### `stl`（.stl） - ✅ 可读

- **直转**：
  - `stl` → `base64` ✅ `hash`
  - `stl` → `crc` ✅ `hash`
  - `stl` → `geo_json` ✅ `mesh_geo`
  - `stl` → `glb` ✅ `model3d`
  - `stl` → `gltf` ✅ `model3d`
  - `stl` → `identicon_png` ✅ `identicon`
  - `stl` → `jpg` ✅ `render3d`
  - `stl` → `md5` ✅ `hash`
  - `stl` → `obj` ✅ `model3d`
  - `stl` → `off` ✅ `mesh`
  - `stl` → `ply` ✅ `mesh`
  - `stl` → `png` ✅ `render3d`
  - `stl` → `qr_png` ✅ `qr`
  - `stl` → `sha` ✅ `hash`
- **多跳**（最多 2 跳）：
  - `stl` → `aco` ✅ stl --[render3d]--> png --[image_palette]--> aco
  - `stl` → `ascii_art` ✅ stl --[render3d]--> png --[ascii_art]--> ascii_art
  - `stl` → `ase` ✅ stl --[render3d]--> png --[image_palette]--> ase
  - `stl` → `bmp` ✅ stl --[render3d]--> png --[image]--> bmp
  - `stl` → `braille_art` ✅ stl --[render3d]--> png --[ascii_art]--> braille_art
  - `stl` → `dds` ✅ stl --[render3d]--> png --[texture]--> dds
  - `stl` → `docx` ✅ stl --[render3d]--> png --[image_doc]--> docx
  - `stl` → `dst` ✅ stl --[render3d]--> png --[embroidery]--> dst
  - `stl` → `gif` ✅ stl --[render3d]--> png --[image]--> gif
  - `stl` → `gpl` ✅ stl --[render3d]--> png --[image_palette]--> gpl
  - `stl` → `ico` ✅ stl --[render3d]--> png --[image]--> ico
  - `stl` → `jef` ✅ stl --[render3d]--> png --[embroidery]--> jef
  - `stl` → `json` ✅ stl --[render3d]--> png --[image_palette]--> json
  - `stl` → `ktx` ✅ stl --[render3d]--> png --[texture]--> ktx
  - `stl` → `pdf` ✅ stl --[render3d]--> png --[pdf]--> pdf
  - `stl` → `pes` ✅ stl --[render3d]--> png --[embroidery]--> pes
  - `stl` → `svg` ✅ stl --[render3d]--> png --[svg_vector]--> svg
  - `stl` → `tga` ✅ stl --[render3d]--> png --[texture]--> tga
  - `stl` → `tiff` ✅ stl --[render3d]--> png --[image]--> tiff
  - `stl` → `webp` ✅ stl --[render3d]--> png --[image]--> webp

#### `gltf`（.gltf） - ✅ 可读

- **直转**：
  - `gltf` → `base64` ✅ `hash`
  - `gltf` → `crc` ✅ `hash`
  - `gltf` → `geo_json` ✅ `mesh_geo`
  - `gltf` → `glb` ✅ `model3d`
  - `gltf` → `identicon_png` ✅ `identicon`
  - `gltf` → `jpg` ✅ `render3d`
  - `gltf` → `md5` ✅ `hash`
  - `gltf` → `obj` ✅ `model3d`
  - `gltf` → `off` ✅ `mesh`
  - `gltf` → `ply` ✅ `mesh`
  - `gltf` → `png` ✅ `render3d`
  - `gltf` → `qr_png` ✅ `qr`
  - `gltf` → `sha` ✅ `hash`
  - `gltf` → `stl` ✅ `model3d`
- **多跳**（最多 2 跳）：
  - `gltf` → `aco` ✅ gltf --[render3d]--> png --[image_palette]--> aco
  - `gltf` → `ascii_art` ✅ gltf --[render3d]--> png --[ascii_art]--> ascii_art
  - `gltf` → `ase` ✅ gltf --[render3d]--> png --[image_palette]--> ase
  - `gltf` → `bmp` ✅ gltf --[render3d]--> png --[image]--> bmp
  - `gltf` → `braille_art` ✅ gltf --[render3d]--> png --[ascii_art]--> braille_art
  - `gltf` → `dds` ✅ gltf --[render3d]--> png --[texture]--> dds
  - `gltf` → `docx` ✅ gltf --[render3d]--> png --[image_doc]--> docx
  - `gltf` → `dst` ✅ gltf --[render3d]--> png --[embroidery]--> dst
  - `gltf` → `gif` ✅ gltf --[render3d]--> png --[image]--> gif
  - `gltf` → `gpl` ✅ gltf --[render3d]--> png --[image_palette]--> gpl
  - `gltf` → `ico` ✅ gltf --[render3d]--> png --[image]--> ico
  - `gltf` → `jef` ✅ gltf --[render3d]--> png --[embroidery]--> jef
  - `gltf` → `json` ✅ gltf --[render3d]--> png --[image_palette]--> json
  - `gltf` → `ktx` ✅ gltf --[render3d]--> png --[texture]--> ktx
  - `gltf` → `pdf` ✅ gltf --[render3d]--> png --[pdf]--> pdf
  - `gltf` → `pes` ✅ gltf --[render3d]--> png --[embroidery]--> pes
  - `gltf` → `svg` ✅ gltf --[render3d]--> png --[svg_vector]--> svg
  - `gltf` → `tga` ✅ gltf --[render3d]--> png --[texture]--> tga
  - `gltf` → `tiff` ✅ gltf --[render3d]--> png --[image]--> tiff
  - `gltf` → `webp` ✅ gltf --[render3d]--> png --[image]--> webp

#### `glb`（.glb） - ✅ 可读

- **直转**：
  - `glb` → `base64` ✅ `hash`
  - `glb` → `crc` ✅ `hash`
  - `glb` → `geo_json` ✅ `mesh_geo`
  - `glb` → `gltf` ✅ `model3d`
  - `glb` → `identicon_png` ✅ `identicon`
  - `glb` → `jpg` ✅ `render3d`
  - `glb` → `md5` ✅ `hash`
  - `glb` → `obj` ✅ `model3d`
  - `glb` → `off` ✅ `mesh`
  - `glb` → `ply` ✅ `mesh`
  - `glb` → `png` ✅ `render3d`
  - `glb` → `qr_png` ✅ `qr`
  - `glb` → `sha` ✅ `hash`
  - `glb` → `stl` ✅ `model3d`
- **多跳**（最多 2 跳）：
  - `glb` → `aco` ✅ glb --[render3d]--> png --[image_palette]--> aco
  - `glb` → `ascii_art` ✅ glb --[render3d]--> png --[ascii_art]--> ascii_art
  - `glb` → `ase` ✅ glb --[render3d]--> png --[image_palette]--> ase
  - `glb` → `bmp` ✅ glb --[render3d]--> png --[image]--> bmp
  - `glb` → `braille_art` ✅ glb --[render3d]--> png --[ascii_art]--> braille_art
  - `glb` → `dds` ✅ glb --[render3d]--> png --[texture]--> dds
  - `glb` → `docx` ✅ glb --[render3d]--> png --[image_doc]--> docx
  - `glb` → `dst` ✅ glb --[render3d]--> png --[embroidery]--> dst
  - `glb` → `gif` ✅ glb --[render3d]--> png --[image]--> gif
  - `glb` → `gpl` ✅ glb --[render3d]--> png --[image_palette]--> gpl
  - `glb` → `ico` ✅ glb --[render3d]--> png --[image]--> ico
  - `glb` → `jef` ✅ glb --[render3d]--> png --[embroidery]--> jef
  - `glb` → `json` ✅ glb --[render3d]--> png --[image_palette]--> json
  - `glb` → `ktx` ✅ glb --[render3d]--> png --[texture]--> ktx
  - `glb` → `pdf` ✅ glb --[render3d]--> png --[pdf]--> pdf
  - `glb` → `pes` ✅ glb --[render3d]--> png --[embroidery]--> pes
  - `glb` → `svg` ✅ glb --[render3d]--> png --[svg_vector]--> svg
  - `glb` → `tga` ✅ glb --[render3d]--> png --[texture]--> tga
  - `glb` → `tiff` ✅ glb --[render3d]--> png --[image]--> tiff
  - `glb` → `webp` ✅ glb --[render3d]--> png --[image]--> webp

#### `geo_json`（.geo.json） - ✅ 可读

- **直转**：
  - `geo_json` → `base64` ✅ `hash`
  - `geo_json` → `crc` ✅ `hash`
  - `geo_json` → `identicon_png` ✅ `identicon`
  - `geo_json` → `md5` ✅ `hash`
  - `geo_json` → `qr_png` ✅ `qr`
  - `geo_json` → `sha` ✅ `hash`

### 纹理（texture）


#### `dds`（.dds） - ✅ 可读

- **直转**：
  - `dds` → `base64` ✅ `hash`
  - `dds` → `crc` ✅ `hash`
  - `dds` → `identicon_png` ✅ `identicon`
  - `dds` → `jpg` ✅ `texture`
  - `dds` → `md5` ✅ `hash`
  - `dds` → `png` ✅ `texture`
  - `dds` → `qr_png` ✅ `qr`
  - `dds` → `sha` ✅ `hash`
  - `dds` → `tga` ✅ `texture`
  - `dds` → `webp` ✅ `texture`
- **多跳**（最多 2 跳）：
  - `dds` → `aco` ✅ dds --[texture]--> png --[image_palette]--> aco
  - `dds` → `ascii_art` ✅ dds --[texture]--> png --[ascii_art]--> ascii_art
  - `dds` → `ase` ✅ dds --[texture]--> png --[image_palette]--> ase
  - `dds` → `bmp` ✅ dds --[texture]--> png --[image]--> bmp
  - `dds` → `braille_art` ✅ dds --[texture]--> png --[ascii_art]--> braille_art
  - `dds` → `docx` ✅ dds --[texture]--> png --[image_doc]--> docx
  - `dds` → `dst` ✅ dds --[texture]--> png --[embroidery]--> dst
  - `dds` → `gif` ✅ dds --[texture]--> png --[image]--> gif
  - `dds` → `gpl` ✅ dds --[texture]--> png --[image_palette]--> gpl
  - `dds` → `ico` ✅ dds --[texture]--> png --[image]--> ico
  - `dds` → `jef` ✅ dds --[texture]--> png --[embroidery]--> jef
  - `dds` → `json` ✅ dds --[texture]--> png --[image_palette]--> json
  - `dds` → `ktx` ✅ dds --[texture]--> png --[texture]--> ktx
  - `dds` → `pdf` ✅ dds --[texture]--> png --[pdf]--> pdf
  - `dds` → `pes` ✅ dds --[texture]--> png --[embroidery]--> pes
  - `dds` → `svg` ✅ dds --[texture]--> png --[svg_vector]--> svg
  - `dds` → `tiff` ✅ dds --[texture]--> png --[image]--> tiff

#### `astc`（.astc） - ❌ 暂不支持

- **直转**：
  - `astc` → `base64` ✅ `hash`
  - `astc` → `crc` ✅ `hash`
  - `astc` → `identicon_png` ✅ `identicon`
  - `astc` → `md5` ✅ `hash`
  - `astc` → `qr_png` ✅ `qr`
  - `astc` → `sha` ✅ `hash`

#### `ktx`（.ktx） - ✅ 可读

- **直转**：
  - `ktx` → `base64` ✅ `hash`
  - `ktx` → `crc` ✅ `hash`
  - `ktx` → `dds` ✅ `texture`
  - `ktx` → `identicon_png` ✅ `identicon`
  - `ktx` → `jpg` ✅ `texture`
  - `ktx` → `md5` ✅ `hash`
  - `ktx` → `png` ✅ `texture`
  - `ktx` → `qr_png` ✅ `qr`
  - `ktx` → `sha` ✅ `hash`
  - `ktx` → `tga` ✅ `texture`
  - `ktx` → `webp` ✅ `texture`
- **多跳**（最多 2 跳）：
  - `ktx` → `aco` ✅ ktx --[texture]--> png --[image_palette]--> aco
  - `ktx` → `ascii_art` ✅ ktx --[texture]--> png --[ascii_art]--> ascii_art
  - `ktx` → `ase` ✅ ktx --[texture]--> png --[image_palette]--> ase
  - `ktx` → `bmp` ✅ ktx --[texture]--> png --[image]--> bmp
  - `ktx` → `braille_art` ✅ ktx --[texture]--> png --[ascii_art]--> braille_art
  - `ktx` → `docx` ✅ ktx --[texture]--> png --[image_doc]--> docx
  - `ktx` → `dst` ✅ ktx --[texture]--> png --[embroidery]--> dst
  - `ktx` → `gif` ✅ ktx --[texture]--> png --[image]--> gif
  - `ktx` → `gpl` ✅ ktx --[texture]--> png --[image_palette]--> gpl
  - `ktx` → `ico` ✅ ktx --[texture]--> png --[image]--> ico
  - `ktx` → `jef` ✅ ktx --[texture]--> png --[embroidery]--> jef
  - `ktx` → `json` ✅ ktx --[texture]--> png --[image_palette]--> json
  - `ktx` → `pdf` ✅ ktx --[texture]--> png --[pdf]--> pdf
  - `ktx` → `pes` ✅ ktx --[texture]--> png --[embroidery]--> pes
  - `ktx` → `svg` ✅ ktx --[texture]--> png --[svg_vector]--> svg
  - `ktx` → `tiff` ✅ ktx --[texture]--> png --[image]--> tiff

#### `xnb`（.xnb） - ❌ 暂不支持

- **直转**：
  - `xnb` → `base64` ✅ `hash`
  - `xnb` → `crc` ✅ `hash`
  - `xnb` → `identicon_png` ✅ `identicon`
  - `xnb` → `md5` ✅ `hash`
  - `xnb` → `qr_png` ✅ `qr`
  - `xnb` → `sha` ✅ `hash`

#### `tga`（.tga） - ✅ 可读

- **直转**：
  - `tga` → `base64` ✅ `hash`
  - `tga` → `bmp` ✅ `image`
  - `tga` → `crc` ✅ `hash`
  - `tga` → `dds` ✅ `texture`
  - `tga` → `gif` ✅ `image`
  - `tga` → `ico` ✅ `image`
  - `tga` → `identicon_png` ✅ `identicon`
  - `tga` → `jpg` ✅ `texture`
  - `tga` → `md5` ✅ `hash`
  - `tga` → `png` ✅ `texture`
  - `tga` → `qr_png` ✅ `qr`
  - `tga` → `sha` ✅ `hash`
  - `tga` → `tiff` ✅ `image`
  - `tga` → `webp` ✅ `texture`
- **多跳**（最多 2 跳）：
  - `tga` → `aco` ✅ tga --[texture]--> png --[image_palette]--> aco
  - `tga` → `ascii_art` ✅ tga --[texture]--> png --[ascii_art]--> ascii_art
  - `tga` → `ase` ✅ tga --[texture]--> png --[image_palette]--> ase
  - `tga` → `braille_art` ✅ tga --[texture]--> png --[ascii_art]--> braille_art
  - `tga` → `docx` ✅ tga --[texture]--> png --[image_doc]--> docx
  - `tga` → `dst` ✅ tga --[texture]--> png --[embroidery]--> dst
  - `tga` → `gpl` ✅ tga --[texture]--> png --[image_palette]--> gpl
  - `tga` → `jef` ✅ tga --[texture]--> png --[embroidery]--> jef
  - `tga` → `json` ✅ tga --[texture]--> png --[image_palette]--> json
  - `tga` → `ktx` ✅ tga --[texture]--> png --[texture]--> ktx
  - `tga` → `pdf` ✅ tga --[texture]--> png --[pdf]--> pdf
  - `tga` → `pes` ✅ tga --[texture]--> png --[embroidery]--> pes
  - `tga` → `svg` ✅ tga --[texture]--> png --[svg_vector]--> svg

### 网格（mesh）


#### `ply`（.ply） - ✅ 可读

- **直转**：
  - `ply` → `base64` ✅ `hash`
  - `ply` → `crc` ✅ `hash`
  - `ply` → `geo_json` ✅ `mesh_geo`
  - `ply` → `glb` ✅ `model3d`
  - `ply` → `gltf` ✅ `model3d`
  - `ply` → `identicon_png` ✅ `identicon`
  - `ply` → `jpg` ✅ `render3d`
  - `ply` → `md5` ✅ `hash`
  - `ply` → `obj` ✅ `model3d`
  - `ply` → `off` ✅ `mesh`
  - `ply` → `png` ✅ `render3d`
  - `ply` → `qr_png` ✅ `qr`
  - `ply` → `sha` ✅ `hash`
  - `ply` → `stl` ✅ `model3d`
- **多跳**（最多 2 跳）：
  - `ply` → `aco` ✅ ply --[render3d]--> png --[image_palette]--> aco
  - `ply` → `ascii_art` ✅ ply --[render3d]--> png --[ascii_art]--> ascii_art
  - `ply` → `ase` ✅ ply --[render3d]--> png --[image_palette]--> ase
  - `ply` → `bmp` ✅ ply --[render3d]--> png --[image]--> bmp
  - `ply` → `braille_art` ✅ ply --[render3d]--> png --[ascii_art]--> braille_art
  - `ply` → `dds` ✅ ply --[render3d]--> png --[texture]--> dds
  - `ply` → `docx` ✅ ply --[render3d]--> png --[image_doc]--> docx
  - `ply` → `dst` ✅ ply --[render3d]--> png --[embroidery]--> dst
  - `ply` → `gif` ✅ ply --[render3d]--> png --[image]--> gif
  - `ply` → `gpl` ✅ ply --[render3d]--> png --[image_palette]--> gpl
  - `ply` → `ico` ✅ ply --[render3d]--> png --[image]--> ico
  - `ply` → `jef` ✅ ply --[render3d]--> png --[embroidery]--> jef
  - `ply` → `json` ✅ ply --[render3d]--> png --[image_palette]--> json
  - `ply` → `ktx` ✅ ply --[render3d]--> png --[texture]--> ktx
  - `ply` → `pdf` ✅ ply --[render3d]--> png --[pdf]--> pdf
  - `ply` → `pes` ✅ ply --[render3d]--> png --[embroidery]--> pes
  - `ply` → `svg` ✅ ply --[render3d]--> png --[svg_vector]--> svg
  - `ply` → `tga` ✅ ply --[render3d]--> png --[texture]--> tga
  - `ply` → `tiff` ✅ ply --[render3d]--> png --[image]--> tiff
  - `ply` → `webp` ✅ ply --[render3d]--> png --[image]--> webp

#### `off`（.off） - ✅ 可读

- **直转**：
  - `off` → `base64` ✅ `hash`
  - `off` → `crc` ✅ `hash`
  - `off` → `geo_json` ✅ `mesh_geo`
  - `off` → `glb` ✅ `model3d`
  - `off` → `gltf` ✅ `model3d`
  - `off` → `identicon_png` ✅ `identicon`
  - `off` → `jpg` ✅ `render3d`
  - `off` → `md5` ✅ `hash`
  - `off` → `obj` ✅ `model3d`
  - `off` → `ply` ✅ `mesh`
  - `off` → `png` ✅ `render3d`
  - `off` → `qr_png` ✅ `qr`
  - `off` → `sha` ✅ `hash`
  - `off` → `stl` ✅ `model3d`
- **多跳**（最多 2 跳）：
  - `off` → `aco` ✅ off --[render3d]--> png --[image_palette]--> aco
  - `off` → `ascii_art` ✅ off --[render3d]--> png --[ascii_art]--> ascii_art
  - `off` → `ase` ✅ off --[render3d]--> png --[image_palette]--> ase
  - `off` → `bmp` ✅ off --[render3d]--> png --[image]--> bmp
  - `off` → `braille_art` ✅ off --[render3d]--> png --[ascii_art]--> braille_art
  - `off` → `dds` ✅ off --[render3d]--> png --[texture]--> dds
  - `off` → `docx` ✅ off --[render3d]--> png --[image_doc]--> docx
  - `off` → `dst` ✅ off --[render3d]--> png --[embroidery]--> dst
  - `off` → `gif` ✅ off --[render3d]--> png --[image]--> gif
  - `off` → `gpl` ✅ off --[render3d]--> png --[image_palette]--> gpl
  - `off` → `ico` ✅ off --[render3d]--> png --[image]--> ico
  - `off` → `jef` ✅ off --[render3d]--> png --[embroidery]--> jef
  - `off` → `json` ✅ off --[render3d]--> png --[image_palette]--> json
  - `off` → `ktx` ✅ off --[render3d]--> png --[texture]--> ktx
  - `off` → `pdf` ✅ off --[render3d]--> png --[pdf]--> pdf
  - `off` → `pes` ✅ off --[render3d]--> png --[embroidery]--> pes
  - `off` → `svg` ✅ off --[render3d]--> png --[svg_vector]--> svg
  - `off` → `tga` ✅ off --[render3d]--> png --[texture]--> tga
  - `off` → `tiff` ✅ off --[render3d]--> png --[image]--> tiff
  - `off` → `webp` ✅ off --[render3d]--> png --[image]--> webp

### 哈希计算（hash）


#### `md5`（.md5） - ✅ 可读

- （无出边：该格式没有可用的写出引擎，或上游读取能力未接入）

#### `sha`（.sha） - ✅ 可读

- （无出边：该格式没有可用的写出引擎，或上游读取能力未接入）

#### `crc`（.crc） - ✅ 可读

- （无出边：该格式没有可用的写出引擎，或上游读取能力未接入）

#### `base64`（.b64） - ✅ 可读

- （无出边：该格式没有可用的写出引擎，或上游读取能力未接入）

### 绣花（embroidery）


#### `pes`（.pes） - ✅ 可读

- **直转**：
  - `pes` → `base64` ✅ `hash`
  - `pes` → `crc` ✅ `hash`
  - `pes` → `dst` ✅ `embroidery`
  - `pes` → `identicon_png` ✅ `identicon`
  - `pes` → `jef` ✅ `embroidery`
  - `pes` → `md5` ✅ `hash`
  - `pes` → `png` ✅ `embroidery`
  - `pes` → `qr_png` ✅ `qr`
  - `pes` → `sha` ✅ `hash`
- **多跳**（最多 2 跳）：
  - `pes` → `aco` ✅ pes --[embroidery]--> png --[image_palette]--> aco
  - `pes` → `ascii_art` ✅ pes --[embroidery]--> png --[ascii_art]--> ascii_art
  - `pes` → `ase` ✅ pes --[embroidery]--> png --[image_palette]--> ase
  - `pes` → `bmp` ✅ pes --[embroidery]--> png --[image]--> bmp
  - `pes` → `braille_art` ✅ pes --[embroidery]--> png --[ascii_art]--> braille_art
  - `pes` → `dds` ✅ pes --[embroidery]--> png --[texture]--> dds
  - `pes` → `docx` ✅ pes --[embroidery]--> png --[image_doc]--> docx
  - `pes` → `gif` ✅ pes --[embroidery]--> png --[image]--> gif
  - `pes` → `gpl` ✅ pes --[embroidery]--> png --[image_palette]--> gpl
  - `pes` → `ico` ✅ pes --[embroidery]--> png --[image]--> ico
  - `pes` → `jpg` ✅ pes --[embroidery]--> png --[image]--> jpg
  - `pes` → `json` ✅ pes --[embroidery]--> png --[image_palette]--> json
  - `pes` → `ktx` ✅ pes --[embroidery]--> png --[texture]--> ktx
  - `pes` → `pdf` ✅ pes --[embroidery]--> png --[pdf]--> pdf
  - `pes` → `svg` ✅ pes --[embroidery]--> png --[svg_vector]--> svg
  - `pes` → `tga` ✅ pes --[embroidery]--> png --[texture]--> tga
  - `pes` → `tiff` ✅ pes --[embroidery]--> png --[image]--> tiff
  - `pes` → `webp` ✅ pes --[embroidery]--> png --[image]--> webp

#### `dst`（.dst） - ✅ 可读

- **直转**：
  - `dst` → `base64` ✅ `hash`
  - `dst` → `crc` ✅ `hash`
  - `dst` → `identicon_png` ✅ `identicon`
  - `dst` → `jef` ✅ `embroidery`
  - `dst` → `md5` ✅ `hash`
  - `dst` → `pes` ✅ `embroidery`
  - `dst` → `png` ✅ `embroidery`
  - `dst` → `qr_png` ✅ `qr`
  - `dst` → `sha` ✅ `hash`
- **多跳**（最多 2 跳）：
  - `dst` → `aco` ✅ dst --[embroidery]--> png --[image_palette]--> aco
  - `dst` → `ascii_art` ✅ dst --[embroidery]--> png --[ascii_art]--> ascii_art
  - `dst` → `ase` ✅ dst --[embroidery]--> png --[image_palette]--> ase
  - `dst` → `bmp` ✅ dst --[embroidery]--> png --[image]--> bmp
  - `dst` → `braille_art` ✅ dst --[embroidery]--> png --[ascii_art]--> braille_art
  - `dst` → `dds` ✅ dst --[embroidery]--> png --[texture]--> dds
  - `dst` → `docx` ✅ dst --[embroidery]--> png --[image_doc]--> docx
  - `dst` → `gif` ✅ dst --[embroidery]--> png --[image]--> gif
  - `dst` → `gpl` ✅ dst --[embroidery]--> png --[image_palette]--> gpl
  - `dst` → `ico` ✅ dst --[embroidery]--> png --[image]--> ico
  - `dst` → `jpg` ✅ dst --[embroidery]--> png --[image]--> jpg
  - `dst` → `json` ✅ dst --[embroidery]--> png --[image_palette]--> json
  - `dst` → `ktx` ✅ dst --[embroidery]--> png --[texture]--> ktx
  - `dst` → `pdf` ✅ dst --[embroidery]--> png --[pdf]--> pdf
  - `dst` → `svg` ✅ dst --[embroidery]--> png --[svg_vector]--> svg
  - `dst` → `tga` ✅ dst --[embroidery]--> png --[texture]--> tga
  - `dst` → `tiff` ✅ dst --[embroidery]--> png --[image]--> tiff
  - `dst` → `webp` ✅ dst --[embroidery]--> png --[image]--> webp

#### `jef`（.jef） - ✅ 可读

- **直转**：
  - `jef` → `base64` ✅ `hash`
  - `jef` → `crc` ✅ `hash`
  - `jef` → `dst` ✅ `embroidery`
  - `jef` → `identicon_png` ✅ `identicon`
  - `jef` → `md5` ✅ `hash`
  - `jef` → `pes` ✅ `embroidery`
  - `jef` → `png` ✅ `embroidery`
  - `jef` → `qr_png` ✅ `qr`
  - `jef` → `sha` ✅ `hash`
- **多跳**（最多 2 跳）：
  - `jef` → `aco` ✅ jef --[embroidery]--> png --[image_palette]--> aco
  - `jef` → `ascii_art` ✅ jef --[embroidery]--> png --[ascii_art]--> ascii_art
  - `jef` → `ase` ✅ jef --[embroidery]--> png --[image_palette]--> ase
  - `jef` → `bmp` ✅ jef --[embroidery]--> png --[image]--> bmp
  - `jef` → `braille_art` ✅ jef --[embroidery]--> png --[ascii_art]--> braille_art
  - `jef` → `dds` ✅ jef --[embroidery]--> png --[texture]--> dds
  - `jef` → `docx` ✅ jef --[embroidery]--> png --[image_doc]--> docx
  - `jef` → `gif` ✅ jef --[embroidery]--> png --[image]--> gif
  - `jef` → `gpl` ✅ jef --[embroidery]--> png --[image_palette]--> gpl
  - `jef` → `ico` ✅ jef --[embroidery]--> png --[image]--> ico
  - `jef` → `jpg` ✅ jef --[embroidery]--> png --[image]--> jpg
  - `jef` → `json` ✅ jef --[embroidery]--> png --[image_palette]--> json
  - `jef` → `ktx` ✅ jef --[embroidery]--> png --[texture]--> ktx
  - `jef` → `pdf` ✅ jef --[embroidery]--> png --[pdf]--> pdf
  - `jef` → `svg` ✅ jef --[embroidery]--> png --[svg_vector]--> svg
  - `jef` → `tga` ✅ jef --[embroidery]--> png --[texture]--> tga
  - `jef` → `tiff` ✅ jef --[embroidery]--> png --[image]--> tiff
  - `jef` → `webp` ✅ jef --[embroidery]--> png --[image]--> webp

### GPS（gps）


#### `gpx`（.gpx） - ✅ 可读

- **直转**：
  - `gpx` → `base64` ✅ `hash`
  - `gpx` → `crc` ✅ `hash`
  - `gpx` → `geojson` ✅ `gps`
  - `gpx` → `identicon_png` ✅ `identicon`
  - `gpx` → `kml` ✅ `gps`
  - `gpx` → `md5` ✅ `hash`
  - `gpx` → `png` ✅ `geo_render`
  - `gpx` → `qr_png` ✅ `qr`
  - `gpx` → `sha` ✅ `hash`
  - `gpx` → `svg` ✅ `geo_render`
  - `gpx` → `tcx` ✅ `gps`
- **多跳**（最多 2 跳）：
  - `gpx` → `aco` ✅ gpx --[geo_render]--> png --[image_palette]--> aco
  - `gpx` → `ascii_art` ✅ gpx --[geo_render]--> png --[ascii_art]--> ascii_art
  - `gpx` → `ase` ✅ gpx --[geo_render]--> png --[image_palette]--> ase
  - `gpx` → `bmp` ✅ gpx --[geo_render]--> png --[image]--> bmp
  - `gpx` → `braille_art` ✅ gpx --[geo_render]--> png --[ascii_art]--> braille_art
  - `gpx` → `dds` ✅ gpx --[geo_render]--> png --[texture]--> dds
  - `gpx` → `docx` ✅ gpx --[geo_render]--> png --[image_doc]--> docx
  - `gpx` → `dst` ✅ gpx --[geo_render]--> png --[embroidery]--> dst
  - `gpx` → `gif` ✅ gpx --[geo_render]--> png --[image]--> gif
  - `gpx` → `gpl` ✅ gpx --[geo_render]--> png --[image_palette]--> gpl
  - `gpx` → `ico` ✅ gpx --[geo_render]--> png --[image]--> ico
  - `gpx` → `jef` ✅ gpx --[geo_render]--> png --[embroidery]--> jef
  - `gpx` → `jpg` ✅ gpx --[geo_render]--> png --[image]--> jpg
  - `gpx` → `json` ✅ gpx --[geo_render]--> png --[image_palette]--> json
  - `gpx` → `ktx` ✅ gpx --[geo_render]--> png --[texture]--> ktx
  - `gpx` → `pdf` ✅ gpx --[geo_render]--> png --[pdf]--> pdf
  - `gpx` → `pes` ✅ gpx --[geo_render]--> png --[embroidery]--> pes
  - `gpx` → `tga` ✅ gpx --[geo_render]--> png --[texture]--> tga
  - `gpx` → `tiff` ✅ gpx --[geo_render]--> png --[image]--> tiff
  - `gpx` → `webp` ✅ gpx --[geo_render]--> png --[image]--> webp

#### `kml`（.kml） - ✅ 可读

- **直转**：
  - `kml` → `base64` ✅ `hash`
  - `kml` → `crc` ✅ `hash`
  - `kml` → `geojson` ✅ `gps`
  - `kml` → `gpx` ✅ `gps`
  - `kml` → `identicon_png` ✅ `identicon`
  - `kml` → `md5` ✅ `hash`
  - `kml` → `png` ✅ `geo_render`
  - `kml` → `qr_png` ✅ `qr`
  - `kml` → `sha` ✅ `hash`
  - `kml` → `svg` ✅ `geo_render`
  - `kml` → `tcx` ✅ `gps`
- **多跳**（最多 2 跳）：
  - `kml` → `aco` ✅ kml --[geo_render]--> png --[image_palette]--> aco
  - `kml` → `ascii_art` ✅ kml --[geo_render]--> png --[ascii_art]--> ascii_art
  - `kml` → `ase` ✅ kml --[geo_render]--> png --[image_palette]--> ase
  - `kml` → `bmp` ✅ kml --[geo_render]--> png --[image]--> bmp
  - `kml` → `braille_art` ✅ kml --[geo_render]--> png --[ascii_art]--> braille_art
  - `kml` → `dds` ✅ kml --[geo_render]--> png --[texture]--> dds
  - `kml` → `docx` ✅ kml --[geo_render]--> png --[image_doc]--> docx
  - `kml` → `dst` ✅ kml --[geo_render]--> png --[embroidery]--> dst
  - `kml` → `gif` ✅ kml --[geo_render]--> png --[image]--> gif
  - `kml` → `gpl` ✅ kml --[geo_render]--> png --[image_palette]--> gpl
  - `kml` → `ico` ✅ kml --[geo_render]--> png --[image]--> ico
  - `kml` → `jef` ✅ kml --[geo_render]--> png --[embroidery]--> jef
  - `kml` → `jpg` ✅ kml --[geo_render]--> png --[image]--> jpg
  - `kml` → `json` ✅ kml --[geo_render]--> png --[image_palette]--> json
  - `kml` → `ktx` ✅ kml --[geo_render]--> png --[texture]--> ktx
  - `kml` → `pdf` ✅ kml --[geo_render]--> png --[pdf]--> pdf
  - `kml` → `pes` ✅ kml --[geo_render]--> png --[embroidery]--> pes
  - `kml` → `tga` ✅ kml --[geo_render]--> png --[texture]--> tga
  - `kml` → `tiff` ✅ kml --[geo_render]--> png --[image]--> tiff
  - `kml` → `webp` ✅ kml --[geo_render]--> png --[image]--> webp

#### `tcx`（.tcx） - ✅ 可读

- **直转**：
  - `tcx` → `base64` ✅ `hash`
  - `tcx` → `crc` ✅ `hash`
  - `tcx` → `geojson` ✅ `gps`
  - `tcx` → `gpx` ✅ `gps`
  - `tcx` → `identicon_png` ✅ `identicon`
  - `tcx` → `kml` ✅ `gps`
  - `tcx` → `md5` ✅ `hash`
  - `tcx` → `png` ✅ `geo_render`
  - `tcx` → `qr_png` ✅ `qr`
  - `tcx` → `sha` ✅ `hash`
  - `tcx` → `svg` ✅ `geo_render`
- **多跳**（最多 2 跳）：
  - `tcx` → `aco` ✅ tcx --[geo_render]--> png --[image_palette]--> aco
  - `tcx` → `ascii_art` ✅ tcx --[geo_render]--> png --[ascii_art]--> ascii_art
  - `tcx` → `ase` ✅ tcx --[geo_render]--> png --[image_palette]--> ase
  - `tcx` → `bmp` ✅ tcx --[geo_render]--> png --[image]--> bmp
  - `tcx` → `braille_art` ✅ tcx --[geo_render]--> png --[ascii_art]--> braille_art
  - `tcx` → `dds` ✅ tcx --[geo_render]--> png --[texture]--> dds
  - `tcx` → `docx` ✅ tcx --[geo_render]--> png --[image_doc]--> docx
  - `tcx` → `dst` ✅ tcx --[geo_render]--> png --[embroidery]--> dst
  - `tcx` → `gif` ✅ tcx --[geo_render]--> png --[image]--> gif
  - `tcx` → `gpl` ✅ tcx --[geo_render]--> png --[image_palette]--> gpl
  - `tcx` → `ico` ✅ tcx --[geo_render]--> png --[image]--> ico
  - `tcx` → `jef` ✅ tcx --[geo_render]--> png --[embroidery]--> jef
  - `tcx` → `jpg` ✅ tcx --[geo_render]--> png --[image]--> jpg
  - `tcx` → `json` ✅ tcx --[geo_render]--> png --[image_palette]--> json
  - `tcx` → `ktx` ✅ tcx --[geo_render]--> png --[texture]--> ktx
  - `tcx` → `pdf` ✅ tcx --[geo_render]--> png --[pdf]--> pdf
  - `tcx` → `pes` ✅ tcx --[geo_render]--> png --[embroidery]--> pes
  - `tcx` → `tga` ✅ tcx --[geo_render]--> png --[texture]--> tga
  - `tcx` → `tiff` ✅ tcx --[geo_render]--> png --[image]--> tiff
  - `tcx` → `webp` ✅ tcx --[geo_render]--> png --[image]--> webp

#### `geojson`（.geojson） - ✅ 可读

- **直转**：
  - `geojson` → `base64` ✅ `hash`
  - `geojson` → `crc` ✅ `hash`
  - `geojson` → `gpx` ✅ `gps`
  - `geojson` → `identicon_png` ✅ `identicon`
  - `geojson` → `kml` ✅ `gps`
  - `geojson` → `md5` ✅ `hash`
  - `geojson` → `png` ✅ `geo_render`
  - `geojson` → `qr_png` ✅ `qr`
  - `geojson` → `sha` ✅ `hash`
  - `geojson` → `svg` ✅ `geo_render`
  - `geojson` → `tcx` ✅ `gps`
- **多跳**（最多 2 跳）：
  - `geojson` → `aco` ✅ geojson --[geo_render]--> png --[image_palette]--> aco
  - `geojson` → `ascii_art` ✅ geojson --[geo_render]--> png --[ascii_art]--> ascii_art
  - `geojson` → `ase` ✅ geojson --[geo_render]--> png --[image_palette]--> ase
  - `geojson` → `bmp` ✅ geojson --[geo_render]--> png --[image]--> bmp
  - `geojson` → `braille_art` ✅ geojson --[geo_render]--> png --[ascii_art]--> braille_art
  - `geojson` → `dds` ✅ geojson --[geo_render]--> png --[texture]--> dds
  - `geojson` → `docx` ✅ geojson --[geo_render]--> png --[image_doc]--> docx
  - `geojson` → `dst` ✅ geojson --[geo_render]--> png --[embroidery]--> dst
  - `geojson` → `gif` ✅ geojson --[geo_render]--> png --[image]--> gif
  - `geojson` → `gpl` ✅ geojson --[geo_render]--> png --[image_palette]--> gpl
  - `geojson` → `ico` ✅ geojson --[geo_render]--> png --[image]--> ico
  - `geojson` → `jef` ✅ geojson --[geo_render]--> png --[embroidery]--> jef
  - `geojson` → `jpg` ✅ geojson --[geo_render]--> png --[image]--> jpg
  - `geojson` → `json` ✅ geojson --[geo_render]--> png --[image_palette]--> json
  - `geojson` → `ktx` ✅ geojson --[geo_render]--> png --[texture]--> ktx
  - `geojson` → `pdf` ✅ geojson --[geo_render]--> png --[pdf]--> pdf
  - `geojson` → `pes` ✅ geojson --[geo_render]--> png --[embroidery]--> pes
  - `geojson` → `tga` ✅ geojson --[geo_render]--> png --[texture]--> tga
  - `geojson` → `tiff` ✅ geojson --[geo_render]--> png --[image]--> tiff
  - `geojson` → `webp` ✅ geojson --[geo_render]--> png --[image]--> webp

### 字幕（subtitle）


#### `srt`（.srt） - ✅ 可读

- **直转**：
  - `srt` → `ass` ✅ `subtitle`
  - `srt` → `base64` ✅ `hash`
  - `srt` → `crc` ✅ `hash`
  - `srt` → `identicon_png` ✅ `identicon`
  - `srt` → `lrc` ✅ `subtitle`
  - `srt` → `md5` ✅ `hash`
  - `srt` → `qr_png` ✅ `qr`
  - `srt` → `sha` ✅ `hash`
  - `srt` → `vtt` ✅ `subtitle`

#### `ass`（.ass） - ✅ 可读

- **直转**：
  - `ass` → `base64` ✅ `hash`
  - `ass` → `crc` ✅ `hash`
  - `ass` → `identicon_png` ✅ `identicon`
  - `ass` → `lrc` ✅ `subtitle`
  - `ass` → `md5` ✅ `hash`
  - `ass` → `qr_png` ✅ `qr`
  - `ass` → `sha` ✅ `hash`
  - `ass` → `srt` ✅ `subtitle`
  - `ass` → `vtt` ✅ `subtitle`

#### `vtt`（.vtt） - ✅ 可读

- **直转**：
  - `vtt` → `ass` ✅ `subtitle`
  - `vtt` → `base64` ✅ `hash`
  - `vtt` → `crc` ✅ `hash`
  - `vtt` → `identicon_png` ✅ `identicon`
  - `vtt` → `lrc` ✅ `subtitle`
  - `vtt` → `md5` ✅ `hash`
  - `vtt` → `qr_png` ✅ `qr`
  - `vtt` → `sha` ✅ `hash`
  - `vtt` → `srt` ✅ `subtitle`

#### `lrc`（.lrc） - ✅ 可读

- **直转**：
  - `lrc` → `ass` ✅ `subtitle`
  - `lrc` → `base64` ✅ `hash`
  - `lrc` → `crc` ✅ `hash`
  - `lrc` → `identicon_png` ✅ `identicon`
  - `lrc` → `md5` ✅ `hash`
  - `lrc` → `qr_png` ✅ `qr`
  - `lrc` → `sha` ✅ `hash`
  - `lrc` → `srt` ✅ `subtitle`
  - `lrc` → `vtt` ✅ `subtitle`

### 播放列表（playlist）


#### `m3u`（.m3u） - ✅ 可读

- **直转**：
  - `m3u` → `base64` ✅ `hash`
  - `m3u` → `crc` ✅ `hash`
  - `m3u` → `cue` ✅ `playlist`
  - `m3u` → `identicon_png` ✅ `identicon`
  - `m3u` → `m3u8` ✅ `playlist`
  - `m3u` → `md5` ✅ `hash`
  - `m3u` → `qr_png` ✅ `qr`
  - `m3u` → `sha` ✅ `hash`

#### `m3u8`（.m3u8） - ✅ 可读

- **直转**：
  - `m3u8` → `base64` ✅ `hash`
  - `m3u8` → `crc` ✅ `hash`
  - `m3u8` → `cue` ✅ `playlist`
  - `m3u8` → `identicon_png` ✅ `identicon`
  - `m3u8` → `m3u` ✅ `playlist`
  - `m3u8` → `md5` ✅ `hash`
  - `m3u8` → `qr_png` ✅ `qr`
  - `m3u8` → `sha` ✅ `hash`

#### `cue`（.cue） - ✅ 可读

- **直转**：
  - `cue` → `base64` ✅ `hash`
  - `cue` → `crc` ✅ `hash`
  - `cue` → `identicon_png` ✅ `identicon`
  - `cue` → `m3u` ✅ `playlist`
  - `cue` → `m3u8` ✅ `playlist`
  - `cue` → `md5` ✅ `hash`
  - `cue` → `qr_png` ✅ `qr`
  - `cue` → `sha` ✅ `hash`

### 压缩包（archive）


#### `zip`（.zip） - ✅ 可读

- **直转**：
  - `zip` → `base64` ✅ `hash`
  - `zip` → `crc` ✅ `hash`
  - `zip` → `identicon_png` ✅ `identicon`
  - `zip` → `mcpack` ✅ `minecraft`
  - `zip` → `mcpack_java` ✅ `minecraft`
  - `zip` → `mcworld` ✅ `minecraft`
  - `zip` → `mcworld_java` ✅ `minecraft`
  - `zip` → `md5` ✅ `hash`
  - `zip` → `qr_png` ✅ `qr`
  - `zip` → `sha` ✅ `hash`
  - `zip` → `tar_gz` ✅ `archive`

#### `rar`（.rar） - ❌ 暂不支持

- **直转**：
  - `rar` → `base64` ✅ `hash`
  - `rar` → `crc` ✅ `hash`
  - `rar` → `identicon_png` ✅ `identicon`
  - `rar` → `md5` ✅ `hash`
  - `rar` → `qr_png` ✅ `qr`
  - `rar` → `sha` ✅ `hash`

#### `seven_z`（.7z） - ❌ 暂不支持

- **直转**：
  - `seven_z` → `base64` ✅ `hash`
  - `seven_z` → `crc` ✅ `hash`
  - `seven_z` → `identicon_png` ✅ `identicon`
  - `seven_z` → `md5` ✅ `hash`
  - `seven_z` → `qr_png` ✅ `qr`
  - `seven_z` → `sha` ✅ `hash`

#### `tar_gz`（.tar.gz） - ✅ 可读

- **直转**：
  - `tar_gz` → `base64` ✅ `hash`
  - `tar_gz` → `crc` ✅ `hash`
  - `tar_gz` → `identicon_png` ✅ `identicon`
  - `tar_gz` → `md5` ✅ `hash`
  - `tar_gz` → `qr_png` ✅ `qr`
  - `tar_gz` → `sha` ✅ `hash`
  - `tar_gz` → `zip` ✅ `archive`
- **多跳**（最多 2 跳）：
  - `tar_gz` → `mcpack` ✅ tar_gz --[archive]--> zip --[minecraft]--> mcpack
  - `tar_gz` → `mcpack_java` ✅ tar_gz --[archive]--> zip --[minecraft]--> mcpack_java
  - `tar_gz` → `mcworld` ✅ tar_gz --[archive]--> zip --[minecraft]--> mcworld
  - `tar_gz` → `mcworld_java` ✅ tar_gz --[archive]--> zip --[minecraft]--> mcworld_java

### 我的世界专区（minecraft）


#### `mcworld`（.mcworld） - ✅ 可读

- **直转**：
  - `mcworld` → `base64` ✅ `hash`
  - `mcworld` → `crc` ✅ `hash`
  - `mcworld` → `identicon_png` ✅ `identicon`
  - `mcworld` → `mcpack` ✅ `minecraft`
  - `mcworld` → `mcpack_java` ✅ `minecraft`
  - `mcworld` → `mcworld_java` ✅ `minecraft`
  - `mcworld` → `md5` ✅ `hash`
  - `mcworld` → `qr_png` ✅ `qr`
  - `mcworld` → `sha` ✅ `hash`

#### `mcpack`（.mcpack） - ✅ 可读

- **直转**：
  - `mcpack` → `base64` ✅ `hash`
  - `mcpack` → `crc` ✅ `hash`
  - `mcpack` → `identicon_png` ✅ `identicon`
  - `mcpack` → `mcpack_java` ✅ `minecraft`
  - `mcpack` → `mcworld` ✅ `minecraft`
  - `mcpack` → `mcworld_java` ✅ `minecraft`
  - `mcpack` → `md5` ✅ `hash`
  - `mcpack` → `qr_png` ✅ `qr`
  - `mcpack` → `sha` ✅ `hash`

#### `mcworld_java`（.mcworld） - ✅ 可读

- **直转**：
  - `mcworld_java` → `base64` ✅ `hash`
  - `mcworld_java` → `crc` ✅ `hash`
  - `mcworld_java` → `identicon_png` ✅ `identicon`
  - `mcworld_java` → `mcpack` ✅ `minecraft`
  - `mcworld_java` → `mcpack_java` ✅ `minecraft`
  - `mcworld_java` → `mcworld` ✅ `minecraft`
  - `mcworld_java` → `md5` ✅ `hash`
  - `mcworld_java` → `qr_png` ✅ `qr`
  - `mcworld_java` → `sha` ✅ `hash`

#### `mcpack_java`（.mcpack） - ✅ 可读

- **直转**：
  - `mcpack_java` → `base64` ✅ `hash`
  - `mcpack_java` → `crc` ✅ `hash`
  - `mcpack_java` → `identicon_png` ✅ `identicon`
  - `mcpack_java` → `mcpack` ✅ `minecraft`
  - `mcpack_java` → `mcworld` ✅ `minecraft`
  - `mcpack_java` → `mcworld_java` ✅ `minecraft`
  - `mcpack_java` → `md5` ✅ `hash`
  - `mcpack_java` → `qr_png` ✅ `qr`
  - `mcpack_java` → `sha` ✅ `hash`

## 3. 引擎清单与算法

| 引擎 id | 读 | 写 | 算法要点 |
| --- | --- | --- | --- |
| `hash` | 任意文件 | md5/sha/crc/base64 | crypto 摘要 / CRC32 / base64 文本 |
| `subtitle` | srt/ass/vtt/lrc | 同左 | 字幕 IR（起止时间+文本）互转 |
| `playlist` | m3u/m3u8/cue | 同左 | 曲目 IR 互转（CUE 用累计时长换算 INDEX） |
| `gps` | gpx/kml/tcx/geojson | 同左 | 轨迹点 IR 互转 |
| `color` | ase/aco/gpl/json | 同左 | ASE(u16/f32/UTF-16BE)、ACO(Lab→sRGB)、GPL 解析与写出 |
| `table` | csv/json/xml/xlsx | csv/json/xml/xlsx | 与 spreadsheet 同一套表格 IR，按目标格式选择写出器 |
| `text` | txt/md/html | txt/md/html | 纯文本 HTML/Markdown 互转（内置 stripHtml / htmlToMarkdown） |
| `document` | docx/rtf/txt/html/md | docx/rtf/txt/md/html | OOXML 段落与表格解析、RTF 控制字扫描；写出最简 OOXML/RTF |
| `spreadsheet` | xlsx/csv/json/xml | xlsx/csv/json/xml | 表格 IR（表头+行）互转；xlsx 走 OOXML inlineStr |
| `ebook` | epub | txt/md/html/epub | 按 container.xml/opf spine 顺序抽正文；写出 EPUB3 |
| `pdf` | png/jpg/txt/md/html/pdf | pdf/txt | 图片/文本 → PDF（pdf 包排版，含中文字体探测）；PDF → 文本（解压内容流 + Tj/TJ 提取） |
| `image` | jpg/png/webp/gif/bmp/tiff/ico/psd/tga/pvr/exr | jpg/png/webp/gif/bmp/tiff/ico/tga | 纯 Dart 解码 + 缩放 + 编码；jpg/bmp 输出时 alpha 铺白底 |
| `texture` | dds/ktx/tga | png/jpg/webp/bmp/tga/dds | 解析 DDS(BC1/BC2/BC3)、KTX(DXT1/DXT3/DXT5/RGBA8/RGB8) 并软件解码；可写出未压缩 BGRA8 DDS |
| `svg_vector` | 任意位图 | svg | 位图矢量描摹（轮廓/色块简化） |
| `image_palette` | 任意图片 | ase/aco/gpl/json | 量化取主色后写调色板 |
| `palette_image` | ase/aco/gpl/json | png | 调色板 → 色卡 PNG（可设列数/格子尺寸） |
| `image_doc` | 任意图片 | docx | DrawingML 内嵌 PNG（EMU = px×9525） |
| `ascii_art` | 图片 | ascii_art/braille_art | 亮度映射字符；盲文用 2×4 点阵编码 |
| `qr` | 任意文件 | qr_png | 纯 Dart QR 编码（字节模式、版本 1–10、L/M/Q/H、8 种掩码罚分择优） |
| `identicon` | 任意文件 | identicon_png | md5 → 5×5 对称图案 + HSL 配色 |
| `render3d` | obj/stl/ply/off/gltf/glb | png/jpg | 软件光栅化（正交投影 + z-buffer + Lambert） |
| `mesh_geo` | obj/stl/ply/off/gltf/glb | geojson | 单调链凸包 → Polygon + 质心 Point |
| `geo_render` | gpx/kml/tcx/geojson | svg/png | 经纬度正交投影绘制轨迹线 |
| `embroidery` | dst/pes/jef/png/jpg | dst/pes/jef/png | 绣花针迹 IR 互转；位图按阈值描边成针迹 |
| `archive` | zip/tar/tar.gz/gz | 同左 | archive 包 Zip/Tar/GZip 编解码；rar/7z 暂不支持 |
| `minecraft` | mcworld/mcpack(_java)/zip | 同左 | 资源包/行为包目录重排 + manifest.json |
| `ffmpeg` | mp3/wav/flac/aac/m4a/ogg/mp4/mkv/mov/avi/webm/flv | 同左 + gif/srt/png/jpg | FFmpegKitNext 原生库（无命令行）：转码/抽帧/抽字幕/波形视频 |
| `slides` | pptx/odp | txt/md/html/pdf | 按 presentation.xml sldIdLst 真实页序取文本与图片 |
| `font` | ttf/otf/woff | ttf/otf/woff | sfnt 表目录重建 + WOFF1 zlib 表 + checksum 重算（无损）；woff2 暂不支持 |
| `audio_midi` | wav 等（经 FFmpeg 解码） | midi | 基频自相关提取 → 音符/时值 |
| `spectrogram` | 音频（经 FFmpeg 解码） | png/jpg | 汉宁窗 + radix-2 FFT 绘制时频图 |

> 未列出的 `model3d` / `mesh` 引擎：obj/stl/ply/off/gltf/glb 之间互转（glTF 走 JSON/GLB 容器，
> 采用自写 `lib/engine/engines/mesh_io.dart` 解析与写出）。

## 4. 暂不支持 / 暂不可达的部分

所有转换能力都随安装包内置：纯 Dart 算法引擎 + 编译进包的 FFmpegKitNext 原生库，
不存在外置安装插件的路径。下表里的格式仅仅是因为缺少内置解码器/模型而暂未接入。

| 格式 | 原因 |
| --- | --- |
| `heic` | 需要额外的内置解码器/模型，当前版本暂不支持 |
| `hdr` | 需要额外的内置解码器/模型，当前版本暂不支持 |
| `exr` | 需要额外的内置解码器/模型，当前版本暂不支持 |
| `ncm` | 需要额外的内置解码器/模型，当前版本暂不支持 |
| `kgm` | 需要额外的内置解码器/模型，当前版本暂不支持 |
| `qmc` | 需要额外的内置解码器/模型，当前版本暂不支持 |
| `mobi` | 需要额外的内置解码器/模型，当前版本暂不支持 |
| `azw3` | 需要额外的内置解码器/模型，当前版本暂不支持 |
| `woff2` | 需要额外的内置解码器/模型，当前版本暂不支持 |
| `ufo` | 需要额外的内置解码器/模型，当前版本暂不支持 |
| `fbx` | 需要额外的内置解码器/模型，当前版本暂不支持 |
| `astc` | 需要额外的内置解码器/模型，当前版本暂不支持 |
| `xnb` | 需要额外的内置解码器/模型，当前版本暂不支持 |
| `rar` | 需要额外的内置解码器/模型，当前版本暂不支持 |
| `seven_z` | 需要额外的内置解码器/模型，当前版本暂不支持 |

- 不可达：`heic`、`hdr`、`exr`、`ncm`、`kgm`、`qmc`、`mobi`、`azw3`、`woff2`、`ufo`、`fbx`、`astc`、`xnb`、`rar`、`seven_z`

