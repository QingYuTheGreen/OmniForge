import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'home_provider.dart';

class FilesTab extends ConsumerWidget {
  const FilesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(homeProvider);
    final notifier = ref.read(homeProvider.notifier);

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
        return _buildFileCard(context, file, index, notifier);
      },
    );
  }

  Widget _buildFileCard(
    BuildContext context,
    FileItem file,
    int index,
    HomeNotifier notifier,
  ) {
    switch (file.status) {
      case FileStatus.processing:
        return _buildProcessingCard(file, index, notifier);
      case FileStatus.completed:
        return _buildCompletedCard(file);
      case FileStatus.failed:
        return _buildFailedCard(file, index, notifier);
    }
  }

  // 进行中
  Widget _buildProcessingCard(FileItem file, int index, HomeNotifier notifier) {
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
            LinearProgressIndicator(
              value: file.progress,
              backgroundColor: Colors.grey.shade200,
            ),
            const SizedBox(height: 4),
            Text(
              '${(file.progress * 100).toInt()}%',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  // 已完成
  Widget _buildCompletedCard(FileItem file) {
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
  }

  // 失败
  Widget _buildFailedCard(FileItem file, int index, HomeNotifier notifier) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.error_outline, size: 20, color: Colors.red),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    file.name,
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              file.error ?? '未知错误',
              style: const TextStyle(fontSize: 12, color: Colors.red),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () {}, child: const Text('错误日志')),
                TextButton(
                  onPressed: () => notifier.retryConvert(index),
                  child: const Text('重试'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
