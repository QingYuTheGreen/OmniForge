/*
 * OmniForge OpenHarmony FFmpeg 桥接。
 *
 * 把 Dart 侧 `FfmpegOhosBackend`（lib/engine/ffmpeg_ohos_backend.dart）的
 * MethodChannel 调用转成 `@ohos/ffmpeg-kit`（ohpm 包，NAPI 原生库
 * libffmpegkit_napi.so，内含 libav*）的函数式 API 调用。
 *
 * 通道名：omniforge/ffmpeg
 *
 * Dart -> ArkTS：
 *   execute        {command: string, arguments: string[], durationMs?: number}
 *                  -> number sessionId
 *   cancel         {sessionId: number} -> null
 *   probeDuration  {path: string} -> number?（毫秒，0 表示无法解析）
 *
 * ArkTS -> Dart：
 *   progress  {sessionId: number, percent: number}   0..100
 *   log       {sessionId: number, message: string}   结束时回传日志末尾
 *   complete  {sessionId: number, code: number}      0 成功 / 255 取消
 *
 * 说明：
 * * 全部走原生库调用（FFmpegKit / FFprobeKit 的鸿蒙移植版），不启动命令行进程。
 * * 1.0.1 包的完成回归调不携带 returnCode，需再查
 *   `abstractSessionGetReturnCode`；日志同理用 `abstractSessionGetAllLogsAsString`
 *   事后读取（该版本未导出 enableLogCallback）。
 * * 原生回调可能在非 UI 线程触发，统一通过 @kit.BasicServicesKit 的 emitter
 *   派发回主线程，再操作 MethodChannel。
 */

import {
  FlutterEngine,
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult
} from '@ohos/flutter_ohos';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { emitter } from '@kit.BasicServicesKit';
import { HashMap } from '@kit.ArkTS';
import {
  abstractSessionGetAllLogsAsString,
  abstractSessionGetReturnCode,
  asyncFFmpegSessionExecute,
  cancelSession,
  enableFFmpegSessionCompleteCallback,
  enableRedirection,
  enableStatisticsCallback,
  ffmpegSession,
  ffprobeSession,
  ffprobeSessionExecute,
  RegisterGlobalCallback,
  SessionObject,
  StatisticsObject
} from '@ohos/ffmpeg-kit';

const DOMAIN: number = 0x0FF0;
const TAG: string = 'FFmpegBridge';

/** 与 Dart 侧 FfmpegOhosBackend.channelName 保持一致。 */
const CHANNEL_NAME: string = 'omniforge/ffmpeg';

/** emitter 事件 ID：原生回调 -> 主线程。 */
const EVENT_COMPLETE: number = 20001;
const EVENT_STATISTICS: number = 20002;
const EVENT_PROBE_DONE: number = 20003;

/** ffmpeg-kit 返回码约定。 */
const RETURN_CODE_SUCCESS: number = 0;
const RETURN_CODE_CANCEL: number = 255;

/** ffprobe 取时长参数前缀，实际接在 `-i <path>` 之前。 */
const PROBE_ARGUMENTS: string[] = [
  '-v', 'error',
  '-show_entries', 'format=duration',
  '-of', 'default=noprint_wrappers=1:nokey=1',
  '-i'
];

/** 探测时长超过该时间仍未回调则返回 0，避免 Dart 侧一直等待。 */
const PROBE_TIMEOUT_MS: number = 10000;

type SessionMap = Map<string, ESObject>;
type ChannelValue = Object | number | string | boolean;
type ChannelArguments = Map<string, ChannelValue>;

export default class FFmpegBridge implements FlutterPlugin, MethodCallHandler {
  private static registered: boolean = false;

  private channel: MethodChannel | null = null;

  /** sessionId -> 转码总时长（毫秒），用于把 statistics.time 换算成百分比。 */
  private durationBySession: Map<number, number> = new Map<number, number>();

  /** ffprobe 探测会话：sessionId -> 待回复的 MethodResult。 */
  private pendingProbes: Map<number, MethodResult> = new Map<number, MethodResult>();

  /** 保持 native 回调强引用，供 detach 时置空断开闭包链。 */
  private completeCallback: ((session: SessionObject) => void) | null = null;
  private statisticsCallback: ((statistics: StatisticsObject) => void) | null = null;

  private callbacksInstalled: boolean = false;
  private emitterSubscribed: boolean = false;

