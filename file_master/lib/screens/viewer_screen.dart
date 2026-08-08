import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/recent_file.dart';
import '../utils/doc_format.dart';

class ViewerScreen extends StatelessWidget {
  const ViewerScreen({super.key, required this.file});

  final RecentFile file;

  Future<void> _share(BuildContext context) async {
    final pathFile = File(file.path);
    if (!pathFile.existsSync()) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('File not found')));
      return;
    }
    await SharePlus.instance.share(
      ShareParams(files: [XFile(pathFile.path)], subject: file.name),
    );
  }

  Future<void> _print(BuildContext context) async {
    final pathFile = File(file.path);
    if (!pathFile.existsSync()) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('File not found')));
      return;
    }
    try {
      await Printing.layoutPdf(
        name: file.name,
        onLayout: (format) async => pathFile.readAsBytes(),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not print: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pathFile = File(file.path);
    return Scaffold(
      appBar: AppBar(
        title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (file.format == DocFormat.pdf)
            IconButton(
              tooltip: 'Print',
              icon: const Icon(Icons.print_outlined),
              onPressed: () => _print(context),
            ),
          IconButton(
            tooltip: 'Share',
            icon: const Icon(Icons.share_outlined),
            onPressed: () => _share(context),
          ),
        ],
      ),
      body: !pathFile.existsSync()
          ? _UnsupportedViewer(
              file: file,
              icon: Icons.insert_drive_file_outlined,
              message: 'This file could not be found on your device.',
            )
          : switch (file.format) {
              DocFormat.pdf => _PdfViewer(path: file.path),
              DocFormat.image => _ImageViewer(path: file.path),
              DocFormat.text => _TextViewer(path: file.path),
              DocFormat.word ||
              DocFormat.excel ||
              DocFormat.powerpoint => _UnsupportedViewer(
                file: file,
                icon: file.format.icon,
                message:
                    'Offline preview for ${file.format.label} files is not '
                    'available. Use Share to open it in another app, or '
                    'Convert (from the home screen) to turn it into a PDF.',
              ),
              _ => _UnsupportedViewer(
                file: file,
                icon: file.format.icon,
                message:
                    'This ${file.format.label} type is not supported '
                    'yet. Use Share to open it in another app.',
              ),
            },
    );
  }
}

class _PdfViewer extends StatefulWidget {
  const _PdfViewer({required this.path});

  final String path;

  @override
  State<_PdfViewer> createState() => _PdfViewerState();
}

class _PdfViewerState extends State<_PdfViewer> {
  late final Future<PdfDocument> _document;

  @override
  void initState() {
    super.initState();
    _document = PdfDocument.openFile(widget.path);
  }

  @override
  void dispose() {
    unawaited(_document.then((doc) => doc.close()));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PdfDocument>(
      future: _document,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _CenterMessage(
            icon: Icons.picture_as_pdf,
            title: 'Could not open this PDF',
            subtitle: '${snapshot.error}',
          );
        }
        return PdfViewPinch(
          controller: PdfControllerPinch(
            document: Future.value(snapshot.data!),
          ),
        );
      },
    );
  }
}

class _ImageViewer extends StatelessWidget {
  const _ImageViewer({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InteractiveViewer(
      maxScale: 8,
      child: Center(
        child: Image.file(
          File(path),
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.broken_image_outlined,
                size: 56,
                color: scheme.outline,
              ),
              const SizedBox(height: 12),
              const Text('This image could not be displayed'),
            ],
          ),
        ),
      ),
    );
  }
}

class _TextViewer extends StatefulWidget {
  const _TextViewer({required this.path});

  final String path;

  @override
  State<_TextViewer> createState() => _TextViewerState();
}

class _TextViewerState extends State<_TextViewer> {
  static const int _maxChars = 2 * 1024 * 1024;

  late final Future<_TextResult> _load = _read();

  Future<_TextResult> _read() async {
    final file = File(widget.path);
    final length = await file.length();
    if (length > _maxChars) {
      final partial = await file
          .openRead(0, _maxChars)
          .transform(const Utf8Decoder(allowMalformed: true))
          .join();
      return _TextResult(content: partial, truncated: true, totalBytes: length);
    }
    final content = await file.readAsString();
    return _TextResult(content: content, truncated: false, totalBytes: length);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<_TextResult>(
      future: _load,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _CenterMessage(
            icon: Icons.error_outline,
            title: 'Could not read this file',
            subtitle: '${snapshot.error}',
          );
        }
        final result = snapshot.data!;
        return SelectionArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (result.truncated)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Showing the first $_maxChars characters '
                      '(${result.totalBytes ~/ 1024} KB total).',
                      style: TextStyle(color: scheme.onTertiaryContainer),
                    ),
                  ),
                Text(
                  result.content,
                  style: const TextStyle(fontSize: 15, height: 1.4),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TextResult {
  const _TextResult({
    required this.content,
    required this.truncated,
    required this.totalBytes,
  });

  final String content;
  final bool truncated;
  final int totalBytes;
}

class _UnsupportedViewer extends StatelessWidget {
  const _UnsupportedViewer({
    required this.file,
    required this.icon,
    required this.message,
  });

  final RecentFile file;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return _CenterMessage(icon: icon, title: file.name, subtitle: message);
  }
}

class _CenterMessage extends StatelessWidget {
  const _CenterMessage({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: scheme.outline),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
