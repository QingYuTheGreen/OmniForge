import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omniforge/features/home/config_page.dart';
import 'package:omniforge/registry/registry_manager.dart';
import 'package:omniforge/registry/format_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('注册表：19 类 / 95 个格式条目全部可加载', () async {
    await RegistryManager().initialize();
    final catalog = FormatCatalog.fromRegistry();

    expect(catalog.types.length, 19, reason: '分类数');
    expect(catalog.uniqueFormatCount, 95, reason: '格式去重数');
    expect(RegistryManager().isShellStage, false, reason: '真实转换阶段');

    // 每类都有格式、每类都有中文名
    for (final t in catalog.types) {
      expect(catalog.formatsOf(t.value), isNotEmpty, reason: '${t.label} 为空');
      expect(t.value, isNotEmpty);
    }

    // 跨类共享
    expect(catalog.formatsOf('document').map((o) => o.value), contains('pdf'));
    expect(catalog.formatsOf('ebook').map((o) => o.value), contains('pdf'));
    expect(catalog.formatsOf('slides').map((o) => o.value), contains('pdf'));
    expect(catalog.formatsOf('spreadsheet').map((o) => o.value), contains('json'));
    expect(catalog.formatsOf('palette').map((o) => o.value), contains('json'));

    // 别名命中：tif → tiff、jpeg → jpg、tar.gz → tar_gz、geo.json → geo_json
    expect(catalog.formatByExt('image', 'tif')?.value, 'tiff');
    expect(catalog.formatByExt('image', 'jpeg')?.value, 'jpg');
    expect(catalog.formatByExt('archive', 'tar.gz')?.value, 'tar_gz');
    expect(catalog.formatByExt('model3d', 'geo.json')?.value, 'geo_json');

    // 我的世界 4 个类型
    final mc = catalog.formatsOf('minecraft').map((o) => o.value).toList();
    expect(mc, containsAll(['mcworld', 'mcpack', 'mcworld_java', 'mcpack_java']));
  });

  testWidgets('配置页能渲染并识别输入格式行', (tester) async {
    await RegistryManager().initialize();
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: ConfigPage(initialFilePath: '/tmp/omniforge_probe.png'),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('转换配置'), findsOneWidget);
    expect(find.text('输入格式'), findsOneWidget);
    // 文件不存在时无法识别格式，应给出提示而不是崩溃
    expect(find.textContaining('无法识别该文件'), findsOneWidget);
    // 开始转换按钮在未选目标时禁用
    final button = tester.widget<TextButton>(find.widgetWithText(TextButton, '开始转换'));
    expect(button.onPressed, isNull);
  });
}
