import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// 跨平台输出目录：尽量放到用户能直接找到的地方
/// Android:   /storage/emulated/0/OmniForge/（需全文件访问权限）
/// Windows:   D:\OmniForge\（无 D 盘则 用户目录\OmniForge）
/// macOS:     ~/OmniForge/
/// Linux:     ~/OmniForge/
/// iOS / OHOS: 沙盒目录/OmniForge/（系统不允许写公共目录）
class OutputPaths {
  static Directory? _cache;

  static Future<Directory> get outputDir async {
    if (_cache != null && await _cache!.exists()) return _cache!;

    Directory dir;

    if (Platform.isAndroid) {
      dir = Directory('/storage/emulated/0/OmniForge');
    } else if (Platform.isWindows) {
      if (await Directory(r'D:\').exists()) {
        dir = Directory(r'D:\OmniForge');
      } else {
        final home = Platform.environment['USERPROFILE'] ?? '';
        dir = Directory('$home\\OmniForge');
      }
    } else if (Platform.isMacOS || Platform.isLinux) {
      final home = Platform.environment['HOME'] ?? '';
      dir = Directory('$home/OmniForge');
    } else if (Platform.isIOS) {
      final docs = await getApplicationDocumentsDirectory();
      dir = Directory('${docs.path}/OmniForge');
    } else {
      // OHOS 及其他：path_provider 鸿蒙适配版，落到应用沙箱临时目录
      final temp = await getTemporaryDirectory();
      dir = Directory('${temp.path}/OmniForge');
    }

    try {
      if (!await dir.exists()) await dir.create(recursive: true);
      _cache = dir;
    } catch (_) {
      // Android 无权限时回退到应用缓存目录，避免直接崩
      final fallback = Directory('${(await getTemporaryDirectory()).path}/OmniForge');
      if (!await fallback.exists()) await fallback.create(recursive: true);
      _cache = fallback;
    }
    return _cache!;
  }

  /// 设置页展示用的目录说明
  static String get description {
    if (Platform.isAndroid) return '/storage/emulated/0/OmniForge/';
    if (Platform.isWindows) return r'D:\OmniForge\ （无 D 盘时用 用户目录\OmniForge）';
    if (Platform.isMacOS) return '~/OmniForge/';
    if (Platform.isLinux) return '~/OmniForge/';
    return '应用沙箱目录/OmniForge/';
  }

  /// 生成输出路径：原名_output.扩展名
  static Future<String> buildOutputPath(String inputFileName, String outputExt) async {
    final dir = await outputDir;
    final base = inputFileName.contains('.')
        ? inputFileName.substring(0, inputFileName.lastIndexOf('.'))
        : inputFileName;
    final ext = outputExt.startsWith('.') ? outputExt.substring(1) : outputExt;
    return '${dir.path}${Platform.pathSeparator}${base}_output.$ext';
  }
}
