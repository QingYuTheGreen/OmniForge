import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../utils/output_paths.dart';

// ── 文件状态 ──
enum FileStatus { processing, completed, failed }

class FileItem {
  final String name;
  final String path;
  final FileStatus status;
  final double progress;
  final String? outputPath;
  final String? error;

  const FileItem({
    required this.name,
    required this.path,
    required this.status,
    this.progress = 0,
    this.outputPath,
    this.error,
  });

  FileItem copyWith({
    FileStatus? status,
    double? progress,
    String? outputPath,
    String? error,
  }) {
    return FileItem(
      name: name,
      path: path,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      outputPath: outputPath ?? this.outputPath,
      error: error ?? this.error,
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

  HomeNotifier() : super(const HomeState());

  void switchTab(int index) => state = state.copyWith(currentTab: index);

  /// 从其他应用分享/打开进来的文件：直接进文件列表并开始处理
  void addExternalFile(String filePath) {
    final name = filePath.split(Platform.pathSeparator).last;
    final item = FileItem(
      name: name,
      path: filePath,
      status: FileStatus.processing,
    );
    state = state.copyWith(
      files: [item, ...state.files],
      currentTab: 1,
    );
    _runProcess(0, filePath, null);
  }

  /// 开始处理（当前为模拟进度，真实转换引擎后续接入）
  void startConvert(String filePath, {String? outputExt}) {
    final name = filePath.split(Platform.pathSeparator).last;
    final item = FileItem(
      name: name,
      path: filePath,
      status: FileStatus.processing,
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

// ═══════════════════════════════════════
// 类型 → 格式 级联数据
// ═══════════════════════════════════════

final inputTypeOptions = [
  const FormatOption(label: '图像', value: 'image'),
  const FormatOption(label: '音频', value: 'audio'),
  const FormatOption(label: '视频', value: 'video'),
  const FormatOption(label: '文档', value: 'document'),
  const FormatOption(label: '压缩包', value: 'archive'),
  const FormatOption(label: '我的世界 JAVA 存档', value: 'mc_java', category: '我的世界'),
  const FormatOption(label: '我的世界基岩版存档', value: 'mc_bedrock', category: '我的世界'),
];

final outputTypeOptions = [
  const FormatOption(label: '图像', value: 'image'),
  const FormatOption(label: '音频', value: 'audio'),
  const FormatOption(label: '视频', value: 'video'),
  const FormatOption(label: '文档', value: 'document'),
  const FormatOption(label: '压缩包', value: 'archive'),
  const FormatOption(label: '我的世界', value: 'mc', category: '我的世界'),
];

final Map<String, List<FormatOption>> inputFormatsByType = {
  'image': const [
    FormatOption(label: '.jpg / .jpeg', value: 'jpg'),
    FormatOption(label: '.png', value: 'png'),
    FormatOption(label: '.gif', value: 'gif'),
    FormatOption(label: '.bmp', value: 'bmp'),
    FormatOption(label: '.webp', value: 'webp'),
    FormatOption(label: '.svg', value: 'svg'),
    FormatOption(label: '.ico', value: 'ico'),
    FormatOption(label: '.heic', value: 'heic'),
  ],
  'audio': const [
    FormatOption(label: '.mp3', value: 'mp3'),
    FormatOption(label: '.wav', value: 'wav'),
    FormatOption(label: '.flac', value: 'flac'),
    FormatOption(label: '.aac', value: 'aac'),
    FormatOption(label: '.ogg', value: 'ogg'),
    FormatOption(label: '.m4a', value: 'm4a'),
    FormatOption(label: '.mid / .midi', value: 'midi'),
  ],
  'video': const [
    FormatOption(label: '.mp4', value: 'mp4'),
    FormatOption(label: '.avi', value: 'avi'),
    FormatOption(label: '.mkv', value: 'mkv'),
    FormatOption(label: '.mov', value: 'mov'),
    FormatOption(label: '.webm', value: 'webm'),
    FormatOption(label: '.flv', value: 'flv'),
    FormatOption(label: '.gif', value: 'gif'),
  ],
  'document': const [
    FormatOption(label: '.pdf', value: 'pdf'),
    FormatOption(label: '.doc / .docx', value: 'docx'),
    FormatOption(label: '.txt', value: 'txt'),
    FormatOption(label: '.md', value: 'md'),
    FormatOption(label: '.epub', value: 'epub'),
  ],
  'archive': const [
    FormatOption(label: '.zip', value: 'zip'),
    FormatOption(label: '.rar', value: 'rar'),
    FormatOption(label: '.7z', value: '7z'),
    FormatOption(label: '.tar', value: 'tar'),
    FormatOption(label: '.gz', value: 'gz'),
  ],
  'mc_java': const [
    FormatOption(label: '.mcworld', value: 'mcworld'),
    FormatOption(label: '.zip', value: 'zip'),
  ],
  'mc_bedrock': const [
    FormatOption(label: '.mcworld', value: 'mcworld'),
    FormatOption(label: '.mcaddon', value: 'mcaddon'),
    FormatOption(label: '.mcpack', value: 'mcpack'),
  ],
};

final Map<String, List<FormatOption>> outputFormatsByType = {
  'image': const [
    FormatOption(label: '.png', value: 'png'),
    FormatOption(label: '.jpg', value: 'jpg'),
    FormatOption(label: '.gif', value: 'gif'),
    FormatOption(label: '.bmp', value: 'bmp'),
    FormatOption(label: '.webp', value: 'webp'),
    FormatOption(label: '.ico', value: 'ico'),
  ],
  'audio': const [
    FormatOption(label: '.mp3', value: 'mp3'),
    FormatOption(label: '.wav', value: 'wav'),
    FormatOption(label: '.flac', value: 'flac'),
    FormatOption(label: '.ogg', value: 'ogg'),
    FormatOption(label: '.mid', value: 'midi'),
  ],
  'video': const [
    FormatOption(label: '.mp4', value: 'mp4'),
    FormatOption(label: '.mkv', value: 'mkv'),
    FormatOption(label: '.webm', value: 'webm'),
    FormatOption(label: '.mov', value: 'mov'),
    FormatOption(label: '.gif', value: 'gif'),
  ],
  'document': const [
    FormatOption(label: '.pdf', value: 'pdf'),
    FormatOption(label: '.txt', value: 'txt'),
    FormatOption(label: '.docx', value: 'docx'),
    FormatOption(label: '.epub', value: 'epub'),
  ],
  'archive': const [
    FormatOption(label: '.zip', value: 'zip'),
    FormatOption(label: '.7z', value: '7z'),
    FormatOption(label: '.tar.gz', value: 'tar.gz'),
  ],
  'mc': const [
    FormatOption(label: '.mcaddon', value: 'mcaddon'),
    FormatOption(label: '.mcpack', value: 'mcpack'),
    FormatOption(label: '.mcworld', value: 'mcworld'),
  ],
};

// 我的世界版本
final mcVersions = ['1.21.4', '1.21.1', '1.20.6', '1.20.1', '1.19.4', '1.18.2'];
