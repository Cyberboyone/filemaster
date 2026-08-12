import 'package:pdfx/pdfx.dart';

/// Page counts for PDF files, cached by path.
///
/// Opens are serialized through a queue: Android's PDF renderer is expensive
/// and fails when many documents are opened at the same time (which happens
/// when a long list of PDF tiles all request a count at once).
final Map<String, int?> _countCache = {};
Future<void> _queue = Future.value();

/// Returns the number of pages in the PDF at [path], or null when the file
/// cannot be read. Results are cached, so repeat calls are instant.
Future<int?> pdfPageCount(String path) {
  if (_countCache.containsKey(path)) {
    return Future.value(_countCache[path]);
  }
  final run = _queue.then((_) async {
    try {
      final document = await PdfDocument.openFile(path);
      final count = document.pagesCount;
      await document.close();
      _countCache[path] = count;
      return count;
    } catch (_) {
      _countCache[path] = null;
      return null;
    }
  });
  _queue = run.then((_) {}, onError: (_) {});
  return run;
}