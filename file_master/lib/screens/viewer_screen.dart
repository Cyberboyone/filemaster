import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:pdfx/pdfx.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/recent_file.dart';
import '../utils/doc_format.dart';
import '../utils/office_utils.dart';
import '../utils/output_utils.dart';
import '../utils/pdf_builder.dart';
import '../utils/text_pager.dart';
import '../widgets/docx_document_view.dart';

/// True for Office formats we can read offline (the modern XML based ones).
bool _isConvertibleOffice(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.docx') ||
      lower.endsWith('.xlsx') ||
      lower.endsWith('.pptx');
}

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
              DocFormat.word => pathFile.path.toLowerCase().endsWith('.docx')
                  ? _DocxViewer(file: file)
                  : _UnsupportedViewer(
                      file: file,
                      icon: file.format.icon,
                      message:
                          'Offline preview for older Word files (.doc) is '
                          'not available. Use Share to open it in another '
                          'app, or Convert to turn it into a PDF.',
                    ),
              DocFormat.excel ||
              DocFormat.powerpoint => _isConvertibleOffice(pathFile.path)
                  ? _OfficeDocViewer(file: file)
                  : _UnsupportedViewer(
                      file: file,
                      icon: file.format.icon,
                      message:
                          'Offline preview for ${file.format.label} files is '
                          'not available. Use Share to open it in another '
                          'app.',
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

  late Future<_TextResult> _load = _read();

  void _reload() {
    setState(() {
      _load = _read();
    });
  }

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
        return Column(
          children: [
            Expanded(
              child: SelectionArea(
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
                            style: TextStyle(
                              color: scheme.onTertiaryContainer,
                            ),
                          ),
                        ),
                      Text(
                        result.content,
                        style: const TextStyle(fontSize: 15, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _ToolsBar(
              tools: [
                _ToolItem(
                  icon: Icons.edit_outlined,
                  label: 'Edit',
                  onTap: () => _edit(result.content),
                ),
                _ToolItem(
                  icon: Icons.picture_as_pdf_outlined,
                  label: 'Convert',
                  onTap: () => _convertToPdf(result.content),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Future<void> _edit(String content) async {
    if (!mounted) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _TextEditorPage(
          filePath: widget.path,
          initialContent: content,
        ),
      ),
    );
    if (saved == true) _reload();
  }

  Future<void> _convertToPdf(String content) async {
    final baseName = sanitizeFileName(
      p.basenameWithoutExtension(widget.path),
    );
    final fileName = '${baseName}_converted.pdf';
    try {
      final bytes = await buildTextPdf(
        title: p.basename(widget.path),
        content: content,
      );
      final file = await saveOutput(bytes, fileName);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved to ${file.path}')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save PDF: $error')));
    }
  }
}

class _TextEditorPage extends StatefulWidget {
  const _TextEditorPage({
    required this.filePath,
    required this.initialContent,
  });

  final String filePath;
  final String initialContent;

  @override
  State<_TextEditorPage> createState() => _TextEditorPageState();
}

class _TextEditorPageState extends State<_TextEditorPage> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialContent,
  );
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await File(widget.filePath).writeAsString(
        _controller.text,
        flush: true,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              tooltip: 'Save',
              icon: const Icon(Icons.check),
              onPressed: _save,
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: TextField(
          controller: _controller,
          maxLines: null,
          expands: true,
          autofocus: true,
          keyboardType: TextInputType.multiline,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Type your text...',
          ),
        ),
      ),
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

class _DocxViewer extends StatefulWidget {
  const _DocxViewer({required this.file});

  final RecentFile file;

  @override
  State<_DocxViewer> createState() => _DocxViewerState();
}

class _DocxViewerState extends State<_DocxViewer> {
  late final Future<String> _content = _extract();

  Future<String> _extract() async {
    final text = await extractOfficeText(widget.file.path);
    return text.trim().isEmpty ? '(No readable text found in this file.)' : text;
  }

  Future<void> _convertToPdf() async {
    final baseName = sanitizeFileName(
      p.basenameWithoutExtension(widget.file.path),
    );
    final fileName = '${baseName}_converted.pdf';
    try {
      final content = await _content;
      final bytes = await buildTextPdf(
        title: p.basename(widget.file.path),
        content: content,
      );
      final file = await saveOutput(bytes, fileName);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved to ${file.path}')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save PDF: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(child: DocxDocumentView(path: widget.file.path)),
        _ToolsBar(
          tools: [
            _ToolItem(
              icon: Icons.picture_as_pdf_outlined,
              label: 'Convert',
              onTap: _convertToPdf,
            ),
          ],
        ),
      ],
    );
  }
}

class _OfficeDocViewer extends StatefulWidget {
  const _OfficeDocViewer({required this.file});

  final RecentFile file;

  @override
  State<_OfficeDocViewer> createState() => _OfficeDocViewerState();
}

class _OfficeDocViewerState extends State<_OfficeDocViewer> {
  late final Future<String> _load = _extract();

  Future<String> _extract() async {
    final text = await extractOfficeText(widget.file.path);
    return text.trim().isEmpty ? '(No readable text found in this file.)' : text;
  }

  Future<void> _convertToPdf(String content) async {
    final baseName = sanitizeFileName(
      p.basenameWithoutExtension(widget.file.path),
    );
    final fileName = '${baseName}_converted.pdf';
    try {
      final bytes = await buildTextPdf(
        title: p.basename(widget.file.path),
        content: content,
      );
      final file = await saveOutput(bytes, fileName);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved to ${file.path}')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save PDF: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _load,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _CenterMessage(
            icon: Icons.description_outlined,
            title: 'Could not open this file',
            subtitle:
                '${widget.file.name} is not a readable Office document. '
                'Use Share to open it in another app.',
          );
        }
        final content = snapshot.data!;
        return Column(
          children: [
            Expanded(child: _PagedTextViewer(content: content)),
            _ToolsBar(
              tools: [
                _ToolItem(
                  icon: Icons.picture_as_pdf_outlined,
                  label: 'Convert',
                  onTap: () => _convertToPdf(content),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Shows long text split into numbered, swipeable pages.
class _PagedTextViewer extends StatefulWidget {
  const _PagedTextViewer({required this.content});

  final String content;

  @override
  State<_PagedTextViewer> createState() => _PagedTextViewerState();
}

class _PagedTextViewerState extends State<_PagedTextViewer> {
  static const _style = TextStyle(fontSize: 15, height: 1.4);

  final PageController _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final pages = paginateText(
          text: widget.content,
          style: _style,
          width: constraints.maxWidth - 40,
          height: constraints.maxHeight - 40,
        );
        final total = pages.length;
        final current = _page.clamp(0, total - 1);
        return Column(
          children: [
            Expanded(
              child: SelectionArea(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: total,
                  onPageChanged: (index) => setState(() => _page = index),
                  itemBuilder: (context, index) => SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Text(pages[index], style: _style),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Page ${current + 1} of $total',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Bottom action bar shown inside a viewer with tools for the current file
/// type (Convert, Edit, ...).
class _ToolsBar extends StatelessWidget {
  const _ToolsBar({required this.tools});

  final List<_ToolItem> tools;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final tool in tools)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _ToolButton(item: tool),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.item});

  final _ToolItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: item.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(item.icon, size: 22, color: scheme.onSecondaryContainer),
              const SizedBox(height: 2),
              Text(
                item.label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSecondaryContainer,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolItem {
  const _ToolItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
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
