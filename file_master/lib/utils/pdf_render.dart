import 'dart:typed_data';

import 'package:pdfx/pdfx.dart';

/// Renders every page of the PDF at [path] into PNG images.
///
/// [scale] controls the output resolution (2x = crisp on modern phones).
/// Returns the image bytes in page order, or an empty list if nothing
/// could be rendered.
Future<List<Uint8List>> renderPdfToImages(
  String path, {
  double scale = 2,
}) async {
  final document = await PdfDocument.openFile(path);
  final images = <Uint8List>[];
  try {
    for (var i = 1; i <= document.pagesCount; i++) {
      final page = await document.getPage(i);
      try {
        final image = await page.render(
          width: page.width * scale,
          height: page.height * scale,
          format: PdfPageImageFormat.png,
        );
        if (image != null) images.add(image.bytes);
      } catch (_) {
        // Skip pages that cannot be rendered.
      } finally {
        try {
          await page.close();
        } catch (_) {
          // Already closed by the platform.
        }
      }
    }
  } finally {
    await document.close();
  }
  return images;
}