  /**
   * 在 EntryAbility.configureFlutterEngine 中调用，把桥接注册到引擎。
   * 与 Flutter-ohos 生成的 GeneratedPluginRegistrant 写法一致：
   * `flutterEngine.getPlugins()?.add(new XxxPlugin())`。
   */
  static register(engine: FlutterEngine): void {
    if (FFmpegBridge.registered) {
      hilog.info(DOMAIN, TAG, 'FFmpegBridge already registered, skip.');
      return;
    }
    try {
      engine.getPlugins()?.add(new FFmpegBridge());
      FFmpegBridge.registered = true;
      hilog.info(DOMAIN, TAG, 'FFmpegBridge registered.');
    } catch (e) {
      hilog.error(DOMAIN, TAG, `FFmpegBridge register failed: ${e}`);
    }
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    try {
      this.channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL_NAME);
      this.channel.setMethodCallHandler(this);
      this.installCallbacks();
      hilog.info(DOMAIN, TAG, `channel ${CHANNEL_NAME} attached.`);
    } catch (e) {
      hilog.error(DOMAIN, TAG, `onAttachedToEngine failed: ${e}`);
    }
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    try {
      // 取消所有仍在运行的会话，随后注销回调。
      try {
        this.durationBySession.forEach((duration: number, sessionId: number) => {
          try {
            cancelSession(sessionId);
          } catch (e) {
            hilog.warn(DOMAIN, TAG, `cancelSession ${sessionId} failed: ${e}`);
          }
        });
      } catch (e) {
        hilog.warn(DOMAIN, TAG, `cancel all sessions failed: ${e}`);
      }
      this.durationBySession.clear();
      this.pendingProbes.clear();
      this.uninstallCallbacks();
      if (this.channel != null) {
        this.channel.setMethodCallHandler(null);
        this.channel = null;
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, `onDetachedFromEngine failed: ${e}`);
    }
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    try {
      switch (call.method) {
        case 'execute':
          this.handleExecute(call, result);
          return;
        case 'cancel':
          this.handleCancel(call, result);
          return;
        case 'probeDuration':
          this.handleProbeDuration(call, result);
          return;
        default:
          result.notImplemented();
          return;
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, `onMethodCall ${call.method} failed: ${e}`);
      try {
        result.error('NATIVE_ERROR', `FFmpeg 桥接异常：${e}`, null);
      } catch (inner) {
        hilog.error(DOMAIN, TAG, `report error failed: ${inner}`);
      }
    }
  }

  // ---------------------------------------------------------------------
  // MethodChannel 处理
  // ---------------------------------------------------------------------

  private handleExecute(call: MethodCall, result: MethodResult): void {
    let argumentsArray: string[] = this.readArguments(call);
    if (argumentsArray.length === 0) {
      result.error('INVALID_ARGUMENTS', 'FFmpeg 参数为空', null);
      return;
    }

    let sessionMap: SessionMap = new Map<string, ESObject>();
    try {
      sessionMap = ffmpegSession(argumentsArray);
    } catch (e) {
      result.error('NATIVE_ERROR', `ffmpegSession 创建失败：${e}`, null);
      return;
    }

    let sessionId: number = sessionMap.get('sessionId') as number;
    if (sessionId == null || sessionId < 0) {
      result.error('NATIVE_ERROR', 'ffmpegSession 未返回有效 sessionId', null);
      return;
    }

    let durationMs: number = this.readNumber(call, 'durationMs', 0);
    if (durationMs > 0) {
      this.durationBySession.set(sessionId, durationMs);
    }

    try {
      // 原生 ThreadPool 异步执行，立即返回 sessionId。
      asyncFFmpegSessionExecute(sessionId);
    } catch (e) {
      this.durationBySession.delete(sessionId);
      result.error('NATIVE_ERROR', `FFmpeg 执行启动失败：${e}`, null);
      return;
    }

    result.success(sessionId);
  }

  private handleCancel(call: MethodCall, result: MethodResult): void {
    let sessionId: number = this.readNumber(call, 'sessionId', -1);
    if (sessionId < 0) {
      result.error('INVALID_ARGUMENTS', '缺少 sessionId', null);
      return;
    }
    try {
      cancelSession(sessionId);
      result.success(null);
    } catch (e) {
      result.error('NATIVE_ERROR', `取消会话失败：${e}`, null);
    }
  }

  private handleProbeDuration(call: MethodCall, result: MethodResult): void {
    let path: string = this.readString(call, 'path');
    if (path.length === 0) {
      result.success(0);
      return;
    }

    let ffprobeArguments: string[] = [];
    PROBE_ARGUMENTS.forEach((item: string) => {
      ffprobeArguments.push(item);
    });
    ffprobeArguments.push(path);

    let sessionId: number = -1;
    try {
      let sessionMap: SessionMap = ffprobeSession(ffprobeArguments);
      sessionId = sessionMap.get('sessionId') as number;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `ffprobeSession create failed: ${e}`);
      result.success(0);
      return;
    }

    if (sessionId == null || sessionId < 0) {
      result.success(0);
      return;
    }

    this.pendingProbes.set(sessionId, result);

    // 兜底：原生回调缺失时也回复，避免 Dart 侧 execute 永久等待时长探测。
    setTimeout(() => {
      if (this.pendingProbes.has(sessionId)) {
        this.pendingProbes.delete(sessionId);
        try {
          result.success(0);
        } catch (e) {
          hilog.warn(DOMAIN, TAG, `probe fallback reply failed: ${e}`);
        }
      }
    }, PROBE_TIMEOUT_MS);

    try {
      // 原生 ThreadPool 执行 ffprobe，结束后回调；回调可能不在 UI 线程。
      ffprobeSessionExecute(sessionId, () => {
        try {
          emitter.emit({ eventId: EVENT_PROBE_DONE }, { data: { 'sessionId': sessionId } });
        } catch (e) {
          hilog.error(DOMAIN, TAG, `emit probe done failed: ${e}`);
        }
      });
    } catch (e) {
      this.pendingProbes.delete(sessionId);
      hilog.warn(DOMAIN, TAG, `ffprobeSessionExecute failed: ${e}`);
      result.success(0);
    }
  }

  // ---------------------------------------------------------------------
  // 原生回调（注册一次，按 sessionId 分发）
  // ---------------------------------------------------------------------

  private installCallbacks(): void {
    if (this.callbacksInstalled) {
      return;
    }

    try {
      this.subscribeEmitter();
      // RegisterGlobalCallback 注册原生日志通道，保证 session 日志可被收集。
      RegisterGlobalCallback();
      // 把 ffmpeg/ffprobe 的标准输出也并入日志：probeDuration 依赖 ffprobe 的
      // stdout（format=duration）出现在 abstractSessionGetAllLogsAsString 里。
      try {
        enableRedirection();
      } catch (e) {
        hilog.warn(DOMAIN, TAG, `enableRedirection failed: ${e}`);
      }

      this.completeCallback = (session: SessionObject) => {
        emitter.emit({ eventId: EVENT_COMPLETE }, { data: { 'session': session } });
      };
      this.statisticsCallback = (statistics: StatisticsObject) => {
        emitter.emit({ eventId: EVENT_STATISTICS }, { data: { 'statistics': statistics } });
      };

      enableFFmpegSessionCompleteCallback(this.completeCallback);
      enableStatisticsCallback(this.statisticsCallback);
      this.callbacksInstalled = true;
    } catch (e) {
      hilog.error(DOMAIN, TAG, `install native callbacks failed: ${e}`);
      this.callbacksInstalled = false;
    }
  }

  private uninstallCallbacks(): void {
    if (!this.callbacksInstalled) {
      return;
    }
    try {
      // 用空实现覆盖，避免 null 与包的类型声明不一致。
      enableFFmpegSessionCompleteCallback((session: SessionObject) => {
      });
      enableStatisticsCallback((statistics: StatisticsObject) => {
      });
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `uninstall native callbacks failed: ${e}`);
    }
    this.completeCallback = null;
    this.statisticsCallback = null;
    this.callbacksInstalled = false;
    this.unsubscribeEmitter();
  }

  private subscribeEmitter(): void {
    if (this.emitterSubscribed) {
      return;
    }
    try {
      emitter.on({ eventId: EVENT_COMPLETE }, (eventData: emitter.EventData) => {
        this.onNativeComplete(eventData.data?.['session'] as SessionObject);
      });
      emitter.on({ eventId: EVENT_STATISTICS }, (eventData: emitter.EventData) => {
        this.onNativeStatistics(eventData.data?.['statistics'] as StatisticsObject);
      });
      emitter.on({ eventId: EVENT_PROBE_DONE }, (eventData: emitter.EventData) => {
        this.onProbeDone(eventData.data?.['sessionId'] as number);
      });
      this.emitterSubscribed = true;
    } catch (e) {
      hilog.error(DOMAIN, TAG, `subscribe emitter failed: ${e}`);
      this.emitterSubscribed = false;
    }
  }

  private unsubscribeEmitter(): void {
    if (!this.emitterSubscribed) {
      return;
    }
    try {
      emitter.off(EVENT_COMPLETE);
      emitter.off(EVENT_STATISTICS);
      emitter.off(EVENT_PROBE_DONE);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `unsubscribe emitter failed: ${e}`);
    }
    this.emitterSubscribed = false;
  }

  private onNativeComplete(session: SessionObject): void {
    try {
      let sessionMap: SessionMap = SessionObject.propertyToMap(session);
      let sessionId: number = sessionMap.get('sessionId') as number;
      if (sessionId == null || sessionId < 0) {
        return;
      }
      this.durationBySession.delete(sessionId);

      let returnCode: number = -1;
      try {
        returnCode = abstractSessionGetReturnCode(sessionId);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, `get return code ${sessionId} failed: ${e}`);
      }

      let logs: string = '';
      try {
        logs = abstractSessionGetAllLogsAsString(sessionId, 0);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, `get logs ${sessionId} failed: ${e}`);
      }

      let logArguments: ChannelArguments = new Map<string, ChannelValue>();
      logArguments.set('sessionId', sessionId);
      logArguments.set('message', FFmpegBridge.tail(logs));
      this.invokeDart('log', logArguments);

      let completeArguments: ChannelArguments = new Map<string, ChannelValue>();
      completeArguments.set('sessionId', sessionId);
      completeArguments.set('code', returnCode);
      this.invokeDart('complete', completeArguments);
    } catch (e) {
      hilog.error(DOMAIN, TAG, `onNativeComplete failed: ${e}`);
    }
  }

  private onNativeStatistics(statistics: StatisticsObject): void {
    try {
      let statisticsMap: HashMap<string, ESObject> = StatisticsObject.PropertyToMap(statistics);
      let sessionId: number = statisticsMap.get('sessionId') as number;
      if (sessionId == null || sessionId < 0) {
        return;
      }
      let durationMs: number | undefined = this.durationBySession.get(sessionId);
      if (durationMs == undefined || durationMs <= 0) {
        return;
      }
      let timeMs: number = statisticsMap.get('time') as number;
      if (timeMs == null || timeMs < 0) {
        return;
      }
      let percent: number = Math.min(100, Math.max(0, timeMs * 100 / durationMs));
      let progressArguments: ChannelArguments = new Map<string, ChannelValue>();
      progressArguments.set('sessionId', sessionId);
      progressArguments.set('percent', percent);
      this.invokeDart('progress', progressArguments);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `onNativeStatistics failed: ${e}`);
    }
  }

  private onProbeDone(sessionId: number): void {
    if (sessionId == null || sessionId < 0) {
      return;
    }
    let pending: MethodResult | undefined = this.pendingProbes.get(sessionId);
    if (pending == undefined) {
      return;
    }
    this.pendingProbes.delete(sessionId);

    let durationMs: number = 0;
    try {
      let logs: string = abstractSessionGetAllLogsAsString(sessionId, 0);
      durationMs = FFmpegBridge.parseDurationMs(logs);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `read probe logs ${sessionId} failed: ${e}`);
    }
    try {
      pending.success(durationMs);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `reply probe duration failed: ${e}`);
    }
  }

  // ---------------------------------------------------------------------
  // 工具
  // ---------------------------------------------------------------------

  private invokeDart(method: string, arguments: ChannelArguments): void {
    if (this.channel == null) {
      return;
    }
    try {
      this.channel.invokeMethod(method, arguments);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `invokeMethod ${method} failed: ${e}`);
    }
  }

  /** 优先读 arguments 数组；老版本调用只带 command 时按空格切分（含空格路径不适用）。 */
  private readArguments(call: MethodCall): string[] {
    let argumentsArray: string[] = call.argument('arguments') ?? [];
    if (argumentsArray != null && argumentsArray.length > 0) {
      return argumentsArray;
    }
    let command: string = this.readString(call, 'command');
    if (command.length === 0) {
      return [];
    }
    return command.split(' ').filter((item: string) => item.length > 0);
  }

  private readString(call: MethodCall, key: string): string {
    let value: ESObject = call.argument(key);
    if (value == null) {
      return '';
    }
    return value as string;
  }

  private readNumber(call: MethodCall, key: string, fallback: number): number {
    let value: ESObject = call.argument(key);
    if (value == null) {
      return fallback;
    }
    let numberValue: number = value as number;
    if (numberValue == null || Number.isNaN(numberValue)) {
      return fallback;
    }
    return numberValue;
  }

  /** 取日志最后一条非空行，作为失败原因回传给 Dart。 */
  private static tail(logs: string): string {
    if (logs == null || logs.length === 0) {
      return '';
    }
    let lines: string[] = logs.split('\n');
    for (let i: number = lines.length - 1; i >= 0; i--) {
      let line: string = lines[i].trim();
      if (line.length > 0) {
        return line.length > 500 ? line.substring(line.length - 500) : line;
      }
    }
    return '';
  }

  /** 从 ffprobe 的 `format=duration` 输出（秒）解析毫秒。 */
  private static parseDurationMs(logs: string): number {
    if (logs == null || logs.length === 0) {
      return 0;
    }
    let lines: string[] = logs.split('\n');
    for (let i: number = 0; i < lines.length; i++) {
      let line: string = lines[i].trim();
      if (line.length === 0) {
        continue;
      }
      let seconds: number = Number.parseFloat(line);
      if (!Number.isNaN(seconds) && seconds > 0) {
        return Math.round(seconds * 1000);
      }
    }
    return 0;
  }
}
