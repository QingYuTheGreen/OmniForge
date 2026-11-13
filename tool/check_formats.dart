import 'dart:io';
import 'package:yaml/yaml.dart';

void main() {
  final doc = loadYaml(File('assets/formats.yaml').readAsStringSync()) as Map;
  final cats = (doc['categories'] as List).map((c) => Map.from(c as Map)).toList();
  final fmts = (doc['formats'] as List).map((f) => Map.from(f as Map)).toList();
  print('stage=${doc['stage']}  分类=${cats.length}  格式=${fmts.length}');

  final problems = <String>[];
  final catKeys = cats.map((c) => c['key'].toString()).toSet();
  for (final f in fmts) {
    final id = f['id'];
    if (id == null || id.toString().isEmpty) problems.add('空 id: $f');
    final cs = List<String>.from(f['categories'] ?? []);
    if (cs.isEmpty) problems.add('$id 无分类');
    for (final c in cs) {
      if (!catKeys.contains(c)) problems.add('$id 分类不存在: $c');
    }
    final exts = List<String>.from(f['extensions'] ?? []);
    if (exts.isEmpty) problems.add('$id 无扩展名');
    for (final e in exts) {
      if (!e.startsWith('.')) problems.add('$id 扩展名格式错: $e');
    }
    if (f['status'] == null) problems.add('$id 无 status');
  }

  // 分类覆盖计数
  for (final c in cats) {
    final key = c['key'].toString();
    final n = fmts.where((f) => List<String>.from(f['categories']).contains(key)).length;
    print('${c['order'].toString().padLeft(2)} ${c['name'].toString().padRight(8)} $key'.padRight(28) + ' $n 种');
    if (n == 0) problems.add('分类 $key 没有任何格式');
  }
  print(problems.isEmpty ? '✓ 结构自检全部通过' : '✗ 问题:\n${problems.join('\n')}');
}
