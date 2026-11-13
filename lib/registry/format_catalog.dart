import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/format_node.dart';
import 'registry_manager.dart';

/// UI 侧的一个可选项（类型或格式都用它）
class FormatOption {
  /// 显示文案：类型是「图像」，格式是「.jpg / .jpeg」
  final String label;

  /// 类型 = 分类键（image），格式 = 格式 id（jpg）
  final String value;

  /// 输出时使用的扩展名（不含点，可能是 tar.gz 这种多段）
  final String ext;

  /// 副标题（格式项用来显示所属类型）
  final String? category;

  /// 该格式的全部扩展名别名（不含点，小写）
  final List<String> extensions;

  /// 引擎是否还没接入（空壳）
  final bool planned;

  /// 备注（如「本质是 zip」）
  final String? note;

  const FormatOption({
    required this.label,
    required this.value,
    this.ext = '',
    this.category,
    this.extensions = const [],
    this.planned = false,
    this.note,
  });
}

/// 由 formats.yaml 生成的完整级联表（19 类 / 全部格式）
class FormatCatalog {
  /// 全部类型（分类），按 yaml 里的 order
  final List<FormatOption> types;

  /// 分类键 → 该分类下的全部格式
  final Map<String, List<FormatOption>> formatsByType;

  /// 分类键 → 分类信息
  final Map<String, FormatCategory> categories;

  /// 是否为空壳阶段
  final bool shellStage;

  const FormatCatalog({
    required this.types,
    required this.formatsByType,
    required this.categories,
    this.shellStage = true,
  });

  factory FormatCatalog.fromRegistry() {
    final registry = RegistryManager();
    final cats = registry.getCategories();

    final types = <FormatOption>[];
    final byType = <String, List<FormatOption>>{};
    final catMap = <String, FormatCategory>{};

    for (final c in cats) {
      catMap[c.key] = c;
      types.add(FormatOption(
        label: c.name,
        value: c.key,
        category: null,
      ));

      final list = <FormatOption>[];
      for (final f in registry.getFormatsByCategory(c.key)) {
        final exts = f.extensions
            .map((e) => e.startsWith('.') ? e.substring(1) : e)
            .toList();
        list.add(FormatOption(
          label: f.extensions.isEmpty
              ? f.name
              : f.extensions.map((e) => e.startsWith('.') ? e : '.$e').join(' / '),
          value: f.id,
          ext: exts.isEmpty ? '' : exts.first,
          category: c.name,
          extensions: exts,
          planned: f.isPlanned,
          note: f.note,
        ));
      }
      byType[c.key] = list;
    }

    return FormatCatalog(
      types: List.unmodifiable(types),
      formatsByType: Map.unmodifiable(byType),
      categories: Map.unmodifiable(catMap),
      shellStage: registry.isShellStage,
    );
  }

  /// 分类键 → 类型选项（识别结果预填用）
  FormatOption? typeOf(String key) {
    for (final t in types) {
      if (t.value == key) return t;
    }
    return null;
  }

  /// 某分类下的格式
  List<FormatOption> formatsOf(String typeKey) =>
      formatsByType[typeKey] ?? const [];

  /// 格式总数（跨类共享的格式在每个分类里都算，这里统计不重复的 id）
  int get uniqueFormatCount {
    final ids = <String>{};
    for (final list in formatsByType.values) {
      for (final o in list) {
        ids.add(o.value);
      }
    }
    return ids.length;
  }

  /// 按扩展名在该分类里找格式项（tif/tiff、jpeg/jpg 这类别名都能命中）
  FormatOption? formatByExt(String typeKey, String ext) {
    final e = ext.toLowerCase();
    for (final o in formatsOf(typeKey)) {
      if (o.extensions.contains(e)) return o;
    }
    return null;
  }
}

/// 分类图标（Material 图标，yaml 里存的是名字）
IconData categoryIcon(String key) => _categoryIcons[key] ?? Icons.insert_drive_file;

const Map<String, IconData> _categoryIcons = {
  'image': Icons.photo_outlined,
  'audio': Icons.audiotrack_outlined,
  'video': Icons.movie_outlined,
  'ebook': Icons.menu_book_outlined,
  'document': Icons.description_outlined,
  'slides': Icons.slideshow_outlined,
  'spreadsheet': Icons.table_chart_outlined,
  'font': Icons.font_download_outlined,
  'palette': Icons.palette_outlined,
  'model3d': Icons.view_in_ar_outlined,
  'texture': Icons.texture_outlined,
  'mesh': Icons.grid_on_outlined,
  'hash': Icons.tag_outlined,
  'embroidery': Icons.gesture_outlined,
  'gps': Icons.place_outlined,
  'subtitle': Icons.subtitles_outlined,
  'playlist': Icons.queue_music_outlined,
  'archive': Icons.folder_zip_outlined,
  'minecraft': Icons.extension_outlined,
};

/// 全局唯一的格式目录（RegistryManager 初始化后即可读取）
final formatCatalogProvider =
    Provider<FormatCatalog>((ref) => FormatCatalog.fromRegistry());
