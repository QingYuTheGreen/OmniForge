import 'dart:io';
import 'dart:typed_data';

/// 识别结果
class DetectedFormat {
  /// 类型键，与 formats.yaml 的 categories 对齐（19 类）：
  /// image / audio / video / ebook / document / slides / spreadsheet / font /
  /// palette / model3d / texture / mesh / hash / embroidery / gps / subtitle /
  /// playlist / archive / minecraft，未识别为 unknown
  final String typeKey;

  /// 类型中文名
  final String typeLabel;

  /// 格式扩展名（不带点，小写），未知时为 ''
  final String formatExt;

  /// 是否由文件头魔数确认（比纯扩展名更可靠）
  final bool byMagic;

  const DetectedFormat({
    required this.typeKey,
    required this.typeLabel,
    required this.formatExt,
    this.byMagic = false,
  });

  bool get isKnown => typeKey != 'unknown';

  /// 格式展示文本，如 .png
  String get formatLabel => formatExt.isEmpty ? '未知格式' : '.$formatExt';

  @override
  String toString() => '$typeLabel ${formatLabel.isEmpty ? '' : formatLabel}';
}

/// 文件类型 / 格式自动识别
///
/// 先用文件头魔数判断真实内容（防止扩展名被改错），再用扩展名补充；
/// 不支持的格式或读不到文件时回退到纯扩展名，再不行就是 unknown。
class FileTypeDetector {
  /// 完整识别（读文件头，需要文件可读）
  static Future<DetectedFormat> detect(String path) async {
    final ext = _extension(path);

    Uint8List? head;
    try {
      final raf = await File(path).open();
      head = await raf.read(16);
      await raf.close();
    } catch (_) {
      head = null;
    }

    if (head != null && head.isNotEmpty) {
      final magic = _matchMagic(head, ext);
      if (magic != null) return magic;
    }
    return fromExtension(ext);
  }

  /// 只按扩展名识别（不读文件，UI 上快速预填用）
  static DetectedFormat detectSync(String path) {
    return fromExtension(_extension(path));
  }

  /// 扩展名 → 结果
  static DetectedFormat fromExtension(String ext) {
    final e = ext.toLowerCase();
    final type = _compoundType[e] ?? _extType[e];
    if (type == null) {
      return DetectedFormat(
        typeKey: 'unknown',
        typeLabel: '未知类型',
        formatExt: e,
      );
    }
    return DetectedFormat(
      typeKey: type,
      typeLabel: _typeLabels[type] ?? '未知类型',
      formatExt: e,
    );
  }

  /// 复合扩展名白名单：这些格式的点号后两段才算完整扩展名
  static const List<String> _compoundExts = [
    'tar.gz', 'tar.bz2', 'tar.xz', 'geo.json',
  ];

  static String _extension(String path) {
    final lower = path.toLowerCase();
    for (final c in _compoundExts) {
      if (lower.endsWith('.$c')) return c;
    }
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return '';
    return path.substring(dot + 1).toLowerCase();
  }

