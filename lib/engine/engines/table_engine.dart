import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import 'package:xml/xml.dart';

import '../common/package_io.dart';
import '../engine_utils.dart';
import '../i_engine.dart';

/// 表格数据：表头 + 行。
class TableData {
  final List<String> headers;
  final List<List<String>> rows;

  TableData(this.headers, this.rows);

  factory TableData.empty() => TableData(const [], const []);

  /// 补齐每行的列数，保证导出时不丢列。
  TableData normalized() {
    final width = headers.length;
    final fixed = rows
        .map((row) => List<String>.from(row)
          ..addAll(List.filled(
            (width - row.length).clamp(0, width),
            '',
          )))
        .toList();
    return TableData(headers, fixed);
  }
}

/// 表格引擎：csv / json / xml / xlsx 互转（纯 Dart）。
class TableEngine extends SimpleEngine {
  const TableEngine();

  @override
  String get id => 'table';

  @override
  Future<void> execute(EngineContext context) async {
    final source = _sourceFormat(context);
    final table = source == 'xlsx'
        ? _readXlsx(await readFileBytes(context.inputPath), context)
        : _readText(source, context);
    if (table.headers.isEmpty && table.rows.isEmpty) {
      throw const EngineException('没有从输入文件里解析到表格数据');
    }
    final target = context.targetFormat.toLowerCase();
    switch (target) {
      case 'xlsx':
        await writeFileBytes(
          context.outputPath,
          _writeXlsx(table.normalized(), inputStem(context)),
        );
      case 'csv':
        await writeFileText(
          context.outputPath,
          ListToCsvConverter(
            eol: '\n',
          ).convert([
            table.headers,
            ...table.rows,
          ]),
        );
      case 'json':
        await writeFileText(
          context.outputPath,
          const JsonEncoder.withIndent('  ').convert(_toJson(table)),
        );
      case 'xml':
        await writeFileText(
          context.outputPath,
          _toXml(table, stringParam(context, 'root', 'table')),
        );
      default:
        throw EngineException('表格引擎不支持输出格式：$target');
    }
  }

  String _sourceFormat(EngineContext context) {
    final ext = inputExtension(context);
    if (ext == 'xlsx') return 'xlsx';
    if (ext == 'json') return 'json';
    if (ext == 'xml') return 'xml';
    if (ext == 'csv') return 'csv';
    // 通过目标格式之外的线索兜底
    return ext.isEmpty ? 'csv' : ext;
  }

  // ─────────────────────────── 文本格式读取 ───────────────────────────

  TableData _readText(String source, EngineContext context) {
    return switch (source) {
      'json' => _readJson(context),
      'xml' => _readXml(context),
      _ => _readCsv(context),
    };
  }

  TableData _readCsvFromString(String text, EngineContext context) {
    final rows = CsvToListConverter(
      eol: '\n',
      shouldParseNumbers: false,
    ).convert(text.replaceAll('\r\n', '\n'));
    if (rows.isEmpty) return TableData.empty();
    final rawHeaders = rows.first.map((e) => e.toString()).toList();
    final data = rows.skip(1).map((row) {
      return row.map((e) => e?.toString() ?? '').toList();
    }).toList();
    final width = data.fold<int>(rawHeaders.length,
        (prev, row) => row.length > prev ? row.length : prev);
    final headers = List<String>.from(rawHeaders);
    while (headers.length < width) {
      headers.add('column${headers.length + 1}');
    }
    return TableData(headers, data);
  }

  TableData _readCsv(EngineContext context) {
    final bytes = File(context.inputPath).readAsBytesSync();
    return _readCsvFromString(
      utf8.decode(bytes, allowMalformed: true),
      context,
    );
  }

  TableData _readJson(EngineContext context) {
    final bytes = File(context.inputPath).readAsBytesSync();
    final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
    List<dynamic> list;
    if (decoded is List) {
      list = decoded;
    } else if (decoded is Map && decoded['data'] is List) {
      list = decoded['data'] as List;
    } else if (decoded is Map) {
      list = decoded.values.toList();
    } else {
      list = [decoded];
    }
    final headers = <String>[];
    final rows = <List<String>>[];
    for (final item in list) {
      if (item is Map) {
        for (final key in item.keys) {
          final name = key.toString();
          if (!headers.contains(name)) headers.add(name);
        }
      }
    }
    if (headers.isEmpty) {
      for (final item in list) {
        rows.add([item?.toString() ?? '']);
      }
      return TableData(const ['value'], rows);
    }
    for (final item in list) {
      if (item is! Map) continue;
      rows.add([
        for (final header in headers)
          _stringify(item[header]),
      ]);
    }
    return TableData(headers, rows);
  }

