import '../engine_utils.dart';
import '../i_engine.dart';

/// 一条字幕。
class SubtitleCue {
  final Duration start;
  final Duration end;
  final String text;

  const SubtitleCue({
    required this.start,
    required this.end,
    required this.text,
  });
}

/// 字幕引擎：srt / ass / vtt / lrc 互转（纯 Dart）。
class SubtitleEngine extends SimpleEngine {
  const SubtitleEngine();

  @override
  String get id => 'subtitle';

  @override
  Future<void> execute(EngineContext context) async {
    final input = await readFileText(context.inputPath);
    final source = _detectSource(context, input);
    final cues = _parse(source, input);
    if (cues.isEmpty) {
      throw const EngineException('没有从输入文件里解析到字幕内容');
    }

    final target = context.targetFormat.toLowerCase();
    final text = switch (target) {
      'srt' => _writeSrt(cues),
      'ass' || 'ssa' => _writeAss(cues),
      'vtt' => _writeVtt(cues),
      'lrc' => _writeLrc(cues),
      _ => throw EngineException('字幕引擎不支持输出格式：$target'),
    };
    await writeFileText(context.outputPath, text);
  }

  String _detectSource(EngineContext context, String text) {
    final ext = inputExtension(context);
    if (ext == 'ass' || ext == 'ssa' || text.contains('[Script Info]')) {
      return 'ass';
    }
    if (ext == 'vtt' || text.trimLeft().startsWith('WEBVTT')) return 'vtt';
    if (ext == 'lrc' || RegExp(r'^\[\d{1,2}:\d{2}[.:]\d{1,3}\]', multiLine: true)
        .hasMatch(text)) {
      return 'lrc';
    }
    return 'srt';
  }

  List<SubtitleCue> _parse(String source, String text) {
    return switch (source) {
      'ass' => _parseAss(text),
      'vtt' => _parseVtt(text),
      'lrc' => _parseLrc(text),
      _ => _parseSrt(text),
    };
  }

  // ─────────────────────────── 解析 ───────────────────────────

  List<SubtitleCue> _parseSrt(String text) {
    final cues = <SubtitleCue>[];
    final blocks = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split(RegExp(r'\n{2,}'));
    final timeRe = RegExp(
      r'(\d{1,2}):(\d{2}):(\d{2})[,.](\d{1,3})\s*-->\s*'
      r'(\d{1,2}):(\d{2}):(\d{2})[,.](\d{1,3})',
    );
    for (final block in blocks) {
      final match = timeRe.firstMatch(block);
      if (match == null) continue;
      final start = _duration(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
        int.parse(match.group(4)!.padRight(3, '0')),
      );
      final end = _duration(
        int.parse(match.group(5)!),
        int.parse(match.group(6)!),
        int.parse(match.group(7)!),
        int.parse(match.group(8)!.padRight(3, '0')),
      );
      final lines = block.substring(match.end).split('\n').toList();
      while (lines.isNotEmpty && lines.first.trim().isEmpty) {
        lines.removeAt(0);
      }
      final content = lines.join('\n').trim();
      if (content.isEmpty) continue;
      cues.add(SubtitleCue(start: start, end: end, text: content));
    }
    return cues;
  }

