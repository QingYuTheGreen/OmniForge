import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import FFmpegBridge from '../plugins/FFmpegBridge';

export default class EntryAbility extends FlutterAbility {
  configureFlutterEngine(flutterEngine: FlutterEngine): void {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    // OmniForge：注册 FFmpeg 原生库桥接（@ohos/ffmpeg-kit，通道 omniforge/ffmpeg）。
    // 放在 GeneratedPluginRegistrant 之后，保证其它插件已就绪。
    FFmpegBridge.register(flutterEngine)
  }
}