  TableData _readXml(EngineContext context) {
    final text = utf8.decode(
      File(context.inputPath).readAsBytesSync(),
      allowMalformed: true,
    );
    final document = XmlDocument.parse(text);
    final rowElements = document.descendantElements
        .where((e) => e.localName == 'row' || e.localName == 'tr')
        .toList();
    if (rowElements.isEmpty) return TableData.empty();
    final headers = <String>[];
    final rows = <List<String>>[];
    var first = true;
    for (final row in rowElements) {
      final cells = row.childElements.toList();
      if (cells.isEmpty) continue;
      final values = cells.map((c) {
        final label = c.getAttribute('name') ?? c.getAttribute('key');
        return label ?? c.innerText.trim();
      }).toList();
      if (first) {
        headers.addAll(values.map((v) => v.isEmpty ? 'column${headers.length + 1}' : v));
        first = false;
        continue;
      }
      rows.add(cells.map((c) => c.innerText.trim()).toList());
    }
    return TableData(headers, rows);
  }

  // ─────────────────────────── XLSX 读取 ───────────────────────────

  TableData _readXlsx(Uint8List bytes, EngineContext context) {
    final package = ZipPackage.decode(bytes);
    final sharedStrings = <String>[];
    for (final name in package.names) {
      if (!name.endsWith('sharedStrings.xml')) continue;
      final doc = XmlDocument.parse(package.textOf(name) ?? '');
      for (final si in doc.descendantElements.where((e) => e.localName == 'si')) {
        sharedStrings.add(si.descendantElements
            .where((e) => e.localName == 't')
            .map((e) => e.innerText)
            .join());
      }
    }

    String? sheetName;
    for (final name in package.names) {
      if (name.startsWith('xl/worksheets/') && name.endsWith('.xml')) {
        if (sheetName == null || name.compareTo(sheetName) < 0) {
          sheetName = name;
        }
      }
    }
    if (sheetName == null) {
      throw const EngineException('xlsx 中没有找到工作表');
    }

    final doc = XmlDocument.parse(package.textOf(sheetName) ?? '');
    final rawRows = <int, List<String>>{};
    var maxColumn = 0;
    for (final rowElement in doc.descendantElements.where((e) => e.localName == 'row')) {
      final rowIndex =
          int.tryParse(rowElement.getAttribute('r') ?? '') ?? rawRows.length + 1;
      final values = <int, String>{};
      for (final cell in rowElement.childElements.where((e) => e.localName == 'c')) {
        final ref = cell.getAttribute('r') ?? '';
        final column = _columnIndex(ref);
        final type = cell.getAttribute('t');
        String value = '';
        if (type == 's') {
          final indexText = cell.descendantElements
              .where((e) => e.localName == 'v')
              .map((e) => e.innerText)
              .join();
          final index = int.tryParse(indexText);
          if (index != null && index >= 0 && index < sharedStrings.length) {
            value = sharedStrings[index];
          }
        } else if (type == 'inlineStr') {
          value = cell.descendantElements
              .where((e) => e.localName == 't')
              .map((e) => e.innerText)
              .join();
        } else {
          value = cell.descendantElements
              .where((e) => e.localName == 'v')
              .map((e) => e.innerText)
              .join();
        }
        values[column] = value;
        if (column + 1 > maxColumn) maxColumn = column + 1;
      }
      final row = List<String>.filled(maxColumn, '');
      for (final entry in values.entries) {
        row[entry.key] = entry.value;
      }
      rawRows[rowIndex] = row;
    }

    final sortedKeys = rawRows.keys.toList()..sort();
    if (sortedKeys.isEmpty) return TableData.empty();
    final width = maxColumn;
    final headers = List<String>.from(rawRows[sortedKeys.first] ?? List.filled(width, ''));
    for (var i = 0; i < width; i++) {
      if (i >= headers.length || headers[i].isEmpty) {
        headers.length <= i ? headers.add('column${i + 1}') : headers[i] = 'column${i + 1}';
      }
    }
    final rows = <List<String>>[];
    for (final key in sortedKeys.skip(1)) {
      final row = List<String>.from(rawRows[key] ?? List.filled(width, ''));
      while (row.length < width) {
        row.add('');
      }
      rows.add(row);
    }
    return TableData(headers, rows);
  }

