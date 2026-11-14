import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/conversion_planner.dart';
import '../../engine/engine_providers.dart';
import '../../engine/i_engine.dart';
import '../../registry/registry_manager.dart';
import '../../utils/file_type_detector.dart';
import '../../utils/output_paths.dart';

// FormatOption / 格式目录统一定义在 registry/format_catalog.dart，这里转出，
// 让原本 import home_provider 的地方继续能用。
export '../../registry/format_catalog.dart'
    show FormatOption, FormatCatalog, formatCatalogProvider, categoryIcon;

// ── 文件状态 ──
enum FileStatus { processing, completed, failed }

class FileItem {
  final String name;
  final String path;
  final FileStatus status;
  final double progress;
  final String? outputPath;
  final String? error;

  /// 自动识别出的类型中文名（如「图像」），未识别为 null
  final String? detectedType;

  /// 自动识别出的格式扩展名（如 png），未识别为 null
  final String? detectedFormat;

  /// 目标格式 id（如 exif 中取到的 jpg → pdf）
  final String? targetFormat;

  /// 本次转换使用的参数（重试时复用）
  final Map<String, dynamic> params;

  /// 进度提示文字
  final String message;

  const FileItem({
    required this.name,
    required this.path,
    required this.status,
    this.progress = 0,
    this.outputPath,
    this.error,
    this.detectedType,
    this.detectedFormat,
    this.targetFormat,
    this.params = const {},
    this.message = '',
  });

  FileItem copyWith({
    FileStatus? status,
    double? progress,
    String? outputPath,
    String? error,
    String? detectedType,
    String? detectedFormat,
    String? targetFormat,
    Map<String, dynamic>? params,
    String? message,
  }) {
    return FileItem(
      name: name,
      path: path,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      outputPath: outputPath ?? this.outputPath,
      error: error ?? this.error,
      detectedType: detectedType ?? this.detectedType,
      detectedFormat: detectedFormat ?? this.detectedFormat,
      targetFormat: targetFormat ?? this.targetFormat,
      params: params ?? this.params,
      message: message ?? this.message,
    );
  }
}

/// 其他应用分享/打开进来的文件路径：main 写入，HomePage 监听后打开转换配置页
/// （而不是直接开始转换）。处理完置回 null。
final incomingFileProvider = StateProvider<String?>((ref) => null);

// ── 主状态 ──
class HomeState {
  final int currentTab;
  final List<FileItem> files;

  const HomeState({
    this.currentTab = 0,
    this.files = const [],
  });

  HomeState copyWith({
    int? currentTab,
    List<FileItem>? files,
  }) {
    return HomeState(
      currentTab: currentTab ?? this.currentTab,
      files: files ?? this.files,
    );
  }
}

// ── Notifier ──
class HomeNotifier extends StateNotifier<HomeState> {
  HomeNotifier(this._ref) : super(const HomeState());

  final Ref _ref;
  final Map<int, CancelToken> _tokens = {};

  void switchTab(int index) => state = state.copyWith(currentTab: index);

  /// 源格式 id（根据扩展名 / 文件头推断），推断失败返回 null。
  String? sourceFormatId(String filePath, String? detectedExt) {
    final manager = RegistryManager();
    if (detectedExt != null && detectedExt.isNotEmpty) {
      final byExt = manager.getFormatByExtension(detectedExt);
      if (byExt != null) return byExt.id;
    }
    final dot = filePath.lastIndexOf('.');
    if (dot >= 0) {
      final byExt = manager.getFormatByExtension(
        filePath.substring(dot + 1).toLowerCase(),
      );
      if (byExt != null) return byExt.id;
    }
    return null;
  }

