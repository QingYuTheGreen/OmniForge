import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../common/package_io.dart';
import '../common/text_format.dart';
import '../engine_utils.dart';
import '../i_engine.dart';

/// 图片 → Word 文档（.docx，内嵌图片）引擎（纯 Dart）。
///
/// 构造最小可用 OOXML 包：`[Content_Types].xml`、`_rels/.rels`、
/// `word/document.xml`、`word/_rels/document.xml.rels` 与
/// `word/media/image1.png`，正文里用标准 DrawingML
/// `<w:drawing><wp:inline>` 内嵌图片。图片统一重编码为 PNG，
/// 尺寸按 96 DPI 做像素→EMU 换算（1 px = 9525 EMU）。
///
/// 参数：
/// - `width`（int，默认 0）：0 表示使用图片原宽；>0 时按比例缩放到该宽度
///   （clamp 16..20000）。
/// - `align`（string，默认 'center'）：段落对齐，仅支持 left / center / right。
/// - `caption`（string，默认空）：非空时在图片下方追加一段说明文字。
class ImageDocEngine extends SimpleEngine {
  const ImageDocEngine();

  @override
  String get id => 'image_doc';

  /// 96 DPI 下 1 像素对应的 EMU。
  static const int _emuPerPixel = 9525;

  /// 缩放宽度的允许区间（像素）。
  static const int _minWidth = 16;
  static const int _maxWidth = 20000;

  /// A4 页面尺寸（twip，1/20 pt）。
  static const int _pageWidthTwips = 11906;
  static const int _pageHeightTwips = 16838;

  /// A4 默认页边距（twip，1 英寸 = 1440 twip）。
  static const int _marginTwips = 1440;

  @override
  void validate(EngineContext context) {
    if (context.targetFormat.toLowerCase() != 'docx') {
      throw const EngineException('image_doc 仅支持 docx 输出');
    }
  }

  @override
  Future<void> execute(EngineContext context) async {
    final target = context.targetFormat.toLowerCase();
    if (target != 'docx') {
      throw const EngineException('image_doc 仅支持 docx 输出');
    }

    final source = await readFileBytes(context.inputPath);
    var image = img.decodeImage(source);
    if (image == null) {
      throw EngineException('无法解码输入图片：${context.inputPath}');
    }

    // width > 0 时按比例缩放到目标宽度；0 / 负数表示沿用原宽。
    final requestedWidth = intParam(context, 'width', 0);
    if (requestedWidth > 0) {
      final targetWidth = requestedWidth.clamp(_minWidth, _maxWidth);
      if (targetWidth != image.width) {
        image = img.copyResize(
          image,
          width: targetWidth,
          interpolation: img.Interpolation.cubic,
        );
      }
    }

    final align = _normalizeAlign(stringParam(context, 'align', 'center'));
    final caption = stringParam(context, 'caption');

    // 统一重编码为 PNG（docx 内只放 PNG 媒体，避免解码器差异）。
    final media = Uint8List.fromList(img.encodePng(image));

    final widthEmu = image.width * _emuPerPixel;
    final heightEmu = image.height * _emuPerPixel;

    final documentXml = _documentXml(
      widthEmu: widthEmu,
      heightEmu: heightEmu,
      align: align,
      caption: caption,
    );

    final entries = <PackageEntry>[
      _textEntry('[Content_Types].xml', _contentTypesXml),
      _textEntry('_rels/.rels', _rootRelsXml),
      _textEntry('word/document.xml', documentXml),
      _textEntry('word/_rels/document.xml.rels', _documentRelsXml),
      PackageEntry('word/media/image1.png', media),
    ];
    await writeFileBytes(
      context.outputPath,
      ZipPackage.encodeEntries(entries),
    );
  }

  /// 只接受 left / center / right，其它值回退到 center。
  String _normalizeAlign(String value) {
    return switch (value.toLowerCase()) {
      'left' => 'left',
      'right' => 'right',
      _ => 'center',
    };
  }

  PackageEntry _textEntry(String name, String content) =>
      PackageEntry(name, Uint8List.fromList(utf8.encode(content)));

  String _documentXml({
    required int widthEmu,
    required int heightEmu,
    required String align,
    required String caption,
  }) {
    final captionXml = caption.isEmpty
        ? ''
        : '<w:p><w:pPr><w:jc w:val="$align"/></w:pPr>'
            '<w:r><w:rPr><w:sz w:val="18"/></w:rPr>'
            '<w:t xml:space="preserve">${escapeXml(caption)}</w:t></w:r></w:p>';
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document '
        'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
        'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
        '<w:body>'
        '<w:p>'
        '<w:pPr><w:jc w:val="$align"/><w:spacing w:after="0"/></w:pPr>'
        '<w:r><w:drawing>'
        '<wp:inline distT="0" distB="0" distL="0" distR="0">'
        '<wp:extent cx="$widthEmu" cy="$heightEmu"/>'
        '<wp:effectExtent l="0" t="0" r="0" b="0"/>'
        '<wp:docPr id="1" name="Picture 1" descr="OmniForge image"/>'
        '<wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="1"/>'
        '</wp:cNvGraphicFramePr>'
        '<a:graphic>'
        '<a:graphicData '
        'uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:pic '
        'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:nvPicPr><pic:cNvPr id="1" name="image1.png"/><pic:cNvPicPr/>'
        '</pic:nvPicPr>'
        '<pic:blipFill><a:blip r:embed="rId1"/>'
        '<a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
        '<pic:spPr><a:xfrm><a:off x="0" y="0"/>'
        '<a:ext cx="$widthEmu" cy="$heightEmu"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>'
        '</pic:pic>'
        '</a:graphicData>'
        '</a:graphic>'
        '</wp:inline>'
        '</w:drawing></w:r>'
        '</w:p>'
        '$captionXml'
        '<w:sectPr>'
        '<w:pgSz w:w="$_pageWidthTwips" w:h="$_pageHeightTwips"/>'
        '<w:pgMar w:top="$_marginTwips" w:right="$_marginTwips" '
        'w:bottom="$_marginTwips" w:left="$_marginTwips" '
        'w:header="708" w:footer="708" w:gutter="0"/>'
        '</w:sectPr>'
        '</w:body></w:document>';
  }

  static const String _contentTypesXml =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Default Extension="png" ContentType="image/png"/>'
      '<Default Extension="jpeg" ContentType="image/jpeg"/>'
      '<Override PartName="/word/document.xml" '
      'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
      '</Types>';

  static const String _rootRelsXml =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
      'Target="word/document.xml"/>'
      '</Relationships>';

  static const String _documentRelsXml =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" '
      'Target="media/image1.png"/>'
      '</Relationships>';
}
