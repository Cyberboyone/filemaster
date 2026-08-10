import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Model + parser for .docx files, extracting the real document structure
/// (styled paragraphs, tables, inline images) so Word files can be shown
/// close to the original instead of flattened text.

enum DocxAlign { left, center, right, justify }

class DocxSpan {
  const DocxSpan({
    required this.text,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.sizePt = 11,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool underline;
  final double sizePt;
}

class DocxParagraph {
  const DocxParagraph({
    required this.spans,
    this.align = DocxAlign.left,
    this.indentLeftPt = 0,
    this.spaceBeforePt = 0,
    this.spaceAfterPt = 6,
    this.isHeading = false,
    this.headingLevel = 0,
    this.isPageBreak = false,
    this.drawings = const [],
  });

  final List<DocxSpan> spans;
  final DocxAlign align;
  final double indentLeftPt;
  final double spaceBeforePt;
  final double spaceAfterPt;
  final bool isHeading;
  final int headingLevel;
  final bool isPageBreak;

  /// Inline images (`a:blip` `r:embed`) inside this paragraph, with their
  /// declared size in drawing EMU (1/914400 inch), so rendering can match
  /// the size Word shows instead of using raw pixel dimensions.
  final List<DocxDrawing> drawings;

  String get plainText => spans.map((s) => s.text).join();
}

class DocxCell {
  const DocxCell({required this.paragraphs});

  final List<DocxParagraph> paragraphs;

  String get plainText => paragraphs.map((p) => p.plainText).join(' ');
}

class DocxRow {
  const DocxRow({required this.cells, this.isHeader = false});

  final List<DocxCell> cells;
  final bool isHeader;
}

class DocxTable {
  const DocxTable({required this.rows});

  final List<DocxRow> rows;
}

class DocxDrawing {
  const DocxDrawing({
    required this.rid,
    required this.cxEmu,
    required this.cyEmu,
  });

  final String rid;
  final int cxEmu;
  final int cyEmu;
}

class DocxPicture {
  const DocxPicture({required this.bytes, this.mime, this.widthPx, this.heightPx});

  final Uint8List bytes;
  final String? mime;

  /// Declared size from `wp:extent` in logical pixels (96 dpi), when known.
  final double? widthPx;
  final double? heightPx;
}

sealed class DocxBlock {
  const DocxBlock();
}

class DocxBlockParagraph extends DocxBlock {
  const DocxBlockParagraph(this.paragraph);

  final DocxParagraph paragraph;
}

class DocxBlockTable extends DocxBlock {
  const DocxBlockTable(this.table);

  final DocxTable table;
}

class DocxBlockPicture extends DocxBlock {
  const DocxBlockPicture(this.picture);

  final DocxPicture picture;
}

class ParsedDocx {
  const ParsedDocx({required this.blocks});

  final List<DocxBlock> blocks;
}

/// Parses a .docx file from disk.
Future<ParsedDocx> parseDocx(String path) async {
  final bytes = await File(path).readAsBytes();
  return parseDocxBytes(bytes);
}

/// Parses .docx bytes. Throws [FormatException] for invalid files.
ParsedDocx parseDocxBytes(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final xmlBytes = _readEntry(archive, 'word/document.xml');
  if (xmlBytes == null) {
    throw const FormatException('Not a Word document');
  }
  final relsBytes = _readEntry(archive, 'word/_rels/document.xml.rels');
  final document = XmlDocument.parse(utf8.decode(xmlBytes));
  final rels =
      relsBytes == null ? null : XmlDocument.parse(utf8.decode(relsBytes));

  final body = _childByLocal(document.rootElement, 'body');
  if (body == null) {
    throw const FormatException('Not a Word document');
  }

  final blocks = <DocxBlock>[];
  for (final node in body.childElements) {
    final name = node.name.local;
    try {
      if (name == 'p') {
        final paragraph = _parseParagraph(node);
        if (paragraph != null) {
          blocks.add(DocxBlockParagraph(paragraph));
        }
      } else if (name == 'tbl') {
        blocks.add(DocxBlockTable(_parseTable(node)));
      }
    } on FormatException {
      rethrow;
    } catch (_) {
      // A malformed block is skipped instead of failing the whole document.
    }
  }
  _attachPictures(blocks, rels, archive);
  return ParsedDocx(blocks: blocks);
}

List<int>? _readEntry(Archive archive, String name) {
  for (final entry in archive.files) {
    if (entry.name == name) return entry.content as List<int>?;
  }
  return null;
}

String? _attr(XmlElement element, String name) {
  final local = name.split(':').last;
  for (final attribute in element.attributes) {
    if (attribute.name.local == local) return attribute.value;
  }
  return null;
}

/// First direct child element whose local name matches [local].
XmlElement? _childByLocal(XmlElement element, String local) {
  for (final child in element.childElements) {
    if (child.name.local == local) return child;
  }
  return null;
}

DocxParagraph? _parseParagraph(XmlElement element) {
  final spans = <DocxSpan>[];
  var align = DocxAlign.left;
  var indentLeftPt = 0.0;
  var spaceBeforePt = 0.0;
  var spaceAfterPt = 6.0;
  var isHeading = false;
  var headingLevel = 0;
  var isPageBreak = false;
  final drawings = <DocxDrawing>[];

  final props = _childByLocal(element, 'pPr');
  if (props != null) {
    final jc = _childByLocal(props, 'jc');
    if (jc != null) {
      final val = _attr(jc, 'w:val') ?? 'left';
      align = switch (val) {
        'center' => DocxAlign.center,
        'right' => DocxAlign.right,
        'both' => DocxAlign.justify,
        'distribute' => DocxAlign.justify,
        _ => DocxAlign.left,
      };
    }
    final ind = _childByLocal(props, 'ind');
    if (ind != null) {
      final left = _attr(ind, 'w:left') ?? _attr(ind, 'w:start');
      if (left != null) indentLeftPt = _twipsToPt(double.tryParse(left) ?? 0);
    }
    final spacing = _childByLocal(props, 'spacing');
    if (spacing != null) {
      final before = _attr(spacing, 'w:before');
      if (before != null) {
        spaceBeforePt = _twipsToPt(double.tryParse(before) ?? 0);
      }
      final after = _attr(spacing, 'w:after');
      if (after != null) spaceAfterPt = _twipsToPt(double.tryParse(after) ?? 0);
    }
    final style = _childByLocal(props, 'pStyle');
    if (style != null) {
      final val = _attr(style, 'w:val')?.toLowerCase() ?? '';
      final match = RegExp(r'heading(\d)|^title$|subtitle').firstMatch(val);
      if (match != null) {
        isHeading = true;
        headingLevel = int.tryParse(match.group(1) ?? '') ?? 1;
      }
    }
    final outline = _childByLocal(props, 'outlineLvl');
    if (outline != null) {
      isHeading = true;
      headingLevel = (int.tryParse(_attr(outline, 'w:val') ?? '') ?? 0) + 1;
    }
    if (_childByLocal(props, 'pageBreakBefore') != null) isPageBreak = true;
  }

  for (final child in element.children) {
    if (child is! XmlElement) continue;
    final name = child.name.local;
if (name == 'r') {
      final span = _parseRun(child, drawings);
      if (span != null) spans.add(span);
    } else if (name == 'hyperlink') {
      for (final inner in child.childElements) {
        if (inner.name.local == 'r') {
          final span = _parseRun(inner, drawings);
          if (span != null) spans.add(span);
        }
      }
    }
  }

  if (spans.isEmpty && drawings.isEmpty && !isPageBreak) return null;
  return DocxParagraph(
    spans: spans,
    align: align,
    indentLeftPt: indentLeftPt,
    spaceBeforePt: spaceBeforePt,
    spaceAfterPt: spaceAfterPt,
    isHeading: isHeading,
    headingLevel: headingLevel,
    isPageBreak: isPageBreak,
    drawings: drawings,
  );
}

DocxSpan? _parseRun(XmlElement run, List<DocxDrawing> drawings) {
  final buffer = StringBuffer();
  var bold = false;
  var italic = false;
  var underline = false;
  var sizePt = 11.0;

  final props = _childByLocal(run, 'rPr');
  if (props != null) {
    final b = _childByLocal(props, 'b');
    if (b != null && _attr(b, 'w:val') != '0' && _attr(b, 'w:val') != 'false') {
      bold = true;
    }
    final i = _childByLocal(props, 'i');
    if (i != null && _attr(i, 'w:val') != '0' && _attr(i, 'w:val') != 'false') {
      italic = true;
    }
    if (_childByLocal(props, 'u') != null) underline = true;
    final sz = _childByLocal(props, 'sz');
    if (sz != null) {
      final halfPoints = int.tryParse(_attr(sz, 'w:val') ?? '');
      if (halfPoints != null) sizePt = halfPoints / 2;
    }
  }

  for (final child in run.children) {
    if (child is! XmlElement) continue;
    final name = child.name.local;
    if (name == 't' || name == 'delText') {
      buffer.write(child.innerText);
    } else if (name == 'tab') {
      buffer.write('  ');
    } else if (name == 'br') {
      if ((_attr(child, 'w:type') ?? 'textWrapping') == 'page') {
        buffer.write('\n\n');
      } else {
        buffer.write('\n');
      }
    } else if (name == 'drawing') {
      final blip = child
          .descendants
          .whereType<XmlElement>()
          .where((e) => e.name.local == 'blip')
          .firstOrNull;
      if (blip != null) {
        final embed = _attr(blip, 'r:embed');
        if (embed != null) {
          var cxEmu = 0;
          var cyEmu = 0;
          final extent = child
              .descendants
              .whereType<XmlElement>()
              .where((e) => e.name.local == 'extent')
              .firstOrNull;
          if (extent != null) {
            cxEmu = int.tryParse(_attr(extent, 'cx') ?? '') ?? 0;
            cyEmu = int.tryParse(_attr(extent, 'cy') ?? '') ?? 0;
          }
          drawings.add(
            DocxDrawing(rid: embed, cxEmu: cxEmu, cyEmu: cyEmu),
          );
        }
      }
    }
  }
  final text = buffer.toString();
  if (text.trim().isEmpty) return null;
  return DocxSpan(
    text: text,
    bold: bold,
    italic: italic,
    underline: underline,
    sizePt: sizePt,
  );
}

DocxTable _parseTable(XmlElement table) {
  final rows = <DocxRow>[];
  for (final rowNode in table.children) {
    if (rowNode is! XmlElement || rowNode.name.local != 'tr') continue;
    var isHeader = false;
    final trPr = _childByLocal(rowNode, 'trPr');
    if (trPr != null && _childByLocal(trPr, 'tblHeader') != null) {
      isHeader = true;
    }
    final cells = <DocxCell>[];
    for (final cellNode in rowNode.children) {
      if (cellNode is! XmlElement || cellNode.name.local != 'tc') continue;
      final paragraphs = <DocxParagraph>[];
      for (final pNode in cellNode.children) {
        if (pNode is XmlElement && pNode.name.local == 'p') {
          final paragraph = _parseParagraph(pNode);
          if (paragraph != null) paragraphs.add(paragraph);
        }
      }
      cells.add(DocxCell(paragraphs: paragraphs));
    }
    rows.add(DocxRow(cells: cells, isHeader: isHeader));
  }
  return DocxTable(rows: rows);
}

void _attachPictures(
  List<DocxBlock> blocks,
  XmlDocument? rels,
  Archive archive,
) {
  if (rels == null) return;

  final images = <String, ({String target, String? mime})>{};
  for (final rel in rels.rootElement.childElements) {
    final id = _attr(rel, 'Id');
    final type = _attr(rel, 'Type') ?? '';
    if (id == null || !type.contains('/image')) continue;
    final target = _attr(rel, 'Target');
    if (target == null) continue;
    final lower = target.toLowerCase();
    final mime = lower.endsWith('.png')
        ? 'image/png'
        : lower.endsWith('.jpeg') || lower.endsWith('.jpg')
        ? 'image/jpeg'
        : lower.endsWith('.gif')
        ? 'image/gif'
        : lower.endsWith('.bmp')
        ? 'image/bmp'
        : null;
    images[id] = (target: target, mime: mime);
  }
  if (images.isEmpty) return;

  final result = <DocxBlock>[];
  for (final block in blocks) {
    if (block is! DocxBlockParagraph) {
      result.add(block);
      continue;
    }
    final paragraph = block.paragraph;
    final drawing = paragraph.drawings
        .where((d) => images.containsKey(d.rid))
        .firstOrNull;
    if (drawing == null) {
      result.add(block);
      continue;
    }
    final image = images[drawing.rid]!;
    final entry = _readEntry(archive, _normalizeTarget(image.target));
    if (entry == null) {
      result.add(block);
      continue;
    }
    final picture = DocxPicture(
      bytes: Uint8List.fromList(entry),
      mime: image.mime,
      widthPx: drawing.cxEmu > 0 ? _emuToPx(drawing.cxEmu) : null,
      heightPx: drawing.cyEmu > 0 ? _emuToPx(drawing.cyEmu) : null,
    );
    result.add(DocxBlockPicture(picture));
  }
  blocks
    ..clear()
    ..addAll(result);
}

String _normalizeTarget(String target) {
  var clean = target.replaceAll('\\', '/');
  while (clean.startsWith('../')) {
    clean = clean.substring(3);
  }
  if (clean.startsWith('/')) clean = clean.substring(1);
  if (clean.startsWith('word/')) return clean;
  return 'word/$clean';
}

double _twipsToPt(double twips) => twips / 20;

double _emuToPx(int emu) => emu / 914400 * 96;