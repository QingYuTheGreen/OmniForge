import 'plugin_manifest.dart';

/// 内置原生插件目录。
///
/// 说明：这些插件都需要额外原生库（.so / .dll / .dylib），
/// 应用不内置大体积二进制，由用户在「设置 → 转换插件」中下载 / 导入。
/// 纯 Dart 能实现的能力（哈希、压缩、图片、文档、wav 等）不在此列。
abstract final class PluginCatalog {
  static const List<PluginManifest> builtIn = <PluginManifest>[
    // ── OCR：图片 → txt ───────────────────────────────────────────
    PluginManifest(
      id: 'ocr',
      name: 'OCR 文字识别',
      description: '图片 / 扫描件 / 截图 → txt。RapidOCR（PaddleOCR 模型）原生推理，完全离线。',
      sizeMb: 38,
      platforms: <String>['android', 'ios', 'windows', 'macos', 'linux'],
      engineIds: <String>['ocr'],
      fileName: 'omniforge_ocr',
      notes: <String, String>{
        'backend': 'RapidOCR / PaddleOCR (ONNXRuntime)',
        'models': 'PP-OCRv4 检测 + 方向分类 + 识别模型内置',
        'engine': 'ocr',
      },
    ),

    // ── ASR：语音 → txt / srt ────────────────────────────────────
    PluginManifest(
      id: 'asr',
      name: '语音识别',
      description: '音频 / 视频音轨 → txt / srt。whisper.cpp 原生推理，模型随插件提供，完全离线。',
      sizeMb: 240,
      platforms: <String>['android', 'ios', 'windows', 'macos', 'linux'],
      engineIds: <String>['asr'],
      fileName: 'omniforge_asr',
      notes: <String, String>{
        'backend': 'whisper.cpp',
        'models': 'tiny / base 模型内置（可选下载 small / medium）',
        'engine': 'asr',
      },
    ),

    // ── TTS：文本 → 语音 ─────────────────────────────────────────
    PluginManifest(
      id: 'tts',
      name: '语音合成',
      description: '文本 → wav / mp3。Piper TTS 原生推理，多音色，完全离线。',
      sizeMb: 68,
      platforms: <String>['android', 'ios', 'windows', 'macos', 'linux'],
      engineIds: <String>['tts'],
      fileName: 'omniforge_tts',
      notes: <String, String>{
        'backend': 'piper TTS (ONNXRuntime)',
        'voices': '中文 / 英文各 2 个音色',
        'engine': 'tts',
      },
    ),

    // ── woff2：woff2 → ttf / woff ────────────────────────────────
    PluginManifest(
      id: 'woff2',
      name: 'WOFF2 字体转换',
      description: 'woff2 → ttf / woff / otf。brotli 解压 + glyf 表变换，原生实现。',
      sizeMb: 2,
      platforms: <String>['android', 'ios', 'windows', 'macos', 'linux'],
      engineIds: <String>['woff2'],
      fileName: 'omniforge_woff2',
      notes: <String, String>{
        'backend': 'woff2 (brotli + glyf transform)',
        'engine': 'woff2',
      },
    ),

    // ── PDF 渲染：PDF / 文档 → 图片 ──────────────────────────────
    PluginManifest(
      id: 'pdf_render',
      name: 'PDF 渲染',
      description: 'PDF / XPS / EPUB → png / jpg。MuPDF 原生渲染，保留排版与中文字体。',
      sizeMb: 12,
      platforms: <String>['android', 'ios', 'windows', 'macos', 'linux'],
      engineIds: <String>['pdf_render'],
      fileName: 'omniforge_pdf_render',
      notes: <String, String>{
        'backend': 'MuPDF',
        'engine': 'pdf_render',
      },
    ),

    // ── 压缩增强：RAR / 7z 解压 ──────────────────────────────────
    PluginManifest(
      id: 'archive_pro',
      name: 'RAR / 7z 解压',
      description:
          'rar / 7z / cab 等压缩包解压。unrar + 7z 原生实现（纯 Dart 只支持 zip / tar / gz）。',
      sizeMb: 8,
      platforms: <String>['android', 'ios', 'windows', 'macos', 'linux'],
      engineIds: <String>['archive_pro'],
      fileName: 'omniforge_archive_pro',
      notes: <String, String>{
        'backend': 'unrar + 7-Zip',
        'engine': 'archive_pro',
      },
    ),

    // midi（音频 → MIDI）未放入目录：
    // 项目已有纯 Dart 音高识别实现，无需原生插件；
    // 若后续替换为高精度神经网络音高模型，再按本文件格式补充即可。
  ];

  /// 该引擎 id 对应的插件（未覆盖时返回 null）。
  static PluginManifest? byEngineId(String engineId) {
    for (final manifest in builtIn) {
      if (manifest.engineIds.contains(engineId)) return manifest;
    }
    return null;
  }

  /// 按插件 id 查找（未知 id 返回 null）。
  static PluginManifest? byId(String id) {
    for (final manifest in builtIn) {
      if (manifest.id == id) return manifest;
    }
    return null;
  }

  /// 当前平台可安装的插件列表。
  static List<PluginManifest> forPlatform(String platform) => builtIn
      .where((manifest) => manifest.supportsPlatform(platform))
      .toList(growable: false);
}
