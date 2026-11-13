# PATCH_MANIFEST — OmniForge 增量包（v0.5.4）

> 给接手的 AI：这是**增量包**，不是完整工程。按「怎么用」覆盖到对应基线即可，不要单独构建它。

## 一、这个包是什么

- 工程：OmniForge（Flutter 跨平台文件转换器，`com.file.omniforge.app`）
- **增量基线：commit `e8dcc42`（v0.5.3）**
- 内容：基线 → 当前状态的全部差异（新增 18 个文件 + 修改 39 个文件，**无删除**）
- 生成时间：2026-11-13

## 二、怎么用

1. 拿到基线：`git clone` 后 `git checkout e8dcc42`。
2. 把本包解压**覆盖**到工程根目录（结构与工程一致，同名直接覆盖）。
3. `flutter pub get` → `flutter analyze`（期望 0 error）→ `flutter build apk --release --split-per-abi`。
4. 覆盖后 `ios/Flutter/ephemeral`、`*/generated_plugin_registrant`、`.flutter-plugins-dependencies` 之类的差异属正常，由 `flutter pub get` 重新生成。

## 三、本轮修了什么

### 1. 点「打开」时弹「允许访问照片和视频」——已消除

**现象**：Android 13+/14 上点结果的「打开」，系统弹「允许 OmniForge 访问照片和视频？」。

**根因**（不是我们代码申请，是插件行为）：
- 输出在公共目录 `/storage/emulated/0/OmniForge/…`；
- `open_filex` 的 Android 实现 `OpenFilePlugin.java` 里 `pathRequiresPermission()` 判断文件是否在应用沙箱内，公共目录 → 判定为「需要权限」；
- SDK ≥ 33 且 MIME 以 `image` 开头（PNG/JPG 都算）→ 调 `requestPermission(READ_MEDIA_IMAGES)`，弹的就是这个框；
- 但它最终是通过 FileProvider 授出 `content://` + `FLAG_GRANT_READ_URI_PERMISSION` 给目标应用，**这个读权限对它自己毫无必要**。

**改法**（`lib/features/home/home_page.dart`）：新增 `_openablePath()`，Android 上先把文件复制到应用缓存（`getTemporaryDirectory()/open/`）再交给 `OpenFilex.open()`。路径落在沙箱内 → 插件直接 `startActivity()`，不再申请任何权限。
- 非 Android 平台原样返回，不复制；
- 每次打开前清空上一份缓存副本；
- 复制失败（极端情况）回退原路径，保证仍能打开。

**副作用**：`打开` 会额外占一份临时副本（下次打开时清掉）。若以后想彻底避免复制，正解是换掉 `open_filex` 或自建 Intent 通道，**不要**去申请那个权限。

### 2. 桌面图标与设置页预览「不吻合」——已统一

**根因**：
- 三张图标素材是**白底不透明 PNG**，白边比例还不一致（默认 10%、铁砧 18%、火焰 17.6%）；
- 工程只有 legacy `mipmap-*.png`，**没有 `mipmap-anydpi-v26` 自适应图标**；
- 桌面拿到 legacy 方形图 → 系统加白色圆角底板并缩到安全区（图形变小、白板变厚）；
- 设置页预览走 `BoxFit.cover` + `ClipRRect` → 白边被裁掉（图形更大）。
- 同一张图两套渲染，于是不一致。

**改法**：
- 新增 `mipmap-anydpi-v26/ic_launcher{,_anvil,_flame}.xml`：白底 + 前景层图形，图形占**可见区 86%**（三套统一）；
- 各密度新增 `ic_launcher*_fg.png`（108dp 画布，透明底）；
- legacy `mipmap-*.png`（48dp）重做为「白底 + 图形 86%」，与预览同比例；
- `assets/icons/*.png` 同步重做，设置页预览与桌面完全同源；
- `AndroidManifest.xml` 为 application 与三个 `activity-alias` 补 `android:roundIcon`；
- iOS 主图标（19 个尺寸）与备选 `IconAnvil/IconFlame@2x/3x` 用同一套素材重写，避免两端观感不一致。

> 想改图标比例只改一个数：`gen_icons.py` 里的 `ART_RATIO_VISIBLE`（当前 0.86），重跑即可同时更新预览图、legacy mipmap、自适应前景与 iOS 图标。

### 3. Android Gradle 配置

本包的 `android/build.gradle`、`android/gradle.properties`、`.github/workflows/build.yml` **与基线 e8dcc42 完全一致**（基线已含 `plugins.withId` + JavaCompile JVM 17 + `kotlin.jvm.target.validation.mode=warning` + Windows 长路径的修复），本轮未改动。

## 四、验证记录

- `flutter pub get`：Got dependencies（依赖未变）
- `flutter analyze`：0 error（8 条 warning/info）
- `flutter build bundle`：通过
- manifest XML 结构校验：application 1 个、3 个 alias 的 icon/roundIcon 均有效
- 图标尺寸核对：legacy 48/72/96/144/192；自适应前景 108/162/216/324/432
- **未验证**：真机/模拟器上的实际桌面渲染（需打包安装）；iOS 图标在 Xcode 资源目录中的显示

## 五、注意

- 不要为了「省一次复制」去给应用加 `READ_MEDIA_*` 运行时申请——那正是要消除的弹窗。
- `READ_MEDIA_IMAGES/VIDEO/AUDIO` 仍会被 `open_filex` 的 manifest 合并进来，属预期；我们的代码不申请它们。
- 自适应图标生效后，桌面上图形的大小由 `ic_launcher*_fg.png` 决定；要调大小只改前景层，别退回纯 legacy 图标。
