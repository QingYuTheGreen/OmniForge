/// 引擎真实读写能力表。
///
/// 规划器据此建立「隐式边」：只有 `sources` 里的格式确实能被该引擎读取、
/// 且目标格式确实能由该引擎写出时，才会生成一条转换边。
/// 这比按类别名猜测（`accepts_from: ["image"]`）精确得多，可避免出现
/// 「公文包 → 二维码 → PNG」这类引擎根本无法执行的链路。
///
/// 泛型来源用 `'*'` 表示「任意格式」，仅限哈希 / 二维码 / 头像这类
/// 只读取原始字节的终端产物引擎。
class EngineCapability {
  /// 引擎 id（与 `EngineRegistry` 中注册的一致）。
  final String engineId;

  /// 可读取的输入格式 id，`'*'` 表示任意格式。
  final List<String> sources;

  /// 可写出的目标格式 id。
  final List<String> targets;

  const EngineCapability(this.engineId, this.sources, this.targets);
}

const List<String> _images = <String>[
  'jpg',
  'png',
  'webp',
  'gif',
  'bmp',
  'tiff',
  'ico',
];

const List<String> _audio = <String>[
  'mp3',
  'wav',
  'flac',
  'aac',
  'm4a',
  'ogg',
];

const List<String> _video = <String>['mp4', 'mkv', 'mov', 'avi', 'webm', 'flv'];

const List<String> _media = <String>[..._audio, ..._video];

const List<String> _meshes = <String>[
  'obj',
  'stl',
  'ply',
  'off',
  'gltf',
  'glb',
];

const List<String> _textures = <String>['dds', 'ktx', 'tga'];

const List<String> _gps = <String>['gpx', 'kml', 'tcx', 'geojson'];

const List<String> _subtitles = <String>['srt', 'ass', 'vtt', 'lrc'];

const List<String> _playlists = <String>['m3u', 'm3u8', 'cue'];

const List<String> _palettes = <String>['ase', 'aco', 'gpl', 'json'];

const List<String> _tables = <String>['xlsx', 'csv', 'json', 'xml'];

const List<String> _documents = <String>['txt', 'docx', 'md', 'html', 'rtf'];

const List<String> _fonts = <String>['ttf', 'otf', 'woff'];

const List<String> _embroidery = <String>['pes', 'dst', 'jef'];

const List<String> _minecraft = <String>[
  'mcworld',
  'mcpack',
  'mcworld_java',
  'mcpack_java',
];

/// 全部引擎的能力声明。顺序即隐式边的优先级顺序。
const List<EngineCapability> engineCapabilities = <EngineCapability>[
  // ── 位图 ──
  EngineCapability('image', [..._images, 'tga'], [..._images, 'tga']),
  // ── 纹理 ──
  EngineCapability('texture', [..._textures, ..._images],
      ['png', 'jpg', 'webp', 'bmp', 'tga', 'dds']),
  EngineCapability('texture', _images, ['dds', 'ktx', 'tga']),
  // ── 矢量 / 调色板 / 文档插图 ──
  EngineCapability('svg_vector', _images, ['svg']),
  EngineCapability('image_palette', _images, _palettes),
  EngineCapability('palette_image', _palettes, ['png']),
  EngineCapability('image_doc', _images, ['docx']),
  EngineCapability('ascii_art', _images, ['ascii_art', 'braille_art']),
  // ── 终端产物（只读原始字节，不做中转） ──
  EngineCapability('qr', ['*'], ['qr_png']),
  EngineCapability('identicon', ['*'], ['identicon_png']),
  EngineCapability('hash', ['*'], ['md5', 'sha', 'crc', 'base64']),
  // ── 文本 / 文档 / 电子书 / PDF ──
  EngineCapability('text', ['txt', 'md', 'html'], ['txt', 'md', 'html']),
  EngineCapability('document', _documents, _documents),
  EngineCapability('ebook', ['epub'], ['epub', 'txt', 'md', 'html']),
  EngineCapability('pdf', [..._images, 'txt', 'md', 'html'], ['pdf']),
  EngineCapability('pdf', ['pdf'], ['txt']),
  // ── 演示文稿 / 表格 ──
  EngineCapability('slides', ['pptx', 'odp'],
      ['pptx', 'odp', 'txt', 'md', 'html', 'pdf']),
  EngineCapability('spreadsheet', _tables, _tables),
  EngineCapability('table', _tables, _tables),
  // ── 字体 / 调色板 ──
  EngineCapability('font', _fonts, _fonts),
  EngineCapability('color', _palettes, _palettes),
  // ── 3D / 网格 ──
  EngineCapability('mesh', _meshes, ['obj', 'ply', 'off', 'stl']),
  EngineCapability('model3d', _meshes, _meshes),
  EngineCapability('mesh_geo', _meshes, ['geo_json']),
  EngineCapability('render3d', _meshes, ['png', 'jpg']),
  // ── 绣花 / GPS / 字幕 / 播放列表 ──
  EngineCapability('embroidery', _embroidery, [..._embroidery, 'png']),
  EngineCapability('embroidery', _images, _embroidery),
  EngineCapability('geo_render', _gps, ['svg', 'png']),
  EngineCapability('gps', _gps, _gps),
  EngineCapability('subtitle', _subtitles, _subtitles),
  EngineCapability('playlist', _playlists, _playlists),
  // ── 压缩包 / Minecraft ──
  EngineCapability('archive', ['zip', 'tar_gz'], ['zip', 'tar_gz']),
  EngineCapability('minecraft', [..._minecraft, 'zip'], _minecraft),
  // ── 音视频（原生 FFmpegKitNext） ──
  EngineCapability('audio_midi', _audio, ['midi']),
  EngineCapability('spectrogram', _audio, ['png', 'jpg']),
  EngineCapability('ffmpeg', _media, _media),
  EngineCapability('ffmpeg', _video, ['gif', 'srt', 'png', 'jpg']),
];
