import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// 单个包内文件。
class PackageEntry {
  PackageEntry(this.name, this.bytes);

  final String name;
  final Uint8List bytes;
}

/// ZIP 容器读写库（docx / xlsx / epub / mcworld / zip 共用）。
///
/// OOXML、EPUB、Minecraft 存档本质上都是 ZIP 容器，各引擎不再重复
/// `ZipDecoder().decodeBytes(...)` / `Archive()..add(ArchiveFile(...))` 样板。
class ZipPackage {
  ZipPackage(Map<String, Uint8List> entries) : _entries = entries;

  final Map<String, Uint8List> _entries;

  factory ZipPackage.decode(Uint8List bytes) {
    final entries = <String, Uint8List>{};
    final archive = ZipDecoder().decodeBytes(bytes, verify: false);
    for (final file in archive.files) {
      if (!file.isFile) continue;
      entries[file.name] = Uint8List.fromList(file.content as List<int>);
    }
    return ZipPackage(entries);
  }

  Iterable<String> get names => _entries.keys;

  Map<String, Uint8List> get entries => Map.unmodifiable(_entries);

  bool contains(String name) => _entries.containsKey(name);

  Uint8List? bytesOf(String name) => _entries[name];

  /// 按名称读取文本；缺失时返回 null。
  String? textOf(String name) {
    final bytes = _entries[name];
    if (bytes == null) return null;
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// 第一个满足条件的条目名。
  String? firstWhereName(bool Function(String name) test) {
    for (final name in _entries.keys) {
      if (test(name)) return name;
    }
    return null;
  }

  /// 重新打包为 ZIP 字节。
  Uint8List encode({int level = 6}) {
    final archive = Archive();
    for (final entry in _entries.entries) {
      archive.add(ArchiveFile(entry.key, entry.value.length, entry.value));
    }
    return Uint8List.fromList(ZipEncoder().encode(archive, level: level));
  }

  /// 由文本片段直接打包（UTF-8）。
  static Uint8List encodeText(Map<String, String> parts, {int level = 6}) {
    final entries = <PackageEntry>[
      for (final part in parts.entries)
        PackageEntry(part.key, Uint8List.fromList(utf8.encode(part.value))),
    ];
    return encodeEntries(entries, level: level);
  }

  static Uint8List encodeEntries(
    Iterable<PackageEntry> entries, {
    int level = 6,
  }) {
    final archive = Archive();
    for (final entry in entries) {
      archive.add(ArchiveFile(entry.name, entry.bytes.length, entry.bytes));
    }
    return Uint8List.fromList(ZipEncoder().encode(archive, level: level));
  }
}
