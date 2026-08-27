import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:file_master/models/recent_file.dart';
import 'package:file_master/screens/viewer_screen.dart';
import 'package:file_master/utils/doc_format.dart';

Future<void> _writeZip(String path, Map<String, String> entries) async {
  final archive = Archive();
  for (final entry in entries.entries) {
    archive.addFile(
      ArchiveFile(
        entry.key,
        entry.value.codeUnits.length,
        entry.value.codeUnits,
      ),
    );
  }
  final bytes = ZipEncoder().encode(archive);
  await File(path).writeAsBytes(bytes);
}

RecentFile _file({
  required String name,
  required String path,
  required DocFormat format,
}) {
  return RecentFile(
    name: name,
    path: path,
    format: format,
    sizeBytes: 0,
    lastOpened: DateTime.fromMillisecondsSinceEpoch(1000000),
  );
}

void main() {
  testWidgets('text viewer shows file content', (tester) async {
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('fm_viewer_test');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/notes.txt';
      await File(path).writeAsString('hello from file master');

      await tester.pumpWidget(
        MaterialApp(
          home: ViewerScreen(
            file: _file(name: 'notes.txt', path: path, format: DocFormat.text),
          ),
        ),
      );

      var attempts = 0;
      while (find.text('hello from file master').evaluate().isEmpty &&
          attempts < 750) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
        attempts++;
      }

      expect(find.text('hello from file master'), findsOneWidget);
    });
  });

  testWidgets('viewer reports missing files', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ViewerScreen(
          file: _file(
            name: 'gone.pdf',
            path: '/nonexistent/gone.pdf',
            format: DocFormat.pdf,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('This file could not be found on your device.'),
      findsOneWidget,
    );
  });

  testWidgets('corrupt office files are reported cleanly', (tester) async {
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('fm_viewer_test');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/deck.pptx';
      await File(path).writeAsString('placeholder');

      await tester.pumpWidget(
        MaterialApp(
          home: ViewerScreen(
            file: _file(
              name: 'deck.pptx',
              path: path,
              format: DocFormat.powerpoint,
            ),
          ),
        ),
      );

      const message =
          'Preview for PowerPoint files is not available. '
          'Use Share to open it in another app.';
      var attempts = 0;
      while (find.text(message).evaluate().isEmpty && attempts < 750) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
        attempts++;
      }

      expect(find.text(message), findsOneWidget);
      expect(find.text('Convert'), findsNothing);
    });
  });

  testWidgets('office files without text show an informative message', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('fm_viewer_test');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/empty.pptx';

      final emptySlide = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"/>
''';
      await _writeZip(path, {
        '[Content_Types].xml': '<Types/>',
        '_rels/.rels': '<Relationships/>',
        'ppt/slides/slide1.xml': emptySlide,
      });

      await tester.pumpWidget(
        MaterialApp(
          home: ViewerScreen(
            file: _file(
              name: 'empty.pptx',
              path: path,
              format: DocFormat.powerpoint,
            ),
          ),
        ),
      );

      const message =
          'Preview for PowerPoint files is not available. '
          'Use Share to open it in another app.';
      var attempts = 0;
      while (find.text(message).evaluate().isEmpty && attempts < 750) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
        attempts++;
      }

      expect(find.text(message), findsOneWidget);
      expect(find.text('Convert'), findsNothing);
    });
  });

  testWidgets('docx content is extracted and shown', (tester) async {
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('fm_viewer_test');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/notes.docx';

      final docXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p><w:r><w:t>Hello from a docx</w:t></w:r></w:p>
    <w:p><w:r><w:t>Second paragraph</w:t></w:r></w:p>
  </w:body>
</w:document>''';
      await _writeZip(path, {
        '[Content_Types].xml': '<Types/>',
        '_rels/.rels': '<Relationships/>',
        'word/document.xml': docXml,
      });

      await tester.pumpWidget(
        MaterialApp(
          home: ViewerScreen(
            file: _file(name: 'notes.docx', path: path, format: DocFormat.word),
          ),
        ),
      );

      var attempts = 0;
      while (find.textContaining('Hello from a docx').evaluate().isEmpty &&
          attempts < 750) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
        attempts++;
      }

      expect(find.textContaining('Hello from a docx'), findsOneWidget);
      expect(find.text('Save as PDF'), findsNothing);
    });
  });

  testWidgets('image viewer renders an image file', (tester) async {
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('fm_viewer_test');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/pic.png';
      await File(path).writeAsBytes([
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
        0x00,
        0x00,
        0x00,
        0x0D,
        0x49,
        0x48,
        0x44,
        0x52,
        0x00,
        0x00,
        0x00,
        0x01,
        0x00,
        0x00,
        0x00,
        0x01,
        0x08,
        0x06,
        0x00,
        0x00,
        0x00,
        0x1F,
        0x15,
        0xC4,
        0x89,
        0x00,
        0x00,
        0x00,
        0x0D,
        0x49,
        0x44,
        0x41,
        0x54,
        0x78,
        0x9C,
        0x62,
        0x00,
        0x01,
        0x00,
        0x00,
        0x05,
        0x00,
        0x01,
        0x0D,
        0x0A,
        0x2D,
        0xB4,
        0x00,
        0x00,
        0x00,
        0x00,
        0x49,
        0x45,
        0x4E,
        0x44,
        0xAE,
        0x42,
        0x60,
        0x82,
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: ViewerScreen(
            file: _file(name: 'pic.png', path: path, format: DocFormat.image),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Image), findsOneWidget);
      expect(find.text('This image could not be displayed'), findsNothing);
    });
  });
}
