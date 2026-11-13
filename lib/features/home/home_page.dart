import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'home_provider.dart';
import 'config_page.dart';
import '../settings/settings_page.dart';
import '../settings/settings_provider.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  bool _picking = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(homeProvider);
    final notifier = ref.read(homeProvider.notifier);
    final settings = ref.watch(settingsProvider);

    // 其他应用分享/打开进来的文件 → 打开转换配置页（不直接转换）
    ref.listen<String?>(incomingFileProvider, (prev, next) => _handleIncoming(next));
    final pending = ref.read(incomingFileProvider);
    if (pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _handleIncoming(pending));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('OmniForge'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsPage()),
            ),
          ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          final isConvert = (child.key as ValueKey<String>?)?.value == 'convert';
          final begin = Offset(isConvert ? -0.15 : 0.15, 0);
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position:
                  Tween<Offset>(begin: begin, end: Offset.zero).animate(animation),
              child: child,
            ),
          );
        },
        child: state.currentTab == 0
            ? _buildConvertTab(key: const ValueKey('convert'))
            : _buildFilesTab(state, notifier, settings, key: const ValueKey('files')),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: state.currentTab,
        onDestinationSelected: notifier.switchTab,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.swap_horiz), label: '转换'),
          NavigationDestination(icon: Icon(Icons.folder_outlined), label: '文件'),
        ],
      ),
    );
  }

  /// 处理外来文件：幂等，先消费（置 null）再打开配置页，防止重复跳转
  void _handleIncoming(String? path) {
    if (path == null || !mounted) return;
    if (ref.read(incomingFileProvider) != path) return;
    ref.read(incomingFileProvider.notifier).state = null;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ConfigPage(initialFilePath: path)),
    );
  }

  // ── 转换 Tab ──
  Widget _buildConvertTab({Key? key}) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      key: key,
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: cs.outlineVariant, width: 2),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: _picking ? null : _pickFile,
          child: SizedBox(
            width: 320,
            height: 240,
            child: Center(
              child: _picking
                  ? const CircularProgressIndicator()
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.folder_open_outlined, size: 56, color: cs.primary),
                        const SizedBox(height: 16),
                        const Text('打开文件',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Text('点击选择要转换的文件',
                            style: TextStyle(color: cs.onSurfaceVariant)),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  /// 不指定 type，避免安卓按 MIME 过滤导致部分文件选不到
  Future<void> _pickFile() async {
    setState(() => _picking = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: false,
      );
      final path = result?.files.single.path;
      if (path == null || !mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ConfigPage(initialFilePath: path)),
      );
    } catch (e) {
      _toast('选择文件失败：$e');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  // ── 文件 Tab ──
  Widget _buildFilesTab(HomeState state, HomeNotifier notifier,
      SettingsState settings, {Key? key}) {
    if (state.files.isEmpty) {
      return Center(
        key: key,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_off_outlined,
                size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            const Text('还没有文件，去转换页选一个吧'),
          ],
        ),
      );
    }

    return ListView.builder(
      key: key,
      padding: const EdgeInsets.all(16),
      itemCount: state.files.length,
      itemBuilder: (_, i) => _buildCard(state.files[i], i, notifier, settings),
    );
  }

  Widget _buildCard(FileItem file, int index, HomeNotifier notifier,
      SettingsState settings) {
    final cs = Theme.of(context).colorScheme;
    final nameStyle = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.bold,
      color: cs.onSurface,
    );

    switch (file.status) {
      case FileStatus.processing:
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.movie_outlined, size: 20, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(file.name,
                        style: nameStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  TextButton(
                    onPressed: () => notifier.cancelConvert(index),
                    child: const Text('取消'),
                  ),
                ]),
                const SizedBox(height: 10),
                if (file.detectedType != null || file.detectedFormat != null)
                  _detectChip(cs, file),
                const SizedBox(height: 12),
                LinearProgressIndicator(value: file.progress),
                const SizedBox(height: 6),
                Text('${(file.progress * 100).toInt()}%',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        );

      case FileStatus.completed:
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.check_circle_outline,
                      size: 20, color: Colors.green),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      file.name,
                      style: nameStyle,
                      maxLines: settings.fileNameDisplay ==
                              FileNameDisplay.multiline
                          ? 3
                          : 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                if (file.detectedType != null || file.detectedFormat != null)
                  _detectChip(cs, file),
                const SizedBox(height: 8),
                Text(
                  file.outputPath ?? '',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.share_outlined, size: 18),
                      label: const Text('分享'),
                      onPressed: () => _share(file),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('打开'),
                      onPressed: () => _open(file),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.info_outline, size: 18),
                      label: const Text('详细信息'),
                      onPressed: () => _detail(file),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );

      case FileStatus.failed:
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.error_outline, size: 20, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(file.name,
                        style: nameStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  TextButton(
                    onPressed: () => notifier.retryConvert(index),
                    child: const Text('重试'),
                  ),
                ]),
                const SizedBox(height: 8),
                Text(file.error ?? '未知错误',
                    style: const TextStyle(fontSize: 12, color: Colors.red)),
              ],
            ),
          ),
        );
    }

    // 枚举已全覆盖，这里只是兜底，保证函数一定 return
    return const SizedBox.shrink();
  }

  /// 自动识别结果的小标签：类型 + 格式
  Widget _detectChip(ColorScheme cs, FileItem file) {
    final text = [
      if (file.detectedType != null) file.detectedType,
      if (file.detectedFormat != null) '.${file.detectedFormat}',
    ].join(' ');

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: cs.secondaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome, size: 13, color: cs.onSecondaryContainer),
            const SizedBox(width: 5),
            Text(text,
                style: TextStyle(
                    fontSize: 12, color: cs.onSecondaryContainer)),
          ],
        ),
      ),
    );
  }

  // ── 分享 ──
  Future<void> _share(FileItem file) async {
    final path = file.outputPath;
    if (path == null || !File(path).existsSync()) {
      _toast('文件不存在，无法分享');
      return;
    }
    try {
      // share_plus 适配版（10.1.1 仍为 Share.shareXFiles 静态 API，自带 ohos 实现）
      await Share.shareXFiles([XFile(path)], text: file.name);
    } catch (e) {
      _toast('分享失败：$e');
    }
  }

  // ── 打开 ──
  Future<void> _open(FileItem file) async {
    final path = file.outputPath;
    if (path == null || !File(path).existsSync()) {
      _toast('文件不存在，无法打开');
      return;
    }
    try {
      final openPath = await _openablePath(path);
      final result = await OpenFilex.open(openPath);
      if (result.type != ResultType.done) {
        _toast('没有能打开该文件的应用（${result.message}）');
      }
    } catch (e) {
      _toast('打开失败：$e');
    }
  }

  /// 安卓上先把公共目录里的文件复制一份到应用缓存，再交给系统打开。
  ///
  /// open_filex 的安卓实现会判断文件路径是否落在应用沙箱内；我们的输出在
  /// /storage/emulated/0/OmniForge/ 这种公共目录，它会认为需要
  /// READ_MEDIA_IMAGES / READ_MEDIA_VIDEO 等运行时权限（Android 13+ 弹的就
  /// 是「访问照片和视频」）。但它最终是走 FileProvider 授出 content:// 给目标
  /// 应用，读取权限由这次授权临时覆盖，根本不需要该权限。
  /// 复制到 cache 后路径在沙箱内，插件直接 startActivity，不再弹窗。
  Future<String> _openablePath(String path) async {
    if (!Platform.isAndroid) return path;
    try {
      final tmp = await getTemporaryDirectory();
      final dir = Directory('${tmp.path}/open');
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      dir.createSync(recursive: true);
      final name = File(path).uri.pathSegments.last;
      final dest = File('${dir.path}/$name');
      await File(path).copy(dest.path);
      return dest.path;
    } catch (_) {
      // 复制失败就退回原路径（可能弹一次权限，但至少能打开）
      return path;
    }
  }

  // ── 详细信息 ──
  void _detail(FileItem file) {
    final path = file.outputPath ?? file.path;
    final f = File(path);
    int? size;
    DateTime? modified;
    try {
      if (f.existsSync()) {
        size = f.lengthSync();
        modified = f.lastModifiedSync();
      }
    } catch (_) {}

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('详细信息'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _row('文件名', file.name),
              _row('原始路径', file.path),
              if (file.outputPath != null) _row('输出路径', file.outputPath!),
              if (size != null) _row('文件大小', _fmtSize(size)),
              if (modified != null) _row('修改时间', _fmtTime(modified)),
              _row('处理状态',
                  file.status == FileStatus.completed ? '已完成' : '失败'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(label,
                style: const TextStyle(fontSize: 13, color: Colors.grey)),
          ),
          Expanded(
              child: SelectableText(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  String _fmtSize(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1024 * 1024 * 1024) {
      return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _fmtTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
