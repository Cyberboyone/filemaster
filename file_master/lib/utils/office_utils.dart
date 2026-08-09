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
    if (lower.endsWith('.xlsx')) return _xlsxText(bytes);
    if (lower.endsWith('.pptx')) return _pptxText(bytes);
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

String _xlsxText(Uint8List bytes) {
  final archive = _openZip(bytes);

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

  final sheetNames =
      archive.files
          .map((e) => e.name)
          .where(
            (name) => RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(name),
          )
          .toList()
        ..sort();
  if (sheetNames.isEmpty) {
    throw const FormatException('Corrupt or unreadable Excel file');
  }
  final buffer = StringBuffer();
  for (final name in sheetNames) {
    final xml = _readEntry(archive, name);
    if (xml == null) continue;
    final sheetXml = utf8.decode(xml);
    final rowTexts = <String>[];
    for (final row in RegExp(
      r'<row[ >](.*?)</row>',
      dotAll: true,
    ).allMatches(sheetXml)) {
      final cells = <String>[];
      for (final cell in RegExp(
        r'<c(.*?)>(.*?)</c>',
        dotAll: true,
      ).allMatches(row.group(1)!)) {
        final attributes = cell.group(1) ?? '';
        final inner = cell.group(2) ?? '';
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
        if (attributes.contains('t="s"')) {
          final index = int.tryParse(text);
          text = (index != null && index >= 0 && index < shared.length)
              ? shared[index]
              : '';
        }
        if (text.isNotEmpty) cells.add(_decodeEntities(text).trim());
      }
      if (cells.isNotEmpty) rowTexts.add(cells.join('\t'));
    }
    if (rowTexts.isNotEmpty) buffer.writeln(rowTexts.join('\n'));
  }
  return _normalizeWhitespace(buffer.toString());
}
