import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'home_provider.dart';
import 'config_page.dart';
import '../settings/settings_page.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  bool _isPicking = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(homeProvider);
    final notifier = ref.read(homeProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('OmniForge'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SettingsPage()),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: state.currentTab,
        children: [
          _buildConvertTab(context, notifier),
          _buildFilesTab(state, notifier),
        ],
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

  // ── 界面 1：转换 Tab ──
  Widget _buildConvertTab(BuildContext context, HomeNotifier notifier) {
    return Center(
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(
            color: Theme.of(context).colorScheme.outline,
            width: 2,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: _isPicking ? null : _pickFileAndGoConfig,
          child: SizedBox(
            width: 320,
            height: 240,
            child: Center(
              child: _isPicking
                  ? const CircularProgressIndicator()
                  : const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.folder_open_outlined, size: 56, color: Colors.teal),
                        SizedBox(height: 16),
                        Text('打开文件', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        SizedBox(height: 8),
                        Text('点击选择，或拖拽到此处', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  // 真实文件选择 → 跳配置页
  Future<void> _pickFileAndGoConfig() async {
    setState(() => _isPicking = true);

    try {
      final result = await FilePicker.platform.pickFiles();

      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;
        final fileName = result.files.single.name;
        final ext = filePath.split('.').last.toLowerCase();

        if (!mounted) return;

        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => ConfigPage(
              initialFilePath: filePath,
            ),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              const begin = Offset(1.0, 0.0);
              const end = Offset.zero;
              const curve = Curves.easeInOut;
              var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
              return SlideTransition(
                position: animation.drive(tween),
                child: child,
              );
            },
            transitionDuration: const Duration(milliseconds: 300),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选择文件失败：$e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isPicking = false);
      }
    }
  }

  // ── 界面 1：文件 Tab ──
  Widget _buildFilesTab(HomeState state, HomeNotifier notifier) {
    if (state.files.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_off_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('还没有文件，去转换页选一个吧'),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: state.files.length,
      itemBuilder: (context, index) {
        final file = state.files[index];
        return _buildFileCard(file, index, notifier);
      },
    );
  }

  Widget _buildFileCard(FileItem file, int index, HomeNotifier notifier) {
    switch (file.status) {
      case FileStatus.processing:
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.movie_outlined, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(file.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    TextButton(
                      onPressed: () => notifier.cancelConvert(index),
                      child: const Text('取消'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(value: file.progress),
                const SizedBox(height: 4),
                Text(
                  '${(file.progress * 100).toInt()}%',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
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
                Row(
                  children: [
                    const Icon(Icons.check_circle_outlined, size: 20, color: Colors.green),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(file.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  file.outputPath ?? '',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () {}, child: const Text('分享')),
                    TextButton(onPressed: () {}, child: const Text('打开')),
                    TextButton(onPressed: () {}, child: const Text('详细信息')),
                  ],
                ),
              ],
            ),
          ),
        );

      case FileStatus.failed:
        return const SizedBox.shrink();
    }
  }
}
