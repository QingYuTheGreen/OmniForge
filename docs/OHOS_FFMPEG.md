# OpenHarmony（ohos）FFmpeg 原生库接入方案

本文记录 OmniForge 在鸿蒙（OpenHarmony / HarmonyOS NEXT）上补齐音视频转换能力的设计、
通道契约、构建步骤、许可义务与已知风险。

一句话：**鸿蒙侧不启动任何命令行进程**，而是通过 ohpm 包 `@ohos/ffmpeg-kit`
（FFmpegKit 的 OpenHarmony 移植，预编译 `libffmpegkit_napi.so`，内含 libav* 全套）
由 ArkTS 通过 NAPI 调用原生库；Dart 通过 MethodChannel 与 ArkTS 桥接通信。

## 1. 背景与目标

- Flutter 侧现有音视频能力由 `ffmpeg_kit_flutter_new_full`（ pub 插件）提供，见
  `lib/engine/ffmpeg_kit_backend.dart`；其原生产物**不包含 OpenHarmony**。
- 桌面/移动端继续使用该插件；只有 `Platform.operatingSystem == 'ohos'` 时切换到本方案。
- 硬约束：不得 `Process.run` / 不得调用 shell / 不得依赖系统 `ffmpeg` 可执行文件。
  本方案的每一次转码都是 `ffmpegSession(...)` + 原生 ThreadPool 执行，属库调用。
- 上游 FFmpegKit（arthenica/ffmpeg-kit）及其后继（arthenica/ffmpeg-kit-next）已不再
  发布 pub / Maven / CocoaPods 产物，且官方平台列表中没有 OHOS；鸿蒙能力由社区移植
  `CPF-ApplicationTPC/ohos_ffmpeg_kit` 提供。

## 2. 选型与上游来源

| 项 | 值 |
| --- | --- |
| ohpm 包 | `@ohos/ffmpeg-kit` |
| 版本 | `1.0.1`（har，`byteCodeHar: true`，`compatibleSdkVersion 12`） |
| 源码仓库 | https://gitcode.com/CPF-ApplicationTPC/ohos_ffmpeg_kit |
| 原生库 | `libs/arm64-v8a/libffmpegkit_napi.so`（另含 `libc++_shared.so`、`libomp.so`、`libomptarget.so`） |
| 实现方式 | C++ 实现 + NAPI 绑定；ArkTS 侧是函数式 API（非对象式 `FFmpegKit` 类） |
| 移植层许可 | 仓库 ADR/README 标注 MIT；har `oh-package.json5` 的 `license` 字段为 `LGPL-3.0`（见 §8） |
| 内含 FFmpeg | LGPL v3（与现有 `ffmpeg_kit_flutter_new_full` 一致） |
| 已验证环境（上游 README） | DevEco Studio 6.0.0 Release、SDK API20、ROM 6.0.0.130 |

> 注意：任务背景里过时的示例 `FFmpegKit.executeAsync(command, ...)` / `ReturnCode.isSuccess` /
> `FFprobeKit.getMediaInformation(path)` 在 1.0.1 包中**不存在**。真实 API 以上游 har 的
> `index.d.ets` 与 `*.d.ets` 声明为准，本桥接按真实签名实现（见 §5）。

## 3. 架构与调用链

```
FfmpegEngine (lib/engine/engines/ffmpeg_engine.dart)
        │  convert(args)
        ▼
FfmpegBackend  (抽象接口 lib/engine/engines/ffmpeg_backend.dart)
        │  createPlatformFfmpegBackend()   ← lib/engine/ffmpeg_backend_factory.dart
        ├── ohos   → FfmpegOhosBackend        (lib/engine/ffmpeg_ohos_backend.dart)
        └── 其它平台 → FfmpegKitBackend        (lib/engine/ffmpeg_kit_backend.dart)
                             │
        ┌────────────────────┘  MethodChannel('omniforge/ffmpeg')
        ▼
FFmpegBridge.ets (ohos/entry/src/main/ets/plugins/FFmpegBridge.ets)
        │  函数式 NAPI：ffmpegSession / asyncFFmpegSessionExecute /
        │  enableStatisticsCallback / enableFFmpegSessionCompleteCallback / cancelSession
        ▼
libffmpegkit_napi.so → FFmpegKit 移植层 → libav*（解封装/解码/编码/封装）
```

注册链路：`EntryAbility.configureFlutterEngine` 中 `GeneratedPluginRegistrant.registerWith()`
之后调用 `FFmpegBridge.register(flutterEngine)`，内部
`engine.getPlugins()?.add(new FFmpegBridge())`（与 Flutter-ohos 生成代码同一写法）。