  List<SubtitleCue> _parseVtt(String text) {
    final cleaned = text
        .replaceAll('\r\n', '\n')
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('NOTE'))
        .join('\n');
    return _parseSrt(cleaned);
  }

  List<SubtitleCue> _parseAss(String text) {
    final cues = <SubtitleCue>[];
    final lines = text.replaceAll('\r\n', '\n').split('\n');
    var format = <String>[
      'Layer',
      'Start',
      'End',
      'Style',
      'Name',
      'MarginL',
      'MarginR',
      'MarginV',
      'Effect',
      'Text',
    ];
    var inEvents = false;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('[')) {
        inEvents = trimmed.toLowerCase() == '[events]';
        continue;
      }
      if (!inEvents) continue;
      if (trimmed.startsWith('Format:')) {
        format = trimmed
            .substring('Format:'.length)
            .split(',')
            .map((e) => e.trim())
            .toList();
        continue;
      }
      if (!trimmed.startsWith('Dialogue:')) continue;
      final body = trimmed.substring('Dialogue:'.length).trim();
      final parts = _splitAssFields(body, format.length);
      if (parts.length < format.length) continue;
      final startIndex = format.indexOf('Start');
      final endIndex = format.indexOf('End');
      final textIndex = format.indexOf('Text');
      if (startIndex < 0 || endIndex < 0 || textIndex < 0) continue;
      final start = _parseAssTime(parts[startIndex]);
      final end = _parseAssTime(parts[endIndex]);
      final content = parts
          .sublist(textIndex)
          .join(',')
          .replaceAll(RegExp(r'\{[^}]*\}'), '')
          .replaceAll(r'\N', '\n')
          .replaceAll(r'\n', '\n')
          .trim();
      if (content.isEmpty) continue;
      cues.add(SubtitleCue(start: start, end: end, text: content));
    }
    return cues;
  }

  List<String> _splitAssFields(String body, int count) {
    final parts = <String>[];
    var current = StringBuffer();
    for (var i = 0; i < body.length; i++) {
      final char = body[i];
      if (char == ',' && parts.length < count - 1) {
        parts.add(current.toString());
        current = StringBuffer();
      } else {
        current.write(char);
      }
    }
    parts.add(current.toString());
    return parts;
  }

  Duration _parseAssTime(String raw) {
    final value = raw.trim();
    final match = RegExp(r'(\d+):(\d{1,2}):(\d{1,2})[.:](\d{1,2})').firstMatch(value);
    if (match == null) return Duration.zero;
    final centis = int.parse(match.group(4)!.padRight(2, '0').substring(0, 2));
    return _duration(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      centis * 10,
    );
  }

  List<SubtitleCue> _parseLrc(String text) {
    final cues = <SubtitleCue>[];
    final tagRe = RegExp(r'\[(\d{1,2}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
    for (final rawLine in text.replaceAll('\r\n', '\n').split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final matches = tagRe.allMatches(line).toList();
      if (matches.isEmpty) continue;
      final content = line.substring(matches.last.end).trim();
      for (final match in matches) {
        final millis = (int.tryParse(match.group(3) ?? '0') ?? 0) *
            ((match.group(3)?.length ?? 0) <= 2 ? 10 : 1);
        cues.add(SubtitleCue(
          start: _duration(
            int.parse(match.group(1)!),
            int.parse(match.group(2)!),
            0,
            millis,
          ),
          end: Duration.zero,
          text: content,
        ));
      }
    }
    cues.sort((a, b) => a.start.compareTo(b.start));
    for (var i = 0; i < cues.length; i++) {
      final next = i + 1 < cues.length ? cues[i + 1].start : cues[i].start + const Duration(seconds: 4);
      cues[i] = SubtitleCue(start: cues[i].start, end: next, text: cues[i].text);
    }
    return cues;
  }

  // ─────────────────────────── 输出 ───────────────────────────

  String _writeSrt(List<SubtitleCue> cues) {
    final buffer = StringBuffer();
    for (var i = 0; i < cues.length; i++) {
      final cue = cues[i];
      buffer.writeln('${i + 1}');
      buffer.writeln(
        '${_srtTime(cue.start)} --> ${_srtTime(cue.end)}',
      );
      buffer.writeln(cue.text);
      buffer.writeln();
    }
    return buffer.toString();
  }

  String _writeVtt(List<SubtitleCue> cues) {
    final buffer = StringBuffer('WEBVTT\n\n');
    for (final cue in cues) {
      buffer.writeln('${_vttTime(cue.start)} --> ${_vttTime(cue.end)}');
      buffer.writeln(cue.text);
      buffer.writeln();
    }
    return buffer.toString();
  }

  String _writeAss(List<SubtitleCue> cues) {
    final buffer = StringBuffer()
      ..writeln('[Script Info]')
      ..writeln('ScriptType: v4.00+')
      ..writeln('PlayResX: 1920')
      ..writeln('PlayResY: 1080')
      ..writeln()
      ..writeln('[V4+ Styles]')
      ..writeln(
        'Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, '
        'OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, '
        'ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, '
        'Alignment, MarginL, MarginR, MarginV, Encoding',
      )
      ..writeln(
        'Style: Default,Arial,48,&H00FFFFFF,&H000000FF,&H00000000,&H64000000,'
        '0,0,0,0,100,100,0,0,1,2,0,2,40,40,40,1',
      )
      ..writeln()
      ..writeln('[Events]')
      ..writeln(
        'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, '
        'Effect, Text',
      );
    for (final cue in cues) {
      final text = cue.text.replaceAll('\n', r'\N');
      buffer.writeln(
        'Dialogue: 0,${_assTime(cue.start)},${_assTime(cue.end)},'
        'Default,,0,0,0,,$text',
      );
    }
    return buffer.toString();
  }

  String _writeLrc(List<SubtitleCue> cues) {
    final buffer = StringBuffer()
      ..writeln('[ti:OmniForge]')
      ..writeln('[by:OmniForge]');
    final sorted = [...cues]..sort((a, b) => a.start.compareTo(b.start));
    for (final cue in sorted) {
      final text = cue.text.replaceAll('\n', ' ').trim();
      buffer.writeln('[${_lrcTime(cue.start)}]$text');
    }
    return buffer.toString();
  }

  // ─────────────────────────── 时间工具 ───────────────────────────

  Duration _duration(int hours, int minutes, int seconds, int millis) =>
      Duration(
        hours: hours,
        minutes: minutes,
        seconds: seconds,
        milliseconds: millis,
      );

  String _srtTime(Duration d) =>
      '${_two(d.inHours)}:${_two(d.inMinutes % 60)}:${_two(d.inSeconds % 60)},'
      '${_three(d.inMilliseconds % 1000)}';

  String _vttTime(Duration d) =>
      '${_two(d.inHours)}:${_two(d.inMinutes % 60)}:${_two(d.inSeconds % 60)}.'
      '${_three(d.inMilliseconds % 1000)}';

  String _assTime(Duration d) =>
      '${d.inHours}:${_two(d.inMinutes % 60)}:${_two(d.inSeconds % 60)}.'
      '${_two((d.inMilliseconds % 1000) ~/ 10)}';

  String _lrcTime(Duration d) =>
      '${_two(d.inMinutes)}:${_two(d.inSeconds % 60)}.'
      '${_two((d.inMilliseconds % 1000) ~/ 10)}';

  String _two(int value) => value.toString().padLeft(2, '0');

  String _three(int value) => value.toString().padLeft(3, '0');
}
