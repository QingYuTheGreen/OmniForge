import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'i_engine.dart';

/// 引擎层统一异常：消息直接面向用户展示。
class EngineException implements Exception {
  final String message;
  const EngineException(this.message);

  @override
  String toString() => message;
}

/// 需要额外插件才能完成的转换。
class PluginRequiredException implements Exception {
  final String pluginId;
  final int sizeMb;
  const PluginRequiredException(this.pluginId, this.sizeMb);

  @override
  String toString() => '需要插件 $pluginId';
}

// ─────────────────────────── 参数读取 ───────────────────────────

String stringParam(EngineContext ctx, String key, [String fallback = '']) {
  final value = ctx.params[key];
  if (value == null) return fallback;
  final text = value.toString().trim();
  return text.isEmpty ? fallback : text;
}

int intParam(EngineContext ctx, String key, int fallback) {
  final value = ctx.params[key];
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

double doubleParam(EngineContext ctx, String key, double fallback) {
  final value = ctx.params[key];
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}

bool boolParam(EngineContext ctx, String key, bool fallback) {
  final value = ctx.params[key];
  if (value is bool) return value;
  final text = value?.toString().trim().toLowerCase() ?? '';
  if (text == 'true' || text == '1' || text == 'yes' || text == 'on') return true;
  if (text == 'false' || text == '0' || text == 'no' || text == 'off') {
    return false;
  }
  return fallback;
}

// ─────────────────────────── 文件工具 ───────────────────────────

/// 确保输出文件的父目录存在。
Future<void> ensureParentDirectory(String path) async {
  final dir = Directory(p.dirname(path));
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
}

/// 读取整个文件为字节。
Future<Uint8List> readFileBytes(String path) async {
  final file = File(path);
  if (!await file.exists()) {
    throw EngineException('输入文件不存在：$path');
  }
  return file.readAsBytes();
}

/// 写入字节，父目录自动创建。
Future<void> writeFileBytes(String path, List<int> bytes) async {
  await ensureParentDirectory(path);
  await File(path).writeAsBytes(bytes, flush: true);
}

/// 写入文本，父目录自动创建。
Future<void> writeFileText(String path, String text) async {
  await ensureParentDirectory(path);
  await File(path).writeAsString(text, flush: true);
}

/// 读取文本（宽松解码，坏字节用替换符）。
Future<String> readFileText(String path) async {
  final bytes = await readFileBytes(path);
  return utf8.decode(bytes, allowMalformed: true).replaceAll('\u0000', '');
}

/// 输入文件主名（不含扩展名）。
String inputStem(EngineContext ctx) {
  final name = p.basename(ctx.inputPath);
  final stem = p.basenameWithoutExtension(name);
  return stem.isEmpty ? 'output' : stem;
}

/// 输入文件小写扩展名（不含点）。
String inputExtension(EngineContext ctx) =>
    p.extension(ctx.inputPath).replaceFirst('.', '').toLowerCase();

/// 输出文件小写扩展名（不含点）。
String outputExtension(EngineContext ctx) =>
    p.extension(ctx.outputPath).replaceFirst('.', '').toLowerCase();

// ─────────────────────────── 引擎基类 ───────────────────────────

/// 简单引擎基类：同步/异步一次性完成，统一处理进度、输出校验与错误包装。
///
/// 子类只需实现 [execute]；需要更细粒度进度时可以直接实现 [IEngine]。
abstract class SimpleEngine implements IEngine {
  const SimpleEngine();

  @override
  String? get requiredPluginId => null;

  /// 实际转换逻辑，输出必须写到 [EngineContext.outputPath]。
  Future<void> execute(EngineContext context);

  /// 可选的输入预检查，抛 [EngineException] 表示用户可读的错误。
  void validate(EngineContext context) {}

  @override
  Stream<EngineProgress> convert(EngineContext context) async* {
    yield const Progress(0.02, '准备中…');
    try {
      final file = File(context.inputPath);
      if (!await file.exists()) {
        throw EngineException('输入文件不存在：${context.inputPath}');
      }
      validate(context);
      await ensureParentDirectory(context.outputPath);
      yield const Progress(0.1, '开始转换…');
      await execute(context);
      if (!await File(context.outputPath).exists()) {
        throw const EngineException('引擎未能生成输出文件');
      }
      yield const Progress(0.99, '写入完成');
      yield Success(context.outputPath);
    } on PluginRequiredException catch (e) {
      yield PluginRequired(e.pluginId, e.sizeMb);
    } on EngineException catch (e) {
      yield Error(e.message);
    } on FileSystemException catch (e) {
      yield Error('文件读写失败：${e.message}');
    } catch (error) {
      yield Error('转换失败：$error');
    }
  }
}

/// 插件占位引擎：真实实现依赖外部插件/二进制，转换时给出明确提示。
class PluginEngine implements IEngine {
  @override
  final String id;
  final String pluginId;
  final int sizeMb;
  final String note;

  const PluginEngine(
    this.id, {
    required this.pluginId,
    this.sizeMb = 0,
    this.note = '',
  });

  @override
  String? get requiredPluginId => pluginId;

  @override
  Stream<EngineProgress> convert(EngineContext context) async* {
    yield Progress(0.01, note.isEmpty ? '需要插件支持' : note);
    yield PluginRequired(pluginId, sizeMb);
  }
}