## 4. 通道契约（MethodChannel `omniforge/ffmpeg`）

### 4.1 Dart → ArkTS

| 方法 | 参数 | 返回 | 说明 |
| --- | --- | --- | --- |
| `execute` | `{command: String, arguments: List<String>, durationMs?: int}` | `int` sessionId | `arguments` 为不含 `ffmpeg` 前缀的完整参数数组（调用方已拼好）；`command` 是同一参数的空格拼接版本，便于日志/兼容。`durationMs > 0` 时 ArkTS 用它将统计时间换算成百分比。 |
| `cancel` | `{sessionId: int}` | `null` | 底层 `cancelSession(sessionId)`，返回码随后为 `255`。 |
| `probeDuration` | `{path: String}` | `int` 毫秒 | 无法解析 / 路径为空 / 原生异常时返回 `0`（Dart 侧 `<=0` 归一为 `null`）。 |

错误（`result.error`）：

| code | 场景 |
| --- | --- |
| `INVALID_ARGUMENTS` | 参数为空、缺 sessionId |
| `NATIVE_ERROR` | 创建会话、启动执行、取消、ffprobe 等原生调用抛异常 |
| `plugin_missing` | 由 Dart 侧 `MissingPluginException` 归一，表示原生库未集成 |
| 未实现通道 | `result.notImplemented()` → Dart `MissingPluginException` |

### 4.2 ArkTS → Dart（`channel.invokeMethod`）

| 回调 | 参数 | 时机 |
| --- | --- | --- |
| `progress` | `{sessionId: int, percent: double}` | 每次 statistics 回调；`percent = time(ms) * 100 / durationMs`，夹取 0..100。无时长信息时不发。 |
| `log` | `{sessionId: int, message: String}` | 会话结束时回传日志**末尾一条**非空行（最长 500 字符），供 Dart 组装失败原因。 |
| `complete` | `{sessionId: int, code: int}` | 会话结束；`code` 取自 `abstractSessionGetReturnCode`：`0` 成功、`255` 取消、其它失败。 |

### 4.3 Dart 侧行为

- `FfmpegOhosBackend.execute`：先按 `-i <path>` 探测时长 → `invokeMethod('execute')` 拿 sessionId →
  `Completer` 等 `complete`。`code == 0` 正常返回；`code == 255` 或本地已发起取消 →
  抛 `FfmpegBackendCancelled`；其它 → 抛 `FfmpegBackendFailure(最后一条日志或 'FFmpeg 执行失败(code=X)')`。
- 回调按 `sessionId` 分发（`Map<int, _OhosFfmpegSession>`），支持同一后端并发多个任务。
- `cancelToken`：`CancelToken` 无 `addListener`，故每 200ms 轮询 `isCancelled`；命中后调用
  `cancel` 方法，并设 8 秒兜底（若原生不回 `complete` 则本地按取消收敛）。
- `probeDurationMs`：`invokeMethod<num>('probeDuration')`，`MissingPluginException` /
  `PlatformException` 一律返回 `null`（时长未知不阻塞转码）。
- 原生库缺失（`MissingPluginException` 或 `PlatformException(code: 'plugin_missing')`）→
  `FfmpegBackendUnavailable('鸿蒙 FFmpeg 原生库未集成（@ohos/ffmpeg-kit）')`。

## 5. ArkTS 侧真实 API 映射

`@ohos/ffmpeg-kit@1.0.1` 导出函数（节选，均来自 har `*.d.ets`）：

| 用途 | API |
| --- | --- |
| 创建 FFmpeg 会话 | `ffmpegSession(argumentsArray: Array<string>): Map<string, ESObject>`（含 `sessionId`） |
| 异步执行 | `asyncFFmpegSessionExecute(sessionId: number): void` |
| 同步执行（内部仍是 ThreadPool） | `ffmpegSessionExecute(sessionId, func: () => void): void` |
| 创建 ffprobe 会话 | `ffprobeSession(argumentsArray: Array<string>)` |
| 执行 ffprobe | `ffprobeSessionExecute(sessionId, func: () => void)` |
| 完成回调 | `enableFFmpegSessionCompleteCallback(func: (session: ESObject) => void)` |
| 统计回调 | `enableStatisticsCallback(func: (statistics: ESObject) => void)` |
| 返回码 | `abstractSessionGetReturnCode(sessionId): number`（-1 运行中/未知，0 成功，255 取消） |
| 日志 | `abstractSessionGetAllLogsAsString(sessionId, waitTimeout): string`（`waitTimeout <= 0` 表示不等待） |
| 取消 | `cancelSession(sessionId): void` |
| 全局日志通道 | `RegisterGlobalCallback(): void` |
| 类型辅助 | `SessionObject.propertyToMap(session)`、`StatisticsObject.PropertyToMap(stats)`；字段见 `SessionObject.d.ets` / `StatisticsObject.d.ets` |

