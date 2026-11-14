import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import '../engine_utils.dart';
import '../i_engine.dart';
import '../plugin/native_plugin_registry.dart';
import '../plugin/plugin_manifest.dart';

/// 原生插件引擎：把一次转换委托给已安装插件动态库里的
/// `int omniforge_convert(const char* input, const char* output,
///                        const char* paramsJson, char* errbuf, int errlen)`。
///
/// 约定：
/// - 返回 0 且输出文件存在 → 成功；
/// - 返回非 0 → 读取 `errbuf` 作为用户可读错误；
/// - 插件未安装 / 平台不支持 / 库损坏 / 缺少导出符号 → [PluginRequired]；
/// - 其余异常一律转成 [Error]，**绝不让异常穿透 stream**。
class NativePluginEngine implements IEngine {
  NativePluginEngine({
    required this.manifest,
    required this.registry,
    this.engineIdOverride,
  });

  /// 插件清单。
  final PluginManifest manifest;

  /// 插件注册表（安装状态 / 库文件路径）。
  final NativePluginRegistry registry;

  /// 覆盖对外引擎 id（同一插件实现多个引擎时使用）。
  final String? engineIdOverride;

  /// 默认取清单里的第一个引擎 id；清单异常时退回插件 id。
  @override
  String get id =>
      engineIdOverride ??
      (manifest.engineIds.isNotEmpty ? manifest.engineIds.first : manifest.id);

  @override
  String? get requiredPluginId => manifest.id;

  /// 当前安装状态（供 UI 展示 / 提前提示）。
  PluginInstallState get installState => registry.stateOf(manifest.id);

  @override
  Stream<EngineProgress> convert(EngineContext context) async* {
    yield const Progress(0.01, '检查插件状态…');
    try {
      final state = registry.stateOf(manifest.id);
      if (state != PluginInstallState.installed) {
        yield Progress(
          0.02,
          state == PluginInstallState.incompatible
              ? '当前平台不支持${manifest.name}插件'
              : '需要安装${manifest.name}插件',
        );
        yield PluginRequired(
          manifest.id,
          manifest.sizeMb,
          note: _installNote(state),
        );
        return;
      }

      final libraryPath = registry.pathOf(manifest.id);
      if (libraryPath == null) {
        yield PluginRequired(
          manifest.id,
          manifest.sizeMb,
          note: _installNote(PluginInstallState.missing),
        );
        return;
      }

      final input = File(context.inputPath);
      if (!await input.exists()) {
        yield Error('输入文件不存在：${context.inputPath}');
        return;
      }
      await ensureParentDirectory(context.outputPath);

      final paramsJson = _encodeParams(context);
      yield const Progress(0.1, '加载原生插件…');

      // 只把字符串带进 isolate（不捕获引擎 / 上下文对象）。
      final symbol = manifest.symbol;
      final inputPath = context.inputPath;
      final outputPath = context.outputPath;

      // 原生转换是同步阻塞调用，放到独立 isolate 执行，避免卡住 UI 线程。
      final outcome = await Isolate.run(
        () => _invokeNative(
          libraryPath: libraryPath,
          symbol: symbol,
          inputPath: inputPath,
          outputPath: outputPath,
          paramsJson: paramsJson,
        ),
      );

      if (outcome.pluginIssue) {
        final detail = outcome.error.isEmpty ? '原生库无法加载' : outcome.error;
        yield PluginRequired(
          manifest.id,
          manifest.sizeMb,
          note: '$detail；请在「设置 → 转换插件」重新导入${manifest.name}',
        );
        return;
      }

      if (outcome.code != 0) {
        final message =
            outcome.error.isEmpty ? '原生插件返回错误码 ${outcome.code}' : outcome.error;
        yield Error(message);
        return;
      }

      if (!await File(context.outputPath).exists()) {
        yield const Error('原生插件返回成功，但未生成输出文件');
        return;
      }

      yield const Progress(0.99, '写入完成');
      yield Success(context.outputPath);
    } on ArgumentError catch (error) {
      // Invalid argument(s) / 参数或指针非法：通常是插件库损坏或 ABI 不匹配。
      yield PluginRequired(
        manifest.id,
        manifest.sizeMb,
        note: '原生插件无法加载（${error.message}）；请重新下载 / 导入${manifest.name}',
      );
    } on UnsupportedError catch (error) {
      yield PluginRequired(
        manifest.id,
        manifest.sizeMb,
        note: '当前环境不支持加载原生插件：$error',
      );
    } catch (error) {
      // 兜底：stream 必须正常结束，异常不能穿透给 UI。
      yield Error('原生插件转换失败：$error');
    }
  }

