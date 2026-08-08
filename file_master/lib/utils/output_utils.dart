import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Directory where File Master keeps generated files (PDFs, exports).
///
/// Tries the public `FileMaster` folder on shared storage first (visible in
/// any file manager when "All files access" is granted), then falls back to
/// the app documents directory.
Future<Directory> getOutputDir() async {
  try {
    final external = Directory('/storage/emulated/0');
    if (await external.exists()) {
      final output = Directory(p.join(external.path, 'FileMaster'));
      await output.create(recursive: true);
      return output;
    }
  } catch (_) {
    // Fall through to the app documents directory.
  }
  return getApplicationDocumentsDirectory();
}

/// Default starting directory for the device file browser.
Future<Directory> getDefaultRoot() async {
  try {
    final external = Directory('/storage/emulated/0');
    if (await external.exists()) return external;
  } catch (_) {
    // Fall through.
  }
  return getOutputDir();
}

/// Writes [bytes] to the output folder as [fileName] and returns the file.
Future<File> saveOutput(List<int> bytes, String fileName) async {
  final dir = await getOutputDir();
  final file = File(p.join(dir.path, fileName));
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

/// Builds a unique timestamped file name like `Scan_2026-08-08_1430.pdf`.
String timestampedName(String prefix, String extension) {
  final now = DateTime.now();
  final stamp =
      '${now.year.toString().padLeft(4, '0')}'
      '-${now.month.toString().padLeft(2, '0')}'
      '-${now.day.toString().padLeft(2, '0')}'
      '_${now.hour.toString().padLeft(2, '0')}'
      '${now.minute.toString().padLeft(2, '0')}';
  return '${prefix}_$stamp.$extension';
}

/// Sanitizes [title] into a safe file base name (no path separators).
String sanitizeFileName(String title) {
  final cleaned = title.trim().replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
  return cleaned.isEmpty ? 'Untitled' : cleaned;
}