实现要点（已在 `FFmpegBridge.ets` 中处理）：

1. **完成回调 payload 不含 returnCode**：原生 `SessionToValue` 只写
   `sessionId/command/createTime/startTime/type`，所以桥接在完成回调里再调
   `abstractSessionGetReturnCode(sessionId)`。
2. **1.0.1 未导出 `enableLogCallback`**：拿不到实时日志行，只能会话结束后
   `abstractSessionGetAllLogsAsString(sid, 0)` 读取，因此 `log` 回调在 `complete` 之前一次性发送。
3. **回调可能在非 UI 线程**：全局回调统一 `emitter.emit(...)`（`@kit.BasicServicesKit`）
   回主线程，再由事件处理器 `channel.invokeMethod` 回 Dart；`ffprobeSessionExecute` 的回调同理。
4. **时长探测不用 `mediaInformationSession`**（其参数语义/JSON 包装在 1.0.1 中不稳定），
   改用 ffprobe 标准参数：
   `-v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 -i <path>`，
   从日志中解析秒数并四舍五入为毫秒；另有 10 秒超时兜底（`pendingProbes` + `setTimeout`）。
   由于 ffprobe 的 `format=duration` 写在 stdout，桥接在初始化时调用
   `enableRedirection()`（同时隐含 `enableLogs()`/`enableStatistics()`）把标准输出并入
   session 日志；若该调用在目标 ROM 上无效，只会退化为"无进度"，不影响转码本身。
5. **sessionId 与生命周期**：`durationBySession` 维护执行中会话；detach 时取消全部会话并
   注销回调（用空实现覆盖回调，避免与包声明中非空函数类型冲突），`emitter.off` 解绑。

## 6. 文件清单

| 文件 | 状态 | 说明 |
| --- | --- | --- |
| `lib/engine/ffmpeg_ohos_backend.dart` | 新增 | Dart 侧后端实现（通道调用、并发会话表、取消轮询、错误归一） |
| `lib/engine/ffmpeg_backend_factory.dart` | 新增 | `createPlatformFfmpegBackend()`，ohos → `FfmpegOhosBackend`，其余 → `FfmpegKitBackend` |
| `ohos/entry/src/main/ets/plugins/FFmpegBridge.ets` | 新增 | ArkTS/NAPI 桥接，MethodChannel `omniforge/ffmpeg` |
| `ohos/entry/src/main/ets/entryability/EntryAbility.ets` | 修改 | `configureFlutterEngine` 中注册 `FFmpegBridge` |
| `ohos/entry/oh-package.json5` | 修改 | dependencies 增加 `"@ohos/ffmpeg-kit": "1.0.1"` |
| `docs/OHOS_FFMPEG.md` | 新增 | 本文档 |
| `THIRD_PARTY_NOTICES.md` | 新增/更新 | 追加 `@ohos/ffmpeg-kit` 的 MIT/LGPL 声明与源码地址 |

**主 agent 还需接线一行**：`lib/engine/engine_providers.dart` 中把
`EngineRegistry.platformDefaults(ffmpegBackend: FfmpegKitBackend())` 里的
`FfmpegKitBackend()` 换成 `createPlatformFfmpegBackend()`（并 import
`lib/engine/ffmpeg_backend_factory.dart`）。

## 7. 构建步骤

1. **安装 ohpm 依赖**（在 `ohos/` 目录下）：
   ```bash
   cd ohos && ohpm install
   ```
   需能访问 ohpm 仓库；`entry/oh-package.json5` 已声明 `@ohos/ffmpeg-kit: 1.0.1`。
   `ohos/oh-package.json5`（工程根）保持不声明该依赖——依赖由被导入的 entry 模块声明，
   以免与 Flutter-ohos 工具注入的依赖冲突。
2. **环境**：DevEco Studio 6.0.0 及以上 / SDK API20（上游 README 的已验证组合）；
   低于该版本可能因 `byteCodeHar` / API 差异无法编译。
3. **Flutter-ohos 构建**：
   ```bash
   flutter build hap --target-platform ohos-arm64   # 具体参数以所用 Flutter-ohos 分支为准
   ```
   `GeneratedPluginRegistrant.ets` 由构建生成，`FFmpegBridge.ets` 位于同目录（plugins/），
   由 `EntryAbility` 显式注册，不依赖生成器。
