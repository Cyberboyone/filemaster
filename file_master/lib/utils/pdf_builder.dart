import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

const _margin = pw.EdgeInsets.all(48);

const PdfPageFormat pageFormat = PdfPageFormat.a4;

/// Builds a multi-page PDF from a title and body text.
///
/// Text flows across pages automatically; the built-in Helvetica font is
/// embedded so no font asset is required.
Future<Uint8List> buildTextPdf({
  required String title,
  required String content,
}) async {
  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: pageFormat,
      margin: _margin,
      build: (context) => [
        pw.Text(
          title,
          style: pw.TextStyle(font: pw.Font.helveticaBold(), fontSize: 18),
        ),
        pw.SizedBox(height: 16),
        pw.Paragraph(
          text: content,
          style: pw.TextStyle(
            font: pw.Font.helvetica(),
            fontSize: 12,
            lineSpacing: 4,
          ),
        ),
      ],
    ),
  );
  return doc.save();
}

/// Builds a PDF where each entry of [pages] becomes one page.
///
/// Every entry must be a PNG or JPEG image; it is fitted to an A4 page.
Future<Uint8List> buildPdfFromPages(List<Uint8List> pages) async {
  final doc = pw.Document();
  for (final pageBytes in pages) {
    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (context) => pw.Center(
          child: pw.Image(pw.MemoryImage(pageBytes), fit: pw.BoxFit.contain),
        ),
      ),
    );
  }
  return doc.save();
}
