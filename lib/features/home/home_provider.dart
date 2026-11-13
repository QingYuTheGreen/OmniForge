import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../utils/output_paths.dart';
import '../../utils/file_type_detector.dart';

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

  const FileItem({
    required this.name,
    required this.path,
    required this.status,
    this.progress = 0,
    this.outputPath,
    this.error,
    this.detectedType,
    this.detectedFormat,
  });

  FileItem copyWith({
    FileStatus? status,
    double? progress,
    String? outputPath,
    String? error,
    String? detectedType,
    String? detectedFormat,
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
  Timer? _timer;

  HomeNotifier() : super(const HomeState());

  void switchTab(int index) => state = state.copyWith(currentTab: index);

  /// 开始处理（当前为模拟进度，真实转换引擎后续接入）
  Future<void> startConvert(String filePath, {String? outputExt}) {
    return _createAndRun(filePath, outputExt);
  }

  /// 建列表项的统一入口：先自动识别文件类型/格式，再启动处理
  Future<void> _createAndRun(String filePath, String? outputExt) async {
    final name = filePath.split(Platform.pathSeparator).last;

    // 自动识别（文件头魔数 + 扩展名），读不到文件时内部会降级
    final detected = await FileTypeDetector.detect(filePath);

    final item = FileItem(
      name: name,
      path: filePath,
      status: FileStatus.processing,
      detectedType: detected.isKnown ? detected.typeLabel : null,
      detectedFormat: detected.formatExt.isEmpty ? null : detected.formatExt,
    );

    state = state.copyWith(
      files: [item, ...state.files],
      currentTab: 1,
    );
    _runProcess(0, filePath, outputExt);
  }

  void _runProcess(int index, String inputPath, String? outputExt) {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 80), (timer) async {
      final list = List<FileItem>.from(state.files);
      if (index >= list.length) {
        timer.cancel();
        return;
      }

      final next = list[index].progress + 0.02;

      if (next >= 1.0) {
        timer.cancel();
        final ext = outputExt ?? _guessExt(inputPath);
        final outPath = await OutputPaths.buildOutputPath(
          inputPath.split(Platform.pathSeparator).last,
          ext,
        );
        // 生成一个占位空文件，保证「分享 / 打开 / 详细信息」有真实对象可用
        try {
          final f = File(outPath);
          if (!await f.exists()) {
            await f.parent.create(recursive: true);
            await f.writeAsBytes(const []);
          }
        } catch (e) {
          final cur = List<FileItem>.from(state.files);
          if (index < cur.length) {
            cur[index] = cur[index].copyWith(
              status: FileStatus.failed,
              error: '输出失败：$e',
            );
            state = state.copyWith(files: cur);
          }
          return;
        }

        final cur = List<FileItem>.from(state.files);
        if (index < cur.length) {
          cur[index] = cur[index].copyWith(
            status: FileStatus.completed,
            progress: 1.0,
            outputPath: outPath,
          );
          state = state.copyWith(files: cur);
        }
      } else {
        list[index] = list[index].copyWith(progress: next);
        state = state.copyWith(files: list);
      }
    });
  }

  String _guessExt(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) return 'gif';
    return path.substring(dot + 1).toLowerCase();
  }

  void cancelConvert(int index) {
    _timer?.cancel();
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
    startConvert(file.path);
  }

  void removeFile(int index) {
    final list = List<FileItem>.from(state.files);
    if (index < list.length) list.removeAt(index);
    state = state.copyWith(files: list);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final homeProvider = StateNotifierProvider<HomeNotifier, HomeState>((ref) {
  return HomeNotifier();
});