  int _columnIndex(String ref) {
    var value = 0;
    for (var i = 0; i < ref.length; i++) {
      final code = ref.codeUnitAt(i);
      if (code < 65 || code > 90) break;
      value = value * 26 + (code - 64);
    }
    return value == 0 ? 0 : value - 1;
  }

  // ─────────────────────────── XLSX 写入 ───────────────────────────

  Uint8List _writeXlsx(TableData table, String sheetName) {
    String escape(String value) => value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');

    String columnName(int index) {
      var value = index + 1;
      var name = '';
      while (value > 0) {
        final remainder = (value - 1) % 26;
        name = String.fromCharCode(65 + remainder) + name;
        value = (value - 1) ~/ 26;
      }
      return name;
    }

    final rowsXml = StringBuffer();
    final allRows = [table.headers, ...table.rows];
    for (var r = 0; r < allRows.length; r++) {
      rowsXml.write('<row r="${r + 1}">');
      final row = allRows[r];
      for (var c = 0; c < row.length; c++) {
        final ref = '${columnName(c)}${r + 1}';
        final value = escape(row[c]);
        rowsXml.write(
          '<c r="$ref" t="inlineStr"><is><t xml:space="preserve">$value</t></is></c>',
        );
      }
      rowsXml.write('</row>');
    }

    final archive = Archive()
      ..add(ArchiveFile(
        '[Content_Types].xml',
        0,
        utf8.encode(
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
          '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
          '<Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
          '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
          '</Types>',
        ),
      ))
      ..add(ArchiveFile(
        '_rels/.rels',
        0,
        utf8.encode(
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
          '</Relationships>',
        ),
      ))
      ..add(ArchiveFile(
        'xl/workbook.xml',
        0,
        utf8.encode(
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
          'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
          '<sheets><sheet name="${escape(sheetName)}" sheetId="1" r:id="rId1"/></sheets>'
          '</workbook>',
        ),
      ))
      ..add(ArchiveFile(
        'xl/_rels/workbook.xml.rels',
        0,
        utf8.encode(
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
          '</Relationships>',
        ),
      ))
      ..add(ArchiveFile(
        'xl/worksheets/sheet1.xml',
        0,
        utf8.encode(
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
          '<sheetData>$rowsXml</sheetData></worksheet>',
        ),
      ));
    return ZipEncoder().encodeBytes(archive);
  }

  // ─────────────────────────── 输出辅助 ───────────────────────────

  Object _toJson(TableData table) {
    return table.rows.map((row) {
      final map = <String, String>{};
      for (var i = 0; i < table.headers.length; i++) {
        map[table.headers[i]] = i < row.length ? row[i] : '';
      }
      return map;
    }).toList();
  }

  String _toXml(TableData table, String root) {
    String escape(String value) => value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<$root>');
    for (final row in table.rows) {
      buffer.write('  <row>');
      for (var i = 0; i < table.headers.length; i++) {
        final name = _xmlName(table.headers[i]);
        buffer.write(
          '<$name>${escape(i < row.length ? row[i] : '')}</$name>',
        );
      }
      buffer.writeln('</row>');
    }
    buffer.writeln('</$root>');
    return buffer.toString();
  }

  String _xmlName(String header) {
    final cleaned = header
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_\-.]'), '_');
    if (cleaned.isEmpty) return 'field';
    if (RegExp(r'^[0-9.]').hasMatch(cleaned)) return 'field_$cleaned';
    return cleaned;
  }

  String _stringify(Object? value) {
    if (value == null) return '';
    if (value is String) return value;
    if (value is num || value is bool) return value.toString();
    return jsonEncode(value);
  }

}

/// 电子表格引擎：与 [TableEngine] 共用实现，保留独立 id 便于 YAML 引用。
