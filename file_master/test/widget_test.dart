import 'package:flutter_test/flutter_test.dart';

import 'package:file_master/models/recent_file.dart';
import 'package:file_master/utils/doc_format.dart';

void main() {
  group('DocFormat.fromPath', () {
    test('detects PDF', () {
      expect(DocFormat.fromPath('/docs/report.pdf'), DocFormat.pdf);
    });

    test('detects Word documents', () {
      expect(DocFormat.fromPath('/docs/a.docx'), DocFormat.word);
      expect(DocFormat.fromPath('/docs/a.doc'), DocFormat.word);
    });

    test('detects Excel and CSV', () {
      expect(DocFormat.fromPath('/data/sheet.xlsx'), DocFormat.excel);
      expect(DocFormat.fromPath('/data/list.csv'), DocFormat.excel);
    });

    test('detects presentations', () {
      expect(DocFormat.fromPath('/deck.pptx'), DocFormat.powerpoint);
    });

    test('detects text', () {
      expect(DocFormat.fromPath('/notes.txt'), DocFormat.text);
    });

    test('detects images', () {
      expect(DocFormat.fromPath('/photo.PNG'), DocFormat.image);
    });

    test('falls back to other', () {
      expect(DocFormat.fromPath('/thing.xyz'), DocFormat.other);
    });
  });

  group('RecentFile', () {
    test('round-trips through map', () {
      final file = RecentFile(
        name: 'report.pdf',
        path: '/tmp/report.pdf',
        format: DocFormat.pdf,
        sizeBytes: 12345,
        lastOpened: DateTime.fromMillisecondsSinceEpoch(1000000),
      );
      final restored = RecentFile.fromMap(file.toMap());
      expect(restored.name, file.name);
      expect(restored.path, file.path);
      expect(restored.format, DocFormat.pdf);
      expect(restored.sizeBytes, file.sizeBytes);
      expect(restored.lastOpened, file.lastOpened);
    });
  });
}