  // ── 魔数匹配 ──
  static DetectedFormat? _matchMagic(Uint8List b, String ext) {
    bool startsWith(List<int> sig) {
      if (b.length < sig.length) return false;
      for (var i = 0; i < sig.length; i++) {
        if (b[i] != sig[i]) return false;
      }
      return true;
    }

    bool asciiAt(int offset, String s) {
      if (b.length < offset + s.length) return false;
      for (var i = 0; i < s.length; i++) {
        if (b[offset + i] != s.codeUnitAt(i)) return false;
      }
      return true;
    }

    // PNG
    if (startsWith([0x89, 0x50, 0x4E, 0x47])) {
      return _r('image', 'png', ext);
    }
    // JPEG
    if (startsWith([0xFF, 0xD8, 0xFF])) {
      return _r('image', ext == 'jpeg' ? 'jpeg' : 'jpg', ext);
    }
    // GIF
    if (asciiAt(0, 'GIF8')) {
      return _r('image', 'gif', ext);
    }
    // BMP
    if (asciiAt(0, 'BM')) {
      return _r('image', 'bmp', ext);
    }
    // PDF
    if (asciiAt(0, '%PDF')) {
      return _r('document', 'pdf', ext);
    }
    // 7z
    if (startsWith([0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C])) {
      return _r('archive', '7z', ext);
    }
    // RAR
    if (asciiAt(0, 'Rar!')) {
      return _r('archive', 'rar', ext);
    }
    // GZIP
    if (startsWith([0x1F, 0x8B])) {
      return _r('archive', 'gz', ext);
    }
    // ZIP 系（含 MC 的 mcworld/mcpack/mcaddon，本质都是 zip）
    if (startsWith([0x50, 0x4B, 0x03, 0x04])) {
      if (_extType[ext] == 'minecraft') {
        return _r('minecraft', ext, ext);
      }
      return _r('archive', ext.isEmpty ? 'zip' : ext, ext);
    }
    // ID3 → MP3
    if (asciiAt(0, 'ID3')) {
      return _r('audio', 'mp3', ext);
    }
    // MP3 帧同步
    if (b.length >= 2 &&
        b[0] == 0xFF &&
        (b[1] == 0xFB || b[1] == 0xF3 || b[1] == 0xFA || b[1] == 0xF2)) {
      return _r('audio', 'mp3', ext);
    }
    // FLAC
    if (asciiAt(0, 'fLaC')) {
      return _r('audio', 'flac', ext);
    }
    // OGG
    if (asciiAt(0, 'OggS')) {
      return _r('audio', 'ogg', ext);
    }
    // RIFF：WAVE / WEBP
    if (asciiAt(0, 'RIFF')) {
      if (asciiAt(8, 'WAVE')) return _r('audio', 'wav', ext);
      if (asciiAt(8, 'WEBP')) return _r('image', 'webp', ext);
    }
    // ftyp：MP4 / MOV / 3gp 等
    if (asciiAt(4, 'ftyp')) {
      // 8 字节处的品牌码，qt 是 mov
      if (asciiAt(8, 'qt')) return _r('video', 'mov', ext);
      return _r('video', ext.isEmpty ? 'mp4' : ext, ext);
    }
    return null;
  }

  static DetectedFormat _r(String type, String resolvedExt, String rawExt) {
    // 扩展名和真实内容一致时保留扩展名，否则以魔数判断为准
    final rawType = _compoundType[rawExt] ?? _extType[rawExt];
    final format = rawExt.isNotEmpty && rawType == type ? rawExt : resolvedExt;
    return DetectedFormat(
      typeKey: type,
      typeLabel: _typeLabels[type] ?? '未知类型',
      formatExt: format,
      byMagic: true,
    );
  }

