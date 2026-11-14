import '../i_engine.dart';
import 'table_engine.dart';

/// 表格引擎：xlsx / csv / json / xml 互转。
/// 复用 [TableEngine] 的表结构解析与生成能力，独立 id 便于按类别注册。
class SpreadsheetEngine implements IEngine {
  const SpreadsheetEngine();

  @override
  String get id => 'spreadsheet';

  @override
  String? get requiredPluginId => null;

  @override
  Stream<EngineProgress> convert(EngineContext context) =>
      const TableEngine().convert(context);
}
