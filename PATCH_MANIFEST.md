# PATCH_MANIFEST — OmniForge 增量包（v0.6.0 · 格式体系空壳）

> 给接手的 AI：这是**增量包**，不是完整工程。按「怎么用」覆盖到对应基线即可，不要单独构建它。

## 一、这个包是什么

- 工程：OmniForge（Flutter 跨平台文件转换器，`com.file.omniforge.app`）
- **增量基线：commit `e8dcc42`（v0.5.3）**
- 内容：基线 → 当前状态的全部差异
- 生成时间：2026-11-13
- 本轮主题：**把 19 大类格式体系一次性铺满，先做空壳**（`stage: shell`），转换引擎仍未接入

## 二、怎么用

1. 拿到基线：`git clone` 后 `git checkout e8dcc42`。
2. 把本包解压**覆盖**到工程根目录（结构与工程一致，同名直接覆盖）。
3. `flutter pub get` → `flutter analyze`（期望 0 error）→ `flutter build apk --release --split-per-abi`。
4. 覆盖后 `ios/Flutter/ephemeral`、`*/generated_plugin_registrant`、`.flutter-plugins-dependencies` 等差异属正常，由 `flutter pub get` 重新生成。

## 三、这轮改了什么

### 1. `assets/formats.yaml` 全量重写

- 新增 `stage: shell` 标记：格式/类型已全量登记，引擎未接入。
- 新增 `categories:` 段：19 类（`key` / 中文名 `name` / 图标名 `icon` / `order`），UI 的类型下拉直接由它生成。
- 格式从 88 条重排为**19 类 88 种**，每条都补齐：
  - `categories:`（复数）——支持**跨类共享**：`pdf` = 文档/电子书/幻灯片，`txt` = 文档/电子书，`json` = 表格/调色板；
  - `extensions:` 全量别名（`.jpeg/.jpe/.jfif`、`.tif`、`.heif`、`.oga/.opus`、`.mid`、`.doc`、`.ppt`、`.xls`、`.woff`、`.ssa`、`.ktx2`、`.tgz`、`.qmc0/.qmc3/.qmcflac`、`.kgma` 等）；
  - `accepts_from:` 按类铺满（同类别内互转全部可达；`gif` 接受视频、`mp3/wav` 接受视频、纹理与图像互转、`mcworld_java/mcpack_java` 兼容压缩包、哈希类写 `"*"` 表示任意输入）；
  - `status: planned`（空壳标记）+ 可选 `note`（如「本质是 zip」「接受任意文件输入」）。
- `flows:` 从 6 条扩到 **25 条**：原有语义链路保留，另加每类内部互通链路。
- 修掉一个历史 bug：`id: off` 在 YAML 1.1 里会被解析成布尔 `false`，导致 OFF 网格的 id 一直是空字符串。现在所有 id 都加了引号。

### 2. 数据层

- `lib/models/format_node.dart`：`FormatNode` 增加 `categories`（多分类）、`status`、`note`，保留 `category` getter 兼容旧代码；新增 `FormatCategory`（key/name/icon/order）。
- `lib/registry/registry_manager.dart`：加载 `categories` 与 `stage`；新增 `getCategories()` / `getCategory()` / `getFormatByExtension()` / `isShellStage`；`getFormatsByCategory` 改为按多分类匹配；`initialize()` 幂等。
- **新增** `lib/registry/format_catalog.dart`：把注册表转成 UI 目录
  - `FormatOption`（label / value / ext / category / extensions / planned / note）；
  - `FormatCatalog`（19 类类型表 + 分类→格式表，`typeOf` / `formatsOf` / `formatByExt` / `uniqueFormatCount`）；
  - `formatCatalogProvider`（Riverpod Provider）；
  - `categoryIcon()` 19 类图标映射。

### 3. UI

- `lib/features/home/home_provider.dart`：**删掉写死的 7 条类型表 / 5 条格式表**（原来只有 image/audio/video/document/archive + 两个 MC 类型，跟注册表完全脱节），`FormatOption` 改为从 `format_catalog.dart` 转出。
- `lib/features/home/config_page.dart`：输入/输出类型与格式全部改从 `formatCatalogProvider` 取；自动识别改为按**扩展名别名**反查（`tif→tiff`、`jpeg→jpg`、`tar.gz→tar_gz` 都能命中）；输出改用 `FormatOption.ext`（多段扩展名如 `tar.gz` 正确）；底部弹窗改成可滚动（19 类 + 11 格式不再挤在一起）；底部加一行空壳提示「已登记 19 类 / 88 种格式，转换引擎尚未接入」。
- `lib/utils/file_type_detector.dart`：类型键从 7 个（含 `mc_bedrock/mc_java`）改为与 yaml 一致的 **19 个分类键**；补全全部扩展名映射（含 `.jfif/.dib/.wave/.opus/.kgma/.qmc*/prc/.azw/markdown/.htm/.tsv/.ufo/.ktx2/.ssa/.geojson/.b64/...`）；新增复合扩展名处理（`.tar.gz` / `.tar.bz2` / `.tar.xz` / `.geo.json`）；ZIP 分支里 MC 判断改为判 `minecraft`。
- `lib/router/conversion_router.dart`：`accepts_from` 支持 `"*"` 通配（原来哈希类写 `"*"` 却永远匹配不到，等于死数据）；分类匹配改用 `categories.contains`。
- `lib/main.dart`：启动先 `WidgetsFlutterBinding.ensureInitialized()` + `await RegistryManager().initialize()`，再 `runApp`。

### 4. 自检脚本

- 新增 `tool/check_formats.dart`：`dart run tool/check_formats.dart` 校验 yaml 结构（空 id、无分类、分类不存在、无扩展名、扩展名缺前缀、无 status、空分类），并打印每类格式数。

## 四、验证记录

- `dart run tool/check_formats.dart`：19 类 / 88 种格式 / 25 条 flow，结构自检全部通过（图像 11、音频 10、视频 6、电子书 5、文档 6、幻灯片 3、表格 4、字体 4、调色板 4、3D 6、纹理 5、网格 2、哈希 4、绣花 3、GPS 4、字幕 4、播放列表 3、压缩包 4、MC 4）
- `flutter analyze`：0 error
- `flutter build bundle`：通过，`build/flutter_assets/assets/formats.yaml` 已打入（22.7 KB）
- **未验证**：真机上的下拉渲染与识别预填（需打包安装）；`flutter test` 未跑

## 五、注意 / 下一轮

- 现在所有格式的 `status` 都是 `planned`，转换仍走 `home_provider` 里**模拟进度**的老路径（不会真的转码）。接引擎时按 `engines` 字段挂对应 `IEngine`，把 `status` 改成 `ready`，UI 的空壳提示会自动消失（`isShellStage` 读 `stage`，届时改成 `ready` 或删掉该行）。
- 同一格式在多个分类下会重复出现（pdf/txt/json），这是**有意**的：分类是展示维度，`id` 仍是唯一键。
- 新增分类时只改 `assets/formats.yaml` + `file_type_detector.dart` 的 `_extType/_typeLabels` + `format_catalog.dart` 的图标表，三处即可，不要再往回加写死的 UI 表。