  String _installNote(PluginInstallState state) {
    switch (state) {
      case PluginInstallState.missing:
        return '需在「设置 → 转换插件」下载 / 导入${manifest.name}'
            '（约 ${manifest.sizeMb}MB）';
      case PluginInstallState.incompatible:
        return '当前平台（${registry.platform}）暂不支持${manifest.name}插件';
      case PluginInstallState.installed:
        return '';
    }
  }

  /// 传给插件的参数：[target] 输出格式、[source] 输入格式、[params] 用户参数。
  String _encodeParams(EngineContext context) => jsonEncode(<String, Object?>{
        'target': context.targetFormat,
        'source': context.sourceFormat,
        'params': context.params,
      });
}

// ───────────────────────── 原生调用（在独立 isolate 内执行）─────────────────

/// 原生入口符号签名：`int omniforge_convert(const char*, const char*,
/// const char*, char*, int)`。
typedef _ConvertNative = Int32 Function(
  Pointer<Uint8> inputPath,
  Pointer<Uint8> outputPath,
  Pointer<Uint8> paramsJson,
  Pointer<Uint8> errorBuffer,
  Int32 errorBufferLength,
);

typedef _ConvertDart = int Function(
  Pointer<Uint8> inputPath,
  Pointer<Uint8> outputPath,
  Pointer<Uint8> paramsJson,
  Pointer<Uint8> errorBuffer,
  int errorBufferLength,
);

/// 原生调用结果：`pluginIssue=true` 表示插件层面不可用（应提示安装 / 重新导入）。
typedef _NativeOutcome = ({int code, String error, bool pluginIssue});

/// 错误缓冲区大小（字节）。
const int _errorBufferLength = 2048;

_NativeOutcome _invokeNative({
  required String libraryPath,
  required String symbol,
  required String inputPath,
  required String outputPath,
  required String paramsJson,
}) {
  final DynamicLibrary library;
  try {
    library = DynamicLibrary.open(libraryPath);
  } on ArgumentError catch (error) {
    return (code: -1, error: '原生库无法加载（${error.message}）', pluginIssue: true);
  } on UnsupportedError catch (error) {
    return (code: -1, error: '当前平台不支持动态库加载（$error）', pluginIssue: true);
  }

  final _ConvertDart convert;
  try {
    convert = library.lookupFunction<_ConvertNative, _ConvertDart>(symbol);
  } on ArgumentError catch (error) {
    return (
      code: -1,
      error: '插件缺少导出符号 $symbol（${error.message}）',
      pluginIssue: true,
    );
  }

  final _NativeAllocator allocator;
  try {
    allocator = _NativeAllocator.instance;
  } catch (error) {
    return (code: -1, error: '无法初始化原生内存分配（$error）', pluginIssue: false);
  }

  Pointer<Uint8>? inputPointer;
  Pointer<Uint8>? outputPointer;
  Pointer<Uint8>? paramsPointer;
  Pointer<Uint8>? errorPointer;
  try {
    inputPointer = _toUtf8Pointer(allocator, inputPath);
    outputPointer = _toUtf8Pointer(allocator, outputPath);
    paramsPointer = _toUtf8Pointer(allocator, paramsJson);
    errorPointer = allocator.allocate(_errorBufferLength);
    errorPointer
        .asTypedList(_errorBufferLength)
        .fillRange(0, _errorBufferLength, 0);

    final code = convert(
      inputPointer,
      outputPointer,
      paramsPointer,
      errorPointer,
      _errorBufferLength,
    );
    final message = _fromUtf8Pointer(errorPointer, _errorBufferLength);
    return (code: code, error: message, pluginIssue: false);
  } on ArgumentError catch (error) {
    return (code: -1, error: '调用原生转换失败（${error.message}）', pluginIssue: true);
  } catch (error) {
    return (code: -1, error: '原生转换调用异常（$error）', pluginIssue: false);
  } finally {
    allocator.free(inputPointer);
    allocator.free(outputPointer);
    allocator.free(paramsPointer);
    allocator.free(errorPointer);
  }
}

