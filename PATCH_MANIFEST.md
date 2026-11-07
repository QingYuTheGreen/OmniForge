# PATCH_MANIFEST — OmniForge 增量包（v0.5.0）

> 给接手的 AI：这是**增量包**，不是完整工程。请严格按「怎么用」执行，不要试图单独构建它。

## 一、这个包是什么

- 工程：OmniForge（Flutter 跨平台文件转换器，包名 `com.file.omniforge.app`）
- 增量基线：GitHub `QingYuTheGreen/OmniForge` main 分支 **commit `265b4c6`**（Release v0.2.1）
- 本包内容：基线 → 当前状态的**全部差异文件**（新增 + 修改），**没有任何删除**（基线里没有被移除的文件）
- 生成时间：2026-11-08

## 二、怎么用（唯一正确用法）

1. 拿到 `265b4c6` 的完整工程（`git clone` 后 `git checkout 265b4c6`），得到目录 `file_converter/`。
2. 把本增量包解压**覆盖**到该工程根目录（同名文件直接覆盖，包内目录结构与工程一致）。
3. 本地/CI 依次执行：
   ```
   flutter pub get      # 必须，会重算 lock 并生成插件注册代码
   flutter analyze      # 期望：0 error（8 条 warning/info 可忽略）
   flutter build apk --release --split-per-abi   # 或照 CI 走全平台
   ```
4. **不要**跳过 `flutter pub get`；包里的 `pubspec.lock` 已锁死 git 依赖的 commit，直接用它可复现同一套依赖。
5. 覆盖后若出现 `.flutter-plugins-dependencies`、`ios/Flutter/ephemeral`、`*/generated_plugin_registrant` 之类的差异，属正常——它们由 `flutter pub get` 重新生成。

## 三、本轮改了什么（按重要性）

### 1. 依赖层：4 个插件换成 CPF-Flutter 官方 OpenHarmony 适配版（git 依赖）

`pubspec.yaml`：

| 插件 | 版本 | git 地址 / 分支 |
|---|---|---|
| path_provider | 2.1.5 | `gitcode.com/CPF-Flutter/flutter_packages.git`，path `packages/path_provider/path_provider`，ref `br_path_provider-v2.1.5_ohos` |
| file_picker | 8.0.7 | `gitcode.com/CPF-Flutter/fluttertpc_file_picker.git`，ref `br_v8.0.7_ohos` |
| open_filex | 4.5.0 | `gitcode.com/CPF-Flutter/fluttertpc_open_filex.git`，ref `br_v4.5.0_ohos` |
| share_plus | 10.1.1 | `gitcode.com/CPF-Flutter/flutter_plus_plugins.git`，path `packages/share_plus/share_plus`，ref `br_share_plus-v10.1.1_ohos` |

- `environment.sdk` 从 `>=3.3.0` 提到 **`>=3.6.0`**（path_provider 适配版要求 `^3.6.0` / Flutter `>=3.27.0`）。
- `receive_sharing_intent` 钉死为 **`1.8.1`**（原来是 `^1.8.1`，会漂到 1.9.0；该包只服务 Android/iOS，本轮不动它）。

### 2. 依赖冲突：两条 `dependency_overrides`（**这两条是修复 CI 的关键，别删**）

```yaml
dependency_overrides:
  path_provider:   # git CPF-Flutter/flutter_packages, path packages/path_provider/path_provider, ref br_path_provider-v2.1.5_ohos
  web: ^1.1.0
```

- **web**：share_plus 10.1.1 间接依赖 `url_launcher_web`，要 `web ^1.x`；而 file_picker 8.0.7 要 `web ^0.5.1`，pub 版本求解直接失败——就是 CI 里那条
  `Because every version of share_plus from git depends on web ^1.0.0 and every version of file_picker from git depends on web ^0.5.1 ... version solving failed`。
  本项目 CI **不出 web 产物**（只出 apk / windows / macos / linux / ios / hap），`web` 包不参与任何实际编译，所以统一覆盖到 1.x（实际解析 `web 1.1.2 (overridden)`）。
- **path_provider**：share_plus 的 `share_plus_platform_interface` 把 path_provider 钉在 `openharmony-sig/flutter_packages` 的 `master`，与我们声明的 CPF-Flutter 分支**同名包不同 git 源**，pub 同样会判冲突；这里强制统一到我们这条 `br_path_provider-v2.1.5_ohos`。
  （这个是修掉 web 冲突后必然撞上的第二个坑，已一并处理。）

