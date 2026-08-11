import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

const _margin = pw.EdgeInsets.all(48);

const PdfPageFormat pageFormat = PdfPageFormat.a4;

/// Builds a multi-page PDF from a title and body text.
///
/// Text flows across pages automatically; the built-in Helvetica font is
/// embedded so no font asset is required. The body can be styled with
/// [fontSize], [bold], [italic], [underline] and [align].
Future<Uint8List> buildTextPdf({
  required String title,
  required String content,
  double fontSize = 12,
  bool bold = false,
  bool italic = false,
  bool underline = false,
  pw.TextAlign align = pw.TextAlign.left,
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
          textAlign: align,
          style: pw.TextStyle(
            font: bold
                ? (italic
                    ? pw.Font.helveticaBoldOblique()
                    : pw.Font.helveticaBold())
                : (italic ? pw.Font.helveticaOblique() : pw.Font.helvetica()),
            fontSize: fontSize,
            lineSpacing: 4,
            decoration: underline ? pw.TextDecoration.underline : null,
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