  /// 开始真实转换。
  ///
  /// [outputFormat] 为目标格式 id（来自 ConversionPlanner.reachableFrom）；
  /// 为空时自动选择第一个可用的目标格式。
  Future<void> startConvert(
    String filePath, {
    String? outputFormat,
    Map<String, dynamic> params = const {},
  }) async {
    final name = filePath.split(Platform.pathSeparator).last;

    // 自动识别（文件头魔数 + 扩展名），读不到文件时内部会降级
    final detected = await FileTypeDetector.detect(filePath);
    final sourceId = sourceFormatId(
      filePath,
      detected.formatExt.isEmpty ? null : detected.formatExt,
    );

    final item = FileItem(
      name: name,
      path: filePath,
      status: FileStatus.processing,
      detectedType: detected.isKnown ? detected.typeLabel : null,
      detectedFormat: detected.formatExt.isEmpty ? null : detected.formatExt,
      targetFormat: outputFormat,
      params: Map<String, dynamic>.from(params),
    );

    state = state.copyWith(files: [item, ...state.files], currentTab: 1);

    if (sourceId == null) {
      _fail(0, '无法识别输入格式，暂不支持该文件');
      return;
    }

    final planner = _ref.read(conversionPlannerProvider);
    final targets = planner.reachableFrom(sourceId);
    final available = targets.where((t) => t.available).toList();
    final targetId = outputFormat ?? (available.isEmpty ? null : available.first.formatId);
    if (targetId == null) {
      _fail(0, _unsupportedMessage(sourceId, targets));
      return;
    }

    final plan = planner.plan(sourceId, targetId, params: params);
    if (plan == null || plan.isEmpty) {
      _fail(0, '没有从 $sourceId 到 $targetId 的转换链路');
      return;
    }

    final ext = _planExtension(plan, targetId);
    final outputPath = await OutputPaths.buildOutputPath(name, ext);

    final updated = state.files[0].copyWith(
      targetFormat: targetId,
      params: Map<String, dynamic>.from(plan.steps.first.params),
    );
    state = state.copyWith(files: [updated, ...state.files.skip(1)]);

    _run(0, plan, filePath, outputPath);
  }

  void _run(
    int index,
    ConversionPlan plan,
    String inputPath,
    String outputPath,
  ) {
    final token = CancelToken();
    _tokens[index] = token;
    final service = _ref.read(conversionServiceProvider);

    service
        .convert(
          plan: plan,
          inputPath: inputPath,
          outputPath: outputPath,
          cancelToken: token,
        )
        .listen((event) {
          _update(index, (item) {
            switch (event) {
              case Progress():
                return item.copyWith(
                  progress: event.percent.clamp(0.0, 0.99),
                  message: event.message,
                );
              case Success():
                return item.copyWith(
                  status: FileStatus.completed,
                  progress: 1.0,
                  outputPath: event.outputPath,
                  message: '完成',
                );
              case Error():
                return item.copyWith(
                  status: FileStatus.failed,
                  error: event.message,
                );
              case PluginRequired():
                final note = event.note;
                return item.copyWith(
                  status: FileStatus.failed,
                  error: '需要插件 ${event.pluginId}'
                      '${event.sizeMb > 0 ? '（约 ${event.sizeMb} MB）' : ''}'
                      '${note != null ? '：$note' : ''}',
                );
            }
          });
        })
        .onDone(() {
          _tokens.remove(index);
        });
  }

  void _update(int index, FileItem Function(FileItem item) transform) {
    final list = List<FileItem>.from(state.files);
    if (index >= list.length) return;
    list[index] = transform(list[index]);
    state = state.copyWith(files: list);
  }

  void _fail(int index, String message) {
    _update(index, (item) => item.copyWith(
          status: FileStatus.failed,
          progress: 0,
          error: message,
        ));
  }

  String _planExtension(ConversionPlan plan, String targetId) {
    for (final step in plan.steps.reversed) {
      if (step.toExtension.isNotEmpty) return step.toExtension;
    }
    final format = RegistryManager().getFormatById(targetId);
    if (format != null && format.extensions.isNotEmpty) {
      return format.extensions.first.replaceFirst('.', '');
    }
    return targetId;
  }

  String _unsupportedMessage(String sourceId, List<ReachableTarget> targets) {
    final blocked = targets.where((t) => !t.available).toList();
    if (blocked.isEmpty) return '暂不支持从 $sourceId 转换为其它格式';
    final plugin = blocked.first.blockedPluginId;
    return '暂无可用的转换目标；部分目标需要插件 ${plugin ?? '未知'}';
  }

  void cancelConvert(int index) {
    _tokens[index]?.cancel();
    _tokens.remove(index);
    final list = List<FileItem>.from(state.files);
    if (index < list.length) list.removeAt(index);
    state = state.copyWith(files: list);
  }

  void retryConvert(int index) {
    if (index >= state.files.length) return;
    final file = state.files[index];
    final list = List<FileItem>.from(state.files);
    list.removeAt(index);
    state = state.copyWith(files: list);
    startConvert(
      file.path,
      outputFormat: file.targetFormat,
      params: file.params,
    );
  }

  void removeFile(int index) {
    final list = List<FileItem>.from(state.files);
    if (index < list.length) list.removeAt(index);
    state = state.copyWith(files: list);
  }

  @override
  void dispose() {
    for (final token in _tokens.values) {
      token.cancel();
    }
    _tokens.clear();
    super.dispose();
  }
}

final homeProvider = StateNotifierProvider<HomeNotifier, HomeState>((ref) {
  return HomeNotifier(ref);
});