// ────────────────────────────── 内存与 UTF-8 ──────────────────────────────

/// 原生内存分配器。
///
/// `dart:ffi` 自身不提供 malloc/calloc（它们在 `package:ffi` 里，本项目未声明该依赖），
/// 因此按平台从进程 / 系统 C 库解析 `malloc` / `free`，只在本模块内部使用。
class _NativeAllocator {
  _NativeAllocator._(this._malloc, this._free);

  static _NativeAllocator? _instance;

  static _NativeAllocator get instance => _instance ??= _create();

  final Pointer<Uint8> Function(int size) _malloc;
  final void Function(Pointer<Uint8> pointer) _free;

  Pointer<Uint8> allocate(int size) {
    final pointer = _malloc(size <= 0 ? 1 : size);
    if (pointer == nullptr) {
      throw StateError('原生内存分配失败（$size 字节）');
    }
    return pointer;
  }

  void free(Pointer<Uint8>? pointer) {
    if (pointer != null && pointer != nullptr) _free(pointer);
  }

  static _NativeAllocator _create() {
    final candidates = <DynamicLibrary>[];
    void add(String name) {
      try {
        candidates.add(DynamicLibrary.open(name));
      } catch (_) {
        // 该候选库不存在，继续尝试下一个。
      }
    }

    try {
      candidates.add(DynamicLibrary.process());
    } catch (_) {
      // Windows 上 DynamicLibrary.process() 不可用。
    }
    if (Platform.isWindows) {
      add('ucrtbase.dll'); // UCRT（VS2015+ 运行时）
      add('msvcrt.dll');
    } else if (Platform.isLinux || Platform.isAndroid) {
      add('libc.so.6');
      add('libc.so');
    } else if (Platform.isMacOS || Platform.isIOS) {
      add('/usr/lib/libSystem.B.dylib');
    }

    for (final library in candidates) {
      try {
        final malloc =
            library.lookupFunction<_MallocNative, _MallocDart>('malloc');
        final free = library.lookupFunction<_FreeNative, _FreeDart>('free');
        return _NativeAllocator._(malloc, free);
      } catch (_) {
        // 这个库没有导出 malloc/free，换下一个。
      }
    }
    throw UnsupportedError('无法定位原生 malloc/free');
  }
}

typedef _MallocNative = Pointer<Uint8> Function(IntPtr size);
typedef _MallocDart = Pointer<Uint8> Function(int size);
typedef _FreeNative = Void Function(Pointer<Uint8> pointer);
typedef _FreeDart = void Function(Pointer<Uint8> pointer);

/// Dart 字符串 → NUL 结尾的 UTF-8 C 字符串（调用方负责 free）。
Pointer<Uint8> _toUtf8Pointer(_NativeAllocator allocator, String text) {
  final bytes = utf8.encode(text);
  final pointer = allocator.allocate(bytes.length + 1);
  final view = pointer.asTypedList(bytes.length + 1);
  view.setRange(0, bytes.length, bytes);
  view[bytes.length] = 0;
  return pointer;
}

/// NUL 结尾的 UTF-8 C 字符串 → Dart 字符串（最多读取 [maxLength] 字节）。
String _fromUtf8Pointer(Pointer<Uint8> pointer, int maxLength) {
  if (pointer == nullptr || maxLength <= 0) return '';
  final view = pointer.asTypedList(maxLength);
  var length = 0;
  while (length < maxLength && view[length] != 0) {
    length++;
  }
  if (length == 0) return '';
  return utf8.decode(view.sublist(0, length), allowMalformed: true).trim();
}
