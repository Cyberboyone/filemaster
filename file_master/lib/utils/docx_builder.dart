import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Builds a minimal but valid .docx (WordprocessingML) file from a title
/// and body text, mirroring the styling options of the PDF builder.
///
/// The document has no external dependencies (no styles.xml, no theme), so
/// any modern word processor (Word, WPS, LibreOffice) opens it.
Future<Uint8List> buildDocx({
  required String title,
  required String content,
  double fontSize = 14,
  bool bold = false,
  bool italic = false,
  bool underline = false,
  String align = 'left',
}) async {
  final documentXml = _documentXml(
    title: title,
    content: content,
    fontSize: fontSize,
    bold: bold,
    italic: italic,
    underline: underline,
    align: align,
  );

  final archive = Archive()
    ..addFile(ArchiveFile(
      '[Content_Types].xml',
      _contentTypesXml.length,
      utf8.encode(_contentTypesXml),
    ))
    ..addFile(ArchiveFile(
      '_rels/.rels',
      _rootRelsXml.length,
      utf8.encode(_rootRelsXml),
    ))
    ..addFile(ArchiveFile(
      'word/document.xml',
      documentXml.length,
      utf8.encode(documentXml),
    ));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

const _contentTypesXml =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Override PartName="/word/document.xml" '
    'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
    '</Types>';

const _rootRelsXml =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" '
    'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
    'Target="word/document.xml"/>'
    '</Relationships>';

String _documentXml({
  required String title,
  required String content,
  required double fontSize,
  required bool bold,
  required bool italic,
  required bool underline,
  required String align,
}) {
  final buffer = StringBuffer();
  buffer.write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
  buffer.write(
    '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
    '<w:body>',
  );
  buffer.write(
    '<w:p><w:pPr><w:jc w:val="center"/></w:pPr>'
    '<w:r><w:rPr><w:b/><w:sz w:val="36"/></w:rPr><w:t>${_escapeXml(title)}</w:t></w:r></w:p>',
  );
  final runProps = StringBuffer();
  if (bold) runProps.write('<w:b/>');
  if (italic) runProps.write('<w:i/>');
  if (underline) runProps.write('<w:u w:val="single"/>');
  runProps.write('<w:sz w:val="${(fontSize * 2).round()}"/>');
  final justify = switch (align) {
    'center' => '<w:jc w:val="center"/>',
    'right' => '<w:jc w:val="right"/>',
    'justify' || 'dist' => '<w:jc w:val="both"/>',
    _ => '',
  };
  for (final line in content.split('\n')) {
    buffer.write(
      '<w:p><w:pPr>$justify</w:pPr>'
      '<w:r><w:rPr>$runProps</w:rPr>'
      '<w:t xml:space="preserve">${_escapeXml(line)}</w:t></w:r></w:p>',
    );
  }
  buffer.write('</w:body></w:document>');
  return buffer.toString();
}

String _escapeXml(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}