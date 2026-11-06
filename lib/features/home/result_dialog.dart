import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:open_filex/open_filex.dart';

class ResultDialog extends StatelessWidget {
  final String outputPath;
  final VoidCallback onDismiss;

  const ResultDialog({
    super.key,
    required this.outputPath,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('转换成功'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('文件已生成：'),
          const SizedBox(height: 8),
          Text(
            outputPath,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Share.shareXFiles([XFile(outputPath)]),
          child: const Text('分享'),
        ),
        TextButton(
          onPressed: () async {
            try {
              await OpenFilex.open(outputPath);
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('无法打开文件：$e')),
                );
              }
            }
          },
          child: const Text('打开'),
        ),
        TextButton(
          onPressed: onDismiss,
          child: const Text('完成'),
        ),
      ],
    );
  }
}