4. **ABI**：har 只带 `arm64-v8a`。模拟器若为 x86_64 无对应 `.so`，必须以真机验证。
5. **（可选）从源码编译原生库**：在移植仓库的 `ohos/` 目录执行 `prebuild.sh`（仅 Linux），
   先编好 FFmpeg / dav1d / lame / libogg / libvorbis / libvpx / openh264 等依赖，
   再用 DevEco Studio 构建；日常集成直接用 ohpm 预编译产物即可。

## 8. 许可与合规

- **移植层**：`CPF-ApplicationTPC/ohos_ffmpeg_kit` 仓库 README/许可文件标注 **MIT**；
  但发布到 ohpm 的 1.0.1 har 包里 `oh-package.json5` 的 `license` 字段写的是
  **LGPL-3.0**。二者不一致，保守做法是同时满足 MIT 与 LGPL 的署名/源码提供要求，
  并在升级该依赖时复核实际 LICENSE 文件。
- **内含 FFmpeg**：LGPL v3（full build 未启用 `--enable-gpl`）。义务与现有
  `ffmpeg_kit_flutter_new_full` 相同：动态库链接、可替换、随包附许可证文本与本声明、
  提供对应源码获取途径、不移除版权声明。
- 应用自身代码仍为 MIT；`THIRD_PARTY_NOTICES.md` §1.1 已列出本依赖。

## 9. 已知风险与限制

1. **本机无法编译 ArkTS / 打包 HAP**：仓库内没有 ohpm / hvigor / Flutter-ohos 工具链，
   `FFmpegBridge.ets` 只经过静态审查（类型显式化、回调判空、try/catch 全覆盖），
   **未经过编译器验证**；首次真机构建可能需要少量语法/类型修正。
2. **API 版本漂移**：`@ohos/ffmpeg-kit` 仍在演进（har 内 metadata 标注 1.0.1-rc.1 语义、
   `compatibleSdkVersionStage: beta1`）。升级时必须以新 har 的 `*.d.ets` 为准复核调用；
   尤其 `enableFFmpegSessionCompleteCallback(null)` 是否允许、`asnycFFprobeSessionExecute`
   的拼写、`getMediaInformation` 的返回结构。
3. **日志非实时**：1.0.1 未暴露 `enableLogCallback`，转码中间日志拿不到，只有结束时末尾一行；
   UI 上不要依赖实时日志流。
4. **stdout 重定向**：`enableRedirection()` 是全局设置，能否让 ffprobe 的 stdout 进入
   `abstractSessionGetAllLogsAsString` 取决于移植版实现（本机无法验证）。失败时仅损失进度
   百分比，转码与取消不受影响。若真机验证发现拿不到时长，可改用
   `mediaInformationSession` + `getMediaInformation(sessionId)` 的官方路线
   （参考移植仓库 `flutter/` 插件的 `SessionHandler.handleGetMediaInformation`）。
5. **进度精度**：百分比依赖「先探测总时长 + statistics.time」，转码前探测失败则整个任务
   无进度回调（不影响功能）；纯音频/无 `-i` 的场景同样无进度。
6. **取消语义**：原生取消后返回码为 255；若原生偶发不回完成回调，Dart 侧 8 秒兜底按取消收敛。
   取消立即性依赖原生 `cancelSession` 的实现（大文件可能仍需数秒）。
7. **依赖注入风险**：Flutter-ohos 构建会重写/合并 `ohos/entry/oh-package.json5` 等文件，
   若 `@ohos/ffmpeg-kit` 依赖被覆盖，需重新 `ohpm install` 并确认依赖仍在。
8. **时机**：`FFmpegBridge.register` 在 `GeneratedPluginRegistrant.registerWith` 之后调用；
   若自定义 EntryAbility 被模板覆盖，需重新加入该行。
9. **文件路径**：鸿蒙侧 `-i` / 输出路径须为 ArkTS 与原生库都可访问的沙箱路径
   （由现有 `path_provider` ohos 分支提供），不建议使用 `content://` URI。

## 10. 验证清单

- [x] `dart analyze lib/engine/ffmpeg_ohos_backend.dart lib/engine/ffmpeg_backend_factory.dart`
      → `No issues found!`
- [x] 无 `Process.run` / `Process.start` / shell 调用（原生库调用路径）
- [ ] `cd ohos && ohpm install` 成功（需网络 + ohpm 环境）
- [ ] DevEco Studio 6.0.0 / SDK API20 编译 HAP 通过（需完整工具链）
- [ ] 真机：导入 mp4 → 转码 → 进度条推进 → 输出可播放
- [ ] 真机：转码中取消 → 抛 `FfmpegBackendCancelled`，无卡死
- [ ] 真机：未安装 `@ohos/ffmpeg-kit` 时 → `FfmpegBackendUnavailable`，UI 有友好提示
