import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:file_master/utils/docx_parser.dart';
import 'package:file_master/widgets/docx_document_view.dart';

const _tinyPng = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x62, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

String _docXml({bool withTable = false}) {
  return '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
            xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
            xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
  <w:body>
    <w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr>
      <w:r><w:t>Project report</w:t></w:r></w:p>
    <w:p><w:pPr><w:jc w:val="center"/></w:pPr>
      <w:r><w:rPr><w:b/></w:rPr><w:t>Bold centered line</w:t></w:r></w:p>
    <w:p><w:pPr><w:spacing w:before="120" w:after="120"/></w:pPr>
      <w:r><w:rPr><w:i/><w:u/></w:rPr><w:t>Italic underlined</w:t></w:r>
      <w:r><w:t> plus plain.</w:t></w:r></w:p>
    <w:p>
      <w:r><w:t>Image below:</w:t></w:r>
      <w:r>
        <w:drawing>
          <wp:inline xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
                     distT="0" distB="0" distL="0" distR="0">
            <a:graphic><a:graphicData>
              <pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">
                <pic:blipFill><a:blip r:embed="rId10"/></pic:blipFill>
              </pic:pic>
            </a:graphicData></a:graphic>
          </wp:inline>
        </w:drawing>
      </w:r>
    </w:p>
    ${withTable ? '''
    <w:tbl>
      <w:tr><w:trPr><w:tblHeader/></w:trPr>
        <w:tc><w:p><w:r><w:t>Name</w:t></w:r></w:p></w:tc>
        <w:tc><w:p><w:r><w:t>Total</w:t></w:r></w:p></w:tc>
      </w:tr>
      <w:tr>
        <w:tc><w:p><w:r><w:t>Alpha</w:t></w:r></w:p></w:tc>
        <w:tc><w:p><w:r><w:t>42</w:t></w:r></w:p></w:tc>
      </w:tr>
    </w:tbl>''' : ''}
  </w:body>
</w:document>''';
}

String _relsXml() {
  return '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId10" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/image1.png"/>
</Relationships>''';
}

Future<File> _writeDocx(String path, {bool table = false}) async {
  final archive = Archive();
  void add(String name, List<int> bytes) =>
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
  add('[Content_Types].xml', '<Types/>'.codeUnits);
  add('_rels/.rels', '<Relationships/>'.codeUnits);
  add(
    'word/document.xml',
    _docXml(withTable: table).codeUnits,
  );
  add('word/_rels/document.xml.rels', _relsXml().codeUnits);
  add('word/media/image1.png', _tinyPng);
  final bytes = ZipEncoder().encode(archive);
  final file = File(path);
  await file.writeAsBytes(bytes);
  return file;
}

void main() {
  group('docx parser', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('fm_docx_test');
    });

    tearDown(() async {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    });

    test('parses headings, alignment, formatting and tables', () async {
      final path = '${dir.path}/sample.docx';
      await _writeDocx(path, table: true);

      final parsed = await parseDocx(path);
      expect(parsed.blocks, isNotEmpty);

      final heading = parsed.blocks.first as DocxBlockParagraph;
      expect(heading.paragraph.isHeading, isTrue);
      expect(heading.paragraph.plainText, 'Project report');

      final centered = parsed.blocks[1] as DocxBlockParagraph;
      expect(centered.paragraph.align, DocxAlign.center);
      expect(centered.paragraph.spans.first.bold, isTrue);

      final formatted = parsed.blocks[2] as DocxBlockParagraph;
      expect(formatted.paragraph.spans.first.italic, isTrue);
      expect(formatted.paragraph.spans.first.underline, isTrue);
      expect(formatted.paragraph.spans.length, greaterThanOrEqualTo(2));

      final table = parsed.blocks
          .whereType<DocxBlockTable>()
          .first
          .table;
      expect(table.rows, hasLength(2));
      expect(table.rows.first.isHeader, isTrue);
      expect(table.rows.first.cells.first.plainText, 'Name');
      expect(table.rows.last.cells.last.plainText, '42');
    });

    test('extracts inline images from media entries', () async {
      final path = '${dir.path}/pics.docx';
      await _writeDocx(path);

      final parsed = await parseDocx(path);
      final picture = parsed.blocks.whereType<DocxBlockPicture>().firstOrNull;
      expect(picture, isNotNull);
      expect(picture!.picture.mime, 'image/png');
      expect(picture.picture.bytes, isNotEmpty);
    });

    test('rejects files that are not docx', () async {
      final path = '${dir.path}/bad.docx';
      await File(path).writeAsString('not a zip');
      expect(() => parseDocx(path), throwsFormatException);
    });
  });

  group('docx document view', () {
    testWidgets('renders content, table and image as word-like page',
        (tester) async {
      await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp('fm_docx_widget');
        addTearDown(() async {
          try {
            await dir.delete(recursive: true);
          } catch (_) {}
        });
        final path = '${dir.path}/sample.docx';
        await _writeDocx(path, table: true);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DocxDocumentView(path: path),
            ),
          ),
        );

        var attempts = 0;
        while (find.text('Project report').evaluate().isEmpty &&
            attempts < 750) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
          attempts++;
        }

        expect(find.text('Project report'), findsOneWidget);
        expect(find.text('Bold centered line'), findsOneWidget);
        expect(find.text('Name'), findsOneWidget);
        expect(find.text('Alpha'), findsOneWidget);
        expect(find.byType(Table), findsOneWidget);
        expect(find.byType(Image), findsWidgets);
      });
    });
  });
}