  // ── 扩展名 → 类型键 ──
  static const Map<String, String> _extType = {
    // 图像
    'jpg': 'image', 'jpeg': 'image', 'jpe': 'image', 'jfif': 'image',
    'png': 'image', 'apng': 'image', 'gif': 'image', 'bmp': 'image',
    'dib': 'image', 'webp': 'image', 'svg': 'image', 'ico': 'image',
    'heic': 'image', 'heif': 'image', 'avif': 'image',
    'tiff': 'image', 'tif': 'image', 'hdr': 'image', 'exr': 'image',
    // 音频
    'mp3': 'audio', 'wav': 'audio', 'wave': 'audio', 'flac': 'audio',
    'aac': 'audio', 'm4a': 'audio', 'ogg': 'audio', 'oga': 'audio',
    'opus': 'audio', 'mid': 'audio', 'midi': 'audio', 'wma': 'audio',
    'amr': 'audio', 'ncm': 'audio', 'kgm': 'audio', 'kgma': 'audio',
    'qmc': 'audio', 'qmc0': 'audio', 'qmc3': 'audio', 'qmcflac': 'audio',
    'qmcogg': 'audio',
    // 视频
    'mp4': 'video', 'm4v': 'video', 'avi': 'video', 'mkv': 'video',
    'mov': 'video', 'webm': 'video', 'flv': 'video', 'wmv': 'video',
    '3gp': 'video', 'ts': 'video',
    // 电子书
    'epub': 'ebook', 'mobi': 'ebook', 'prc': 'ebook', 'azw': 'ebook',
    'azw3': 'ebook',
    // 文档
    'doc': 'document', 'docx': 'document', 'md': 'document',
    'markdown': 'document', 'rtf': 'document', 'htm': 'document',
    // 幻灯片
    'ppt': 'slides', 'pptx': 'slides', 'odp': 'slides',
    // 表格
    'xls': 'spreadsheet', 'xlsx': 'spreadsheet', 'csv': 'spreadsheet',
    'tsv': 'spreadsheet',
    // 字体
    'ttf': 'font', 'otf': 'font', 'woff': 'font', 'woff2': 'font',
    'ufo': 'font',
    // 调色板
    'ase': 'palette', 'aco': 'palette', 'gpl': 'palette',
    // 3D 模型
    'obj': 'model3d', 'fbx': 'model3d', 'stl': 'model3d',
    'gltf': 'model3d', 'glb': 'model3d',
    // 纹理
    'dds': 'texture', 'astc': 'texture', 'ktx': 'texture',
    'ktx2': 'texture', 'xnb': 'texture', 'tga': 'texture',
    // 网格
    'ply': 'mesh', 'off': 'mesh',
    // 哈希（结果文件）
    'md5': 'hash', 'sha': 'hash', 'sha1': 'hash', 'sha256': 'hash',
    'sha512': 'hash', 'crc': 'hash', 'b64': 'hash', 'base64': 'hash',
    // 绣花
    'pes': 'embroidery', 'dst': 'embroidery', 'jef': 'embroidery',
    // GPS
    'gpx': 'gps', 'kml': 'gps', 'tcx': 'gps', 'geojson': 'gps',
    // 字幕
    'srt': 'subtitle', 'ass': 'subtitle', 'ssa': 'subtitle',
    'vtt': 'subtitle', 'lrc': 'subtitle',
    // 播放列表
    'm3u': 'playlist', 'm3u8': 'playlist', 'cue': 'playlist',
    // 压缩包
    'zip': 'archive', 'rar': 'archive', '7z': 'archive',
    'tar': 'archive', 'gz': 'archive', 'bz2': 'archive', 'xz': 'archive',
    // 文本类兜底（PDF / TXT / JSON / XML / HTML 已在对应分类）
    'pdf': 'document', 'txt': 'document', 'json': 'spreadsheet',
    'xml': 'spreadsheet', 'html': 'document',
    // 我的世界
    'mcworld': 'minecraft', 'mcpack': 'minecraft', 'mcaddon': 'minecraft',
    'schematic': 'minecraft', 'schem': 'minecraft', 'nbt': 'minecraft',
    'mcfunction': 'minecraft', 'mca': 'minecraft',
  };

  /// 复合扩展名 → 类型（_extension 已返回 tar.gz 这种两段形式）
  static const Map<String, String> _compoundType = {
    'tar.gz': 'archive', 'tar.bz2': 'archive', 'tar.xz': 'archive',
    'geo.json': 'model3d',
  };

  static const Map<String, String> _typeLabels = {
    'image': '图像',
    'audio': '音频',
    'video': '视频',
    'ebook': '电子书',
    'document': '文档',
    'slides': '幻灯片',
    'spreadsheet': '表格',
    'font': '字体',
    'palette': '调色板',
    'model3d': '3D 模型',
    'texture': '纹理',
    'mesh': '网格',
    'hash': '哈希计算',
    'embroidery': '绣花',
    'gps': 'GPS',
    'subtitle': '字幕',
    'playlist': '播放列表',
    'archive': '压缩包',
    'minecraft': '我的世界专区',
  };
}
