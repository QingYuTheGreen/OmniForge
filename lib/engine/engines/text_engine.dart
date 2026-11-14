import 'dart:convert';

import 'package:markdown/markdown.dart' as md;

import '../engine_utils.dart';
import '../i_engine.dart';
import '../common/text_format.dart';

/// 文本引擎：txt / md / html 互转（纯 Dart）。
class TextEngine extends SimpleEngine {
  const TextEngine();

  @override
  String get id => 'text';

  @override
  Future<void> execute(EngineContext context) async {
    final bytes = await readFileBytes(context.inputPath);
    final text = utf8.decode(bytes, allowMalformed: true);
    final source = _detect(context, text);
    final target = context.targetFormat.toLowerCase();

    String output;
    if (target == 'txt') {
      output = switch (source) {
        'html' => stripHtml(text),
        'md' => stripHtml(md.markdownToHtml(text)),
        _ => text,
      };
    } else if (target == 'md' || target == 'markdown') {
      output = switch (source) {
        'html' => htmlToMarkdown(text),
        'md' => text,
        _ => text,
      };
    } else if (target == 'html' || target == 'htm') {
      output = switch (source) {
        'md' => _wrapHtml(md.markdownToHtml(text), context),
        'html' => text,
        _ => textToHtml(text, title: inputStem(context)),
      };
    } else {
      throw EngineException('文本引擎不支持输出格式：$target');
    }
    await writeFileText(context.outputPath, output);
  }

  String _detect(EngineContext context, String text) {
    final ext = inputExtension(context);
    if (ext == 'md' || ext == 'markdown') return 'md';
    if (ext == 'html' || ext == 'htm') return 'html';
    final head = text.trimLeft().toLowerCase();
    if (head.startsWith('<!doctype html') || head.startsWith('<html')) {
      return 'html';
    }
    return 'txt';
  }

  String _wrapHtml(String body, EngineContext context) {
    return '''<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>${escapeHtml(inputStem(context))}</title>
<style>
body { font-family: system-ui, -apple-system, "Segoe UI", "Noto Sans SC", sans-serif;
  line-height: 1.7; max-width: 860px; margin: 2rem auto; padding: 0 1.2rem;
  color: #1f1f1f; }
a { color: #0b57d0; }
pre { background: #f5f5f5; padding: 1rem; border-radius: 8px; overflow-x: auto; }
code { background: #f0f0f0; padding: .1rem .3rem; border-radius: 4px; }
blockquote { border-left: 4px solid #dadce0; margin-left: 0; padding-left: 1rem; color: #444; }
table { border-collapse: collapse; }
td, th { border: 1px solid #dadce0; padding: .4rem .6rem; }
</style>
</head>
<body>
$body
</body>
</html>
''';
  }
}
