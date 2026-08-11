import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/recent_file.dart';
import '../providers/recents_provider.dart';
import '../utils/doc_format.dart';
import '../utils/office_utils.dart';
import '../utils/output_utils.dart';
import '../utils/pdf_render.dart';
import 'viewer_screen.dart';

/// Convert files to and from PDF (images/text/Office -> PDF and PDF -> PNG).
class ConvertScreen extends ConsumerStatefulWidget {
  const ConvertScreen({super.key});

  @override
  ConsumerState<ConvertScreen> createState() => _ConvertScreenState();
}

class _ConvertScreenState extends ConsumerState<ConvertScreen> {
  bool _busy = false;

  static const _toPdfExtensions = [
    'pdf',
    'jpg',
    'jpeg',
    'png',
    'gif',
    'bmp',
    'webp',
    'heic',
    'tiff',
    'txt',
    'md',
    'log',
    'json',
    'csv',
    'docx',
    'xlsx',
    'pptx',
  ];

  Future<void> _toPdf() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: _toPdfExtensions,
    );
    if (result == null || result.files.isEmpty) return;
    final paths = result.files.map((f) => f.path).whereType<String>().toList();
    if (paths.isEmpty) return;

    setState(() => _busy = true);
    try {
      final doc = pw.Document();
      final pages = await _buildPages(paths);
      for (final page in pages) {
        doc.addPage(page);
      }
      final saved = await saveOutput(
        await doc.save(),
        timestampedName('Converted', 'pdf'),
      );
      await _recordAndOpen(saved.path, 'Conversion saved');
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Conversion failed: $error')));
    }
  }

  /// Builds a page for every selected file, in selection order.
  /// Text stays vector; PDFs are rendered to page images.
  Future<List<pw.Page>> _buildPages(List<String> paths) async {
    final pages = <pw.Page>[];
    for (final path in paths) {
      final format = DocFormat.fromPath(path);
      switch (format) {
        case DocFormat.pdf:
          final images = await renderPdfToImages(path);
          pages.addAll(
            images.map(
              (image) => pw.Page(
                pageFormat: PdfPageFormat.a4,
                build: (context) => pw.Center(
                  child: pw.Image(
                    pw.MemoryImage(image),
                    fit: pw.BoxFit.contain,
                  ),
                ),
              ),
            ),
          );
        case DocFormat.image:
          final bytes = await File(path).readAsBytes();
          pages.add(
            pw.Page(
              pageFormat: PdfPageFormat.a4,
              build: (context) => pw.Center(
                child: pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.contain),
              ),
            ),
          );
        case DocFormat.text ||
            DocFormat.word ||
            DocFormat.excel ||
            DocFormat.powerpoint:
          final content = await _loadText(path, format);
          pages.add(_buildTextPage(p.basename(path), content));
        default:
          break;
      }
    }
    return pages;
  }

  Future<String> _loadText(String path, DocFormat format) async {
    if (format == DocFormat.text) {
      return File(path).readAsString();
    }
    return extractOfficeText(path);
  }

  pw.Page _buildTextPage(String title, String content) {
    return pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(48),
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
    );
  }

  Future<void> _pdfToImages() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result == null) return;
    final paths = result.files.map((f) => f.path).whereType<String>().toList();
    if (paths.isEmpty) return;

    setState(() => _busy = true);
    var exported = 0;
    try {
      for (final path in paths) {
        final pages = await renderPdfToImages(path);
        for (var i = 0; i < pages.length; i++) {
          final page = pages[i];
          final base = p.basenameWithoutExtension(path);
          final number = (i + 1).toString().padLeft(3, '0');
          await saveOutput(page, '${base}_$number.png');
          exported++;
        }
      }
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported $exported page image(s)')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Export failed: $error')));
    }
  }

  Future<void> _recordAndOpen(String path, String message) async {
    final file = File(path);
    final recent = RecentFile(
      name: p.basename(path),
      path: path,
      format: DocFormat.fromPath(path),
      sizeBytes: await file.length(),
      lastOpened: DateTime.now(),
    );
    await ref.read(recentsControllerProvider.notifier).recordOpen(recent);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$message — opening…')),
    );
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => ViewerScreen(file: recent)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Convert')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ToolCard(
            icon: Icons.file_copy_outlined,
            title: 'Files → PDF',
            subtitle:
                'Images, text and Office files become one PDF '
                'document.',
            onTap: _busy ? null : _toPdf,
          ),
          const SizedBox(height: 12),
          _ToolCard(
            icon: Icons.output_outlined,
            title: 'PDF → Images',
            subtitle: 'Save every page of a PDF as a PNG image.',
            onTap: _busy ? null : _pdfToImages,
          ),
          if (_busy) ...[
            const SizedBox(height: 24),
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Working…',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: Icon(icon, color: scheme.primary),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
