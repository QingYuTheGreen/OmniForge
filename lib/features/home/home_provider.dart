import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ── 文件状态 ──
enum FileStatus { processing, completed, failed }

class FileItem {
  final String name;
  final String path;
  final FileStatus status;
  final double progress;
  final String? outputPath;

  const FileItem({
    required this.name,
    required this.path,
    required this.status,
    this.progress = 0,
    this.outputPath,
  });

  FileItem copyWith({
    FileStatus? status,
    double? progress,
    String? outputPath,
  }) {
    return FileItem(
      name: name,
      path: path,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      outputPath: outputPath ?? this.outputPath,
    );
  }
}

// ── 选项模型 ──
class FormatOption {
  final String label;
  final String value;
  final String? category;
  const FormatOption({required this.label, required this.value, this.category});
}

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
  int _processingIndex = -1;

  HomeNotifier() : super(const HomeState()) {
    // 预置示例
    state = state.copyWith(files: [
      const FileItem(
        name: 'demo_video.mp4',
        path: '/mock/demo_video.mp4',
        status: FileStatus.completed,
        outputPath: '/mock/demo_video.gif',
      ),
    ]);
  }

  void switchTab(int index) => state = state.copyWith(currentTab: index);

  // 添加新文件并开始模拟转换
  void startConvert(String filePath) {
    final fileName = filePath.split('/').last;
    final newFile = FileItem(
      name: fileName,
      path: filePath,
      status: FileStatus.processing,
      progress: 0,
    );

    state = state.copyWith(
      files: [newFile, ...state.files],
      currentTab: 1, // 跳到文件 Tab
    );

    _processingIndex = 0;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      final updated = List<FileItem>.from(state.files);
      final newProgress = updated[_processingIndex].progress + 0.02;

      if (newProgress >= 1.0) {
        updated[_processingIndex] = updated[_processingIndex].copyWith(
          status: FileStatus.completed,
          progress: 1.0,
          outputPath: filePath.replaceAll(RegExp(r'\.[^\.]+$'), '_output.gif'),
        );
        timer.cancel();
        _processingIndex = -1;
      } else {
        updated[_processingIndex] = updated[_processingIndex].copyWith(progress: newProgress);
      }

      state = state.copyWith(files: updated);
    });
  }

  void cancelConvert(int index) {
    _timer?.cancel();
    _processingIndex = -1;
    final updated = List<FileItem>.from(state.files);
    updated.removeAt(index);
    state = state.copyWith(files: updated);
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

// ── 配置选项数据 ──
final inputTypeOptions = [
  const FormatOption(label: '图像', value: 'image'),
  const FormatOption(label: '音频', value: 'audio'),
  const FormatOption(label: '视频', value: 'video'),
  const FormatOption(label: '文档', value: 'document'),
  const FormatOption(label: '我的世界 JAVA 存档', value: 'mc_java', category: '我的世界'),
  const FormatOption(label: '我的世界基岩版存档', value: 'mc_bedrock', category: '我的世界'),
];

final inputFormatOptions = [
  const FormatOption(label: '.mp4', value: 'mp4'),
  const FormatOption(label: '.mp3', value: 'mp3'),
  const FormatOption(label: '.jpg / .jpeg', value: 'jpg'),
  const FormatOption(label: '.wav', value: 'wav'),
  const FormatOption(label: '.mcworld', value: 'mcworld'),
  const FormatOption(label: '.zip', value: 'zip'),
];

final outputTypeOptions = [
  const FormatOption(label: '图像', value: 'image'),
  const FormatOption(label: '音频', value: 'audio'),
  const FormatOption(label: '视频', value: 'video'),
  const FormatOption(label: '我的世界', value: 'mc'),
];

final outputFormatOptions = [
  const FormatOption(label: '.gif', value: 'gif'),
  const FormatOption(label: '.mp3', value: 'mp3'),
  const FormatOption(label: '.mid', value: 'midi'),
  const FormatOption(label: '.mcaddon', value: 'mcaddon'),
];

// MC 版本
final mcVersions = ['1.21.4', '1.21.1', '1.20.6', '1.20.1', '1.19.4', '1.18.2'];
