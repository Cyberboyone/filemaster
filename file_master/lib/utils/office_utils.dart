import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Extracts readable text from Office files (.docx, .xlsx, .pptx) so they
/// can be converted to PDF without a full document engine. Styling is not
/// preserved; table cells are separated with tabs and rows with newlines.
Future<String> extractOfficeText(String path) async {
  final bytes = await File(path).readAsBytes();
  final lower = path.toLowerCase();
  try {
    if (lower.endsWith('.docx')) return _docxText(bytes);
    if (lower.endsWith('.xlsx') ||
        lower.endsWith('.xls') ||
        lower.endsWith('.csv')) {
      return _xlsxText(bytes);
    }
    if (lower.endsWith('.pptx') || lower.endsWith('.ppt')) {
      return _pptxText(bytes);
    }
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException('Corrupt or unreadable Office file');
  }
  throw UnsupportedError('Not an Office file: $path');
}

Archive _openZip(Uint8List bytes) => ZipDecoder().decodeBytes(bytes);

List<int>? _readEntry(Archive archive, String name) {
  for (final entry in archive.files) {
    if (entry.name == name) {
      return entry.content as List<int>?;
    }
  }
  return null;
}

String _stripTags(String xml) {
  final text = xml
      .replaceAll('</w:p>', '\n')
      .replaceAll('</a:p>', '\n')
      .replaceAll('</w:tr>', '\n')
      .replaceAll('</w:tc>', '\t')
      .replaceAll(RegExp(r'<[^>]+>'), '');
  return _decodeEntities(text);
}

String _decodeEntities(String input) {
  return input
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&#10;', '\n')
      .replaceAllMapped(RegExp(r'&#(\d+);'), (Match m) {
        final code = int.tryParse(m.group(1)!);
        return code == null ? '' : String.fromCharCode(code);
      });
}

