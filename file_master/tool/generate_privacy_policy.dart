// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';

void main() {
  final docx = _buildPrivacyPolicyDocx();
  final out = File('privacy_policy.docx');
  out.writeAsBytesSync(docx);
  print('Created: ${out.path} (${out.lengthSync()} bytes)');
}

Uint8List _buildPrivacyPolicyDocx() {
  final archive = Archive();

  // [Content_Types].xml
  archive.addFile(ArchiveFile(
    '[Content_Types].xml',
    _contentTypesXml().length,
    _contentTypesXml().codeUnits,
  ));

  // _rels/.rels
  archive.addFile(ArchiveFile(
    '_rels/.rels',
    _relsXml().length,
    _relsXml().codeUnits,
  ));

  // word/document.xml
  archive.addFile(ArchiveFile(
    'word/document.xml',
    _documentXml().length,
    _documentXml().codeUnits,
  ));

  // word/_rels/document.xml.rels
  archive.addFile(ArchiveFile(
    'word/_rels/document.xml.rels',
    _documentRelsXml().length,
    _documentRelsXml().codeUnits,
  ));

  // word/styles.xml
  archive.addFile(ArchiveFile(
    'word/styles.xml',
    _stylesXml().length,
    _stylesXml().codeUnits,
  ));

  return Uint8List.fromList(ZipEncoder().encode(archive));
}

String _contentTypesXml() => '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
</Types>''';

String _relsXml() => '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''';

String _documentRelsXml() => '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>''';

String _stylesXml() => '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:style w:type="paragraph" w:styleId="Title">
    <w:name w:val="Title"/>
    <w:pPr><w:spacing w:after="200"/></w:pPr>
    <w:rPr><w:b/><w:sz w:val="36"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Heading1">
    <w:name w:val="heading 1"/>
    <w:pPr><w:spacing w:before="240" w:after="120"/></w:pPr>
    <w:rPr><w:b/><w:sz w:val="28"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Normal">
    <w:name w:val="Normal"/>
    <w:pPr><w:spacing w:after="120" w:line="276" w:lineRule="auto"/></w:pPr>
    <w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/><w:sz w:val="22"/></w:rPr>
  </w:style>
</w:styles>''';

String _documentXml() {
  final buf = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write('<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">')
    ..write('<w:body>');

  void title(String text) {
    buf.write('<w:p><w:pPr><w:pStyle w:val="Title"/></w:pPr>');
    buf.write('<w:r><w:t>${_esc(text)}</w:t></w:r></w:p>');
  }

  void heading(String text) {
    buf.write('<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr>');
    buf.write('<w:r><w:t>${_esc(text)}</w:t></w:r></w:p>');
  }

  void para(String text) {
    buf.write('<w:p><w:r><w:t xml:space="preserve">${_esc(text)}</w:t></w:r></w:p>');
  }

  void blank() {
    buf.write('<w:p/>');
  }

  // --- CONTENT ---
  title('Privacy Policy');
  blank();
  para('Effective Date: August 14, 2026');
  para('Last Updated: August 14, 2026');
  blank();

  para('File Master ("we", "our", or "us") operates the File Master mobile application (the "App"). This Privacy Policy informs you of our policies regarding the collection, use, and disclosure of personal information when you use our App.');
  blank();

  heading('1. Information We Collect');
  blank();
  para('File Master is a file management application that operates entirely on your local device. We do not collect, store, or transmit any personal files, documents, or media from your device to our servers.');
  blank();
  para('The only data collected is through third-party advertising services (Google AdMob), which may collect:');
  buf.write('<w:p><w:r><w:t xml:space="preserve">    \u2022  Device identifiers (Advertising ID)</w:t></w:r></w:p>');
  buf.write('<w:p><w:r><w:t xml:space="preserve">    \u2022  Device type, operating system version, and language</w:t></w:r></w:p>');
  buf.write('<w:p><w:r><w:t xml:space="preserve">    \u2022  IP address (approximate location)</w:t></w:r></w:p>');
  buf.write('<w:p><w:r><w:t xml:space="preserve">    \u2022  Ad interaction data (impressions, clicks)</w:t></w:r></w:p>');
  blank();

  heading('2. How We Use Information');
  blank();
  para('We use the limited data collected solely to:');
  buf.write('<w:p><w:r><w:t xml:space="preserve">    \u2022  Serve relevant advertisements</w:t></w:r></w:p>');
  buf.write('<w:p><w:r><w:t xml:space="preserve">    \u2022  Improve app performance and user experience</w:t></w:r></w:p>');
  buf.write('<w:p><w:r><w:t xml:space="preserve">    \u2022  Detect and prevent fraud or abuse</w:t></w:r></w:p>');
  buf.write('<w:p><w:r><w:t xml:space="preserve">    \u2022  Comply with legal obligations</w:t></w:r></w:p>');
  blank();

  heading('3. Third-Party Services');
  blank();
  para('Our App uses the following third-party services, each of which has its own privacy policy:');
  blank();
  para('Google AdMob: https://policies.google.com/privacy');
  blank();
  para('These services may collect information as described in their respective privacy policies. We encourage you to review their policies.');
  blank();

  heading('4. File Access');
  blank();
  para('File Master requires access to your device storage to perform its core file management functions, including browsing, opening, creating, merging, and converting files. All file operations are performed locally on your device. No files are uploaded, transmitted, or stored on external servers.');
  blank();

  heading('5. Data Storage and Security');
  blank();
  para('We do not store any personal data on our servers. The App stores only minimal preferences (such as dark mode settings) locally on your device using platform-standard storage mechanisms. Your files remain on your device at all times.');
  blank();

  heading('6. Children\'s Privacy');
  blank();
  para('Our App is not directed at children under the age of 13. We do not knowingly collect personal information from children under 13. If you are a parent or guardian and believe your child has provided us with personal information, please contact us so we can take steps to delete such information.');
  blank();

  heading('7. Changes to This Privacy Policy');
  blank();
  para('We may update our Privacy Policy from time to time. We will notify you of any changes by posting the new Privacy Policy on this page and updating the "Effective Date" at the top. You are advised to review this Privacy Policy periodically for any changes.');
  blank();

  heading('8. Contact Us');
  blank();
  para('If you have any questions about this Privacy Policy, please contact us:');
  blank();
  para('Email: muhammadmusab372@gmail.com');
  blank();

  // end document
  buf.write('</w:body></w:document>');
  return buf.toString();
}

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