### 3. Dart 层

- `lib/features/home/home_page.dart`：分享走 **`Share.shareXFiles([XFile(path)], text: file.name)`**。
  ⚠️ 适配版 share_plus **10.1.1 的 API 仍是老的 `Share` 静态方法**，**没有** `SharePlus.instance` / `ShareParams` / `SharedFile`（那是上游 v11+ 才引入的）。不要"顺手升级"成新 API，会编译不过。
- `lib/utils/file_type_detector.dart`：修掉 2 个**编译级错误**（基线没有此文件，是本轮新增的）：
  - `File(path).open(0)` → `File(path).open()`（`open` 只收命名参数 `mode`）
  - `_r(mcType, ext, ext)` → `_r(mcType!, ext, ext)`（`Map<String, String>[]` 返回 `String?`）
- `lib/main.dart`：去掉 ohos 分支、`_initOhosIncoming`、`ohos_platform` 导入、`dart:io` 导入。
- `lib/utils/output_paths.dart`：去掉 ohos 特判，统一走 path_provider。

### 4. 鸿蒙端：彻底砍掉「接收外部分享 / 用其他应用打开」

**原因**：CPF 的 `fluttertpc_receive_sharing_intent` 官方明确不做「复制到缓存再返回路径」（Issue #12，2026-09-24 结论：权限边界收敛 + 大文件复制与缓存生命周期不属插件职责）→ Flutter 层拿到的临时 URI 无法读写，能力等于不存在。且通过分享输入文件本就是扩展功能。

- 删除 `ohos/entry/src/main/ets/plugins/`（`OmniForgeChannel.ets` 及整个目录）
- 删除 `lib/utils/ohos_platform.dart`
- `ohos/entry/src/main/ets/entryability/EntryAbility.ets` 回到默认 `FlutterAbility`（仅 `configureFlutterEngine` + `GeneratedPluginRegistrant.registerWith`）
- `ohos/entry/src/main/module.json5` 去掉 `ohos.want.action.sendData` / `ohos.want.action.viewData`，只留 home launcher + INTERNET 权限
- 结果：鸿蒙只保留 **选文件 / 输出目录 / 分享 / 打开** 四个能力，全部由上面 4 个适配版插件承担，**零自建 MethodChannel**

### 5. 未换的插件（有意为之）

`device_info_plus`、`permission_handler`（仅 Android 用，跨大版本迁移对鸿蒙零收益、有 Android 回归风险）、`dynamic_color`、`window_manager`、`dynamic_app_icon_changer`、`flutter_riverpod`、`yaml`、`cupertino_icons` 全部保持 pub 版本。

## 四、本次验证记录（本机实跑，Flutter 3.47.9 / Dart 3.13.7，与 CI 同版本）

- `flutter pub get`：**Got dependencies!**（73 个依赖变更；`share_plus 10.1.1 from git`、`path_provider_ohos 2.2.17 from git`、`web 1.1.2 (overridden)`）
- `flutter analyze`：**0 error**，8 条 warning/info
- `flutter build bundle`：通过
- 4 个插件在 pub cache 里的 `ohos/` 目录（`build-profile.json5` / `hvigorfile.ts` / `index.ets` / `oh-package.json5`）均已确认存在
- **未验证**：鸿蒙 HAP 实际构建（需要 CPF Flutter SDK + hvigor，本机不具备），交由 CI 验证

## 五、已知坑

- CI 的 `flutter pub get` 需要能访问 `gitcode.com`（4 条 git 依赖）。若网络抖动，重试即可；`pubspec.lock` 已锁 commit，不会解析到别的版本。
- 鸿蒙构建用的是 CPF 的 `flutter_flutter` 分支（`oh-3.44.9-release` 一类）。历史做法：clone 后需 `git tag 3.44.9` 并删 `bin/cache/flutter.version.json`，否则版本会被识别成 `0.0.0-unknown`。
- 不要恢复 ohos 侧的 `sendData` / `viewData` skill，也不要重新引入 `ohos_platform.dart`——该能力已被弃用。
- `file_picker` 的 `br_v10.3.8_ohos` 分支不要用：它把包名改成了 `file_picker_ohos`（import 全要改），且依赖 `win32 ^5.9.0` 会牵动桌面端。`br_v10.2.0_ohos` 更不要用：没声明 ohos 平台，鸿蒙上等于没插件。