String _normalizeWhitespace(String text) {
  final lines = text
      .split('\n')
      .map((line) => line.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
      .toList();
  final collapsed = <String>[];
  for (final line in lines) {
    if (line.isEmpty && collapsed.isNotEmpty && collapsed.last.isEmpty) {
      continue;
    }
    collapsed.add(line);
  }
  return collapsed.join('\n').trim();
}

String _docxText(Uint8List bytes) {
  final xml = _readEntry(_openZip(bytes), 'word/document.xml');
  if (xml == null) throw const FormatException('No document.xml in docx');
  return _normalizeWhitespace(_stripTags(utf8.decode(xml)));
}

String _pptxText(Uint8List bytes) {
  final archive = _openZip(bytes);
  final slideNames =
      archive.files
          .map((e) => e.name)
          .where((name) => RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(name))
          .toList()
        ..sort((a, b) {
          final na = int.parse(RegExp(r'(\d+)').firstMatch(a)!.group(1)!);
          final nb = int.parse(RegExp(r'(\d+)').firstMatch(b)!.group(1)!);
          return na.compareTo(nb);
        });
  if (slideNames.isEmpty) {
    throw const FormatException('Corrupt or unreadable PowerPoint file');
  }

  final buffer = StringBuffer();
  for (final name in slideNames) {
    final xml = _readEntry(archive, name);
    if (xml == null) continue;
    final plain = _stripTags(utf8.decode(xml)).trim();
    if (plain.isNotEmpty) buffer.writeln(plain);
    buffer.writeln();
  }
  return _normalizeWhitespace(buffer.toString());
}

/// Parses a cell reference like "B15" into (column, row) where column is 0-based.
(int, int)? _parseCellRef(String ref) {
  final match = RegExp(r'^([A-Z]+)(\d+)$').firstMatch(ref);
  if (match == null) return null;
  final colStr = match.group(1)!;
  var col = 0;
  for (var i = 0; i < colStr.length; i++) {
    col = col * 26 + (colStr.codeUnitAt(i) - 64);
  }
  col -= 1;
  final row = int.parse(match.group(2)!) - 1;
  return (col, row);
}

/// Extracts Excel sheets as structured data: list of sheets, each with
/// a name and a 2D grid of cell values.
List<ExcelSheet> extractExcelSheets(Uint8List bytes) {
  final archive = _openZip(bytes);

  // Read shared strings
  final shared = <String>[];
  final sst = _readEntry(archive, 'xl/sharedStrings.xml');
  if (sst != null) {
    final sstXml = utf8.decode(sst);
    for (final match in RegExp(
      r'<si>(.*?)</si>',
      dotAll: true,
    ).allMatches(sstXml)) {
      shared.add(_stripTags(match.group(1)!).trim());
    }
  }

  // Read workbook for sheet names
  final sheetNames = <String>[];
  final wb = _readEntry(archive, 'xl/workbook.xml');
  if (wb != null) {
    final wbXml = utf8.decode(wb);
    for (final m in RegExp(r'<sheet[^>]+name="([^"]+)"').allMatches(wbXml)) {
      sheetNames.add(m.group(1)!);
    }
  }

  // Find sheet XML files
  final sheetFiles =
      archive.files
          .map((e) => e.name)
          .where(
            (name) => RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(name),
          )
          .toList()
        ..sort();

  final sheets = <ExcelSheet>[];
  for (var i = 0; i < sheetFiles.length; i++) {
    final xml = _readEntry(archive, sheetFiles[i]);
    if (xml == null) continue;
    final sheetXml = utf8.decode(xml);
    final name = i < sheetNames.length ? sheetNames[i] : 'Sheet ${i + 1}';

    // Parse cells
    int maxCol = 0;
    int maxRow = 0;
    final cells = <String, String>{};

    for (final cell in RegExp(
      r'<c ([^>]*?)>(.*?)</c>',
      dotAll: true,
    ).allMatches(sheetXml)) {
      final attrs = cell.group(1) ?? '';
      final inner = cell.group(2) ?? '';

      // Extract r="A1" attribute
      final refMatch = RegExp(r'r="([A-Z]+\d+)"').firstMatch(attrs);
      if (refMatch == null) continue;
      final ref = refMatch.group(1)!;
      final parsed = _parseCellRef(ref);
      if (parsed == null) continue;
      final col = parsed.$1;
      final row = parsed.$2;

      final inline = RegExp(
        r'<t[^>]*>(.*?)</t>',
        dotAll: true,
      ).firstMatch(inner)?.group(1);
      final value = RegExp(
        r'<v>(.*?)</v>',
        dotAll: true,
      ).firstMatch(inner)?.group(1);

      var text = inline ?? value ?? '';
      if (text.isEmpty) continue;

      // Resolve shared strings
      if (attrs.contains('t="s"')) {
        final index = int.tryParse(text);
        text = (index != null && index >= 0 && index < shared.length)
            ? shared[index]
            : '';
      }
      // Handle boolean values
      if (attrs.contains('t="b"')) {
        text = text == '1' ? 'TRUE' : 'FALSE';
      }

      if (text.isNotEmpty) {
        cells['$col,$row'] = _decodeEntities(text).trim();
        if (col > maxCol) maxCol = col;
        if (row > maxRow) maxRow = row;
      }
    }

    // Build grid
    final grid = <List<String>>[];
    for (var r = 0; r <= maxRow; r++) {
      final rowData = <String>[];
      for (var c = 0; c <= maxCol; c++) {
        rowData.add(cells['$c,$r'] ?? '');
      }
      grid.add(rowData);
    }

    sheets.add(ExcelSheet(name: name, rows: grid));
  }

  if (sheets.isEmpty) {
    // Fallback to text extraction
    final text = _xlsxText(bytes);
    return [
      ExcelSheet(
        name: 'Sheet 1',
        rows: [
          [text],
        ],
      ),
    ];
  }

  return sheets;
}

String _xlsxText(Uint8List bytes) {
  final sheets = extractExcelSheets(bytes);
  final buffer = StringBuffer();
  for (final sheet in sheets) {
    buffer.writeln('--- ${sheet.name} ---');
    for (final row in sheet.rows) {
      buffer.writeln(row.join('\t'));
    }
    buffer.writeln();
  }
  return _normalizeWhitespace(buffer.toString());
}

/// Extracts PowerPoint slides as structured data with index and text content.
List<PptxSlide> extractPptxSlides(Uint8List bytes) {
  final archive = _openZip(bytes);
  final slideNames =
      archive.files
          .map((e) => e.name)
          .where((name) => RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(name))
          .toList()
        ..sort((a, b) {
          final na = int.parse(RegExp(r'(\d+)').firstMatch(a)!.group(1)!);
          final nb = int.parse(RegExp(r'(\d+)').firstMatch(b)!.group(1)!);
          return na.compareTo(nb);
        });

  final slides = <PptxSlide>[];
  for (var i = 0; i < slideNames.length; i++) {
    final xml = _readEntry(archive, slideNames[i]);
    if (xml == null) continue;
    final plain = _stripTags(utf8.decode(xml)).trim();
    slides.add(PptxSlide(index: i + 1, content: plain));
  }
  return slides;
}

/// Structured Excel sheet data.
class ExcelSheet {
  const ExcelSheet({required this.name, required this.rows});

  final String name;
  final List<List<String>> rows;

  int get rowCount => rows.length;
  int get colCount => rows.isEmpty ? 0 : rows.first.length;
}

/// Structured PowerPoint slide data.
class PptxSlide {
  const PptxSlide({required this.index, required this.content});

  final int index;
  final String content;
}
