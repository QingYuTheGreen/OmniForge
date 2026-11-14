/// 纯文本处理公共工具：HTML 转义 / 去标签 / 简易 HTML→Markdown。
library;

String escapeHtml(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String escapeXml(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

/// 去掉 HTML 标签，保留可读文本。
String stripHtml(String html) {
  var text = html
      .replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), '')
      .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), '')
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</(p|div|h[1-6]|li|tr)>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '');
  text = _decodeEntities(text);
  return text
      .split('\n')
      .map((line) => line.trimRight())
      .join('\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

/// 简易 HTML → Markdown（标题 / 段落 / 列表 / 链接 / 图片 / 粗体斜体）。
String htmlToMarkdown(String html) {
  var text = html
      .replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), '')
      .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), '')
      .replaceAllMapped(RegExp(r'<h([1-6])[^>]*>([\s\S]*?)</h\1>',
              caseSensitive: false),
          (match) =>
              '\n${'#' * int.parse(match.group(1)!)} ${stripHtml(match.group(2)!).trim()}\n')
      .replaceAllMapped(RegExp(r'<li[^>]*>([\s\S]*?)</li>', caseSensitive: false),
          (match) => '\n- ${stripHtml(match.group(1)!).trim()}')
      .replaceAllMapped(RegExp(r'<a[^>]*href="([^"]*)"[^>]*>([\s\S]*?)</a>',
              caseSensitive: false),
          (match) => '[${stripHtml(match.group(2)!).trim()}](${match.group(1)})')
      .replaceAllMapped(RegExp(r'<img[^>]*src="([^"]*)"[^>]*>', caseSensitive: false),
          (match) => '![](${match.group(1)})')
      .replaceAllMapped(RegExp(r'<(b|strong)[^>]*>([\s\S]*?)</(b|strong)>',
              caseSensitive: false),
          (match) => '**${stripHtml(match.group(2)!).trim()}**')
      .replaceAllMapped(RegExp(r'<(i|em)[^>]*>([\s\S]*?)</(i|em)>',
              caseSensitive: false),
          (match) => '*${stripHtml(match.group(2)!).trim()}*')
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</(p|div)>', caseSensitive: false), '\n\n')
      .replaceAll(RegExp(r'<[^>]+>'), '');
  text = _decodeEntities(text);
  return text
      .split('\n')
      .map((line) => line.trimRight())
      .join('\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

/// 文本 → 简易 HTML 段落。
String textToHtml(String text, {String? title, bool paragraph = true}) {
  final body = paragraph
      ? text
          .replaceAll('\r\n', '\n')
          .split(RegExp(r'\n{2,}'))
          .map((block) => '<p>${escapeHtml(block.trim()).replaceAll('\n', '<br/>')}</p>')
          .join('\n')
      : '<pre>${escapeHtml(text)}</pre>';
  return '''<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>${escapeHtml(title ?? 'OmniForge')}</title>
<style>
body { font-family: system-ui, -apple-system, "Segoe UI", "Noto Sans SC", sans-serif;
  line-height: 1.7; max-width: 860px; margin: 2rem auto; padding: 0 1.2rem;
  color: #1f1f1f; }
a { color: #0b57d0; }
pre { background: #f5f5f5; padding: 1rem; border-radius: 8px; overflow-x: auto; }
code { background: #f0f0f0; padding: .1rem .3rem; border-radius: 4px; }
blockquote { border-left: 4px solid #dadce0; margin-left: 0; padding-left: 1rem; color: #444; }
</style>
</head>
<body>
$body
</body>
</html>
''';
}

String _decodeEntities(String text) => text
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&apos;', "'")
    .replaceAll('&mdash;', '—')
    .replaceAll('&ndash;', '–')
    .replaceAll('&hellip;', '…')
    .replaceAll('&amp;', '&');

/// 把文本按行切成段落（保留项目符号）。
List<String> splitParagraphs(String text) => text
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n')
    .split(RegExp(r'\n\s*\n'))
    .map((block) => block.trim())
    .where((block) => block.isNotEmpty)
    .toList();
