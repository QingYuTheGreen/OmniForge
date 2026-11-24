import 'engines/archive_engine.dart';
import 'engines/ascii_art_engine.dart';
import 'engines/audio_midi_engine.dart';
import 'engines/color_engine.dart';
import 'engines/document_engine.dart';
import 'engines/ebook_engine.dart';
import 'engines/embroidery_engine.dart';
import 'engines/ffmpeg_backend.dart';
import 'engines/ffmpeg_engine.dart';
import 'engines/font_engine.dart';
import 'engines/geo_render_engine.dart';
import 'engines/gps_engine.dart';
import 'engines/hash_engine.dart';
import 'engines/identicon_engine.dart';
import 'engines/image_doc_engine.dart';
import 'engines/image_engine.dart';
import 'engines/image_palette_engine.dart';
import 'engines/mesh_engine.dart';
import 'engines/mesh_geo_engine.dart';
import 'engines/mesh_render_engine.dart';
import 'engines/minecraft_engine.dart';
import 'engines/model3d_engine.dart';
import 'engines/palette_image_engine.dart';
import 'engines/pdf_engine.dart';
import 'engines/playlist_engine.dart';
import 'engines/qr_engine.dart';
import 'engines/slides_engine.dart';
import 'engines/spectrogram_engine.dart';
import 'engines/spreadsheet_engine.dart';
import 'engines/subtitle_engine.dart';
import 'engines/svg_vector_engine.dart';
import 'engines/table_engine.dart';
import 'engines/text_engine.dart';
import 'engines/texture_engine.dart';
import 'i_engine.dart';

/// 引擎可用状态：
/// - [ready]：当前构建可直接转换
/// - [pluginRequired]：引擎已实现，但当前构建缺少所需的原生库
/// - [missing]：该引擎尚未注册
enum EngineReadiness { ready, pluginRequired, missing }

/// 缺少内置原生库时的说明信息（普通安装包中不会出现）。
class PluginInfo {
  final String id;
  final int sizeMb;

  const PluginInfo(this.id, this.sizeMb);
}

/// 引擎注册表：id ⇄ [IEngine]。
class EngineRegistry {
  final Map<String, IEngine> _engines;

  EngineRegistry(Iterable<IEngine> engines)
      : _engines = <String, IEngine>{
          for (final engine in engines) engine.id: engine,
        };

  /// 平台默认引擎集合。
  ///
  /// 所有转换能力都随安装包内置：纯 Dart 算法引擎 + 编译进包的 FFmpegKitNext
  /// 原生库（Android / iOS / macOS / Windows / Linux）。不存在“外置安装插件”
  /// 的路径；开发环境未注入原生库后端时，音视频引擎会明确提示缺少内置原生库。
  factory EngineRegistry.platformDefaults({FfmpegBackend? ffmpegBackend}) {
    return EngineRegistry(<IEngine>[
      const HashEngine(),
      const SubtitleEngine(),
      const PlaylistEngine(),
      const GpsEngine(),
      const ColorEngine(),
      const TableEngine(),
      const TextEngine(),
      const DocumentEngine(),
      const SpreadsheetEngine(),
      const EbookEngine(),
      const PdfEngine(),
      const ImageEngine(),
      const TextureEngine(),
      const SvgVectorEngine(),
      const ImagePaletteEngine(),
      const PaletteImageEngine(),
      const ImageDocEngine(),
      const AsciiArtEngine(),
      const QrEngine(),
      const IdenticonEngine(),
      const MeshEngine(),
      const MeshRenderEngine(),
      const MeshGeoEngine(),
      const GeoRenderEngine(),
      const EmbroideryEngine(),
      const Model3DEngine(),
      const ArchiveEngine(),
      const MinecraftEngine(),
      FfmpegEngine(backend: ffmpegBackend ?? const NullFfmpegBackend()),
      const SlidesEngine(),
      const FontEngine(),
      AudioMidiEngine(backend: ffmpegBackend ?? const NullFfmpegBackend()),
      SpectrogramEngine(backend: ffmpegBackend ?? const NullFfmpegBackend()),
    ]);
  }

  /// 全部已注册引擎。
  List<IEngine> get all => List.unmodifiable(_engines.values);

  IEngine? operator [](String id) => _engines[id];

  bool contains(String id) => _engines.containsKey(id);

  /// 该引擎当前是否可直接运行。
  EngineReadiness readiness(String id) {
    final engine = _engines[id];
    if (engine == null) return EngineReadiness.missing;
    if (engine is FfmpegEngine && !engine.isAvailable) {
      return EngineReadiness.pluginRequired;
    }
    return EngineReadiness.ready;
  }

  /// 该引擎缺失内置能力时的 id（可直接运行时为 null）。
  String? pluginIdOf(String id) => _engines[id]?.requiredPluginId;

  /// 该引擎缺失能力的说明（可直接运行 / 未注册时返回 null）。
  PluginInfo? pluginInfoOf(String id) {
    final engine = _engines[id];
    if (engine == null) return null;
    if (engine is FfmpegEngine && !engine.isAvailable) {
      return const PluginInfo('ffmpeg', 0);
    }
    return null;
  }

  /// 当前平台可直接使用的引擎 id 集合（供规划器使用）。
  Set<String> get readyEngineIds => _engines.keys
      .where((id) => readiness(id) == EngineReadiness.ready)
      .toSet();
}

/// 常见引擎 id 常量，避免各处写错字符串。
abstract final class EngineIds {
  static const hash = 'hash';
  static const subtitle = 'subtitle';
  static const playlist = 'playlist';
  static const gps = 'gps';
  static const color = 'color';
  static const table = 'table';
  static const text = 'text';
  static const document = 'document';
  static const spreadsheet = 'spreadsheet';
  static const ebook = 'ebook';
  static const pdf = 'pdf';
  static const image = 'image';
  static const texture = 'texture';
  static const mesh = 'mesh';
  static const model3d = 'model3d';
  static const archive = 'archive';
  static const minecraft = 'minecraft';
  static const ffmpeg = 'ffmpeg';
}
