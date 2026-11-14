import 'dart:io';
import 'package:omniforge/engine/conversion_planner.dart';
import 'package:omniforge/engine/engine_registry.dart';
import 'package:omniforge/models/format_node.dart';
import 'package:yaml/yaml.dart';

void main() {
  final root = loadYaml(File('assets/formats.yaml').readAsStringSync()) as Map;
  final formats = (root['formats'] as List).map((e) => FormatNode.fromYaml(Map.from(e as Map))).toList();
  final flows = (root['flows'] as List).map((e) => FlowRule.fromYaml(Map.from(e as Map))).toList();
  final registry = EngineRegistry.platformDefaults();
  final planner = ConversionPlanner.fromData(
    formats: formats, flows: flows,
    readyEngines: registry.readyEngineIds,
    knownEngines: registry.all.map((e) => e.id).toSet());
  final cat = <String,String>{};
  for (final f in formats) { cat[f.id] = f.category; }
  var crossAvail = 0;
  for (final f in formats) {
    final targets = planner.reachableFrom(f.id).where((t)=>t.available).toList();
    final xs = targets.where((t)=>cat[t.formatId]!=f.category).toList();
    crossAvail += xs.length;
    if (xs.isNotEmpty) {
      print('${f.id} (${f.category}): ${xs.map((t)=>'${t.formatId}${t.isDirect?'':'(+${t.hops-1})'}').join(' ')}');
    }
  }
  print('---- cross-category reachable edges: $crossAvail (listing above)');
  // 反向：统计每类入边
  final inc = <String,int>{};
  for (final f in formats) {
    for (final t in planner.reachableFrom(f.id).where((t)=>t.available)) {
      if (cat[t.formatId]!=f.category) { inc[t.formatId] = (inc[t.formatId] ?? 0) + 1; }
    }
  }
  print('入边(跨类来源数) top: ${(inc.entries.toList()..sort((a,b)=>b.value-a.value)).take(20).map((e)=>'${e.key}:${e.value}').join(' ')}');
}
