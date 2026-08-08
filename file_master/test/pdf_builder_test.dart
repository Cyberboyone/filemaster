import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:file_master/utils/pdf_builder.dart';

void main() {
  group('buildTextPdf', () {
    test('produces a valid PDF with title and body', () async {
      final bytes = await buildTextPdf(
        title: 'Meeting notes',
        content: 'Discussion about phase 3.\nFollow-up next week.',
      );
      final header = utf8.decode(bytes.take(8).toList());
      expect(header, startsWith('%PDF'));
      expect(bytes.length, greaterThan(500));
      // Object dictionaries are stored uncompressed in pdf 3.x.
      final body = latin1.decode(bytes);
      expect(body, contains('/Type/Page'));
      expect(body, contains('/Helvetica'));
    });

    test('multi-page content still produces a single valid file', () async {
      final bytes = await buildTextPdf(
        title: 'Long document',
        content: List.filled(200, 'Line of filler text.').join('\n'),
      );
      expect(utf8.decode(bytes.take(8).toList()), startsWith('%PDF'));
    });
  });

  group('buildPdfFromPages', () {
    test('builds a one-page PDF from a tiny PNG', () async {
      final png = img.encodePng(img.Image(width: 2, height: 2));
      final bytes = await buildPdfFromPages([png]);
      final header = utf8.decode(bytes.take(8).toList());
      expect(header, startsWith('%PDF'));
      final body = latin1.decode(bytes);
      expect(body, contains('/Subtype/Image'));
    });
  });
}
