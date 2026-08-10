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
      ).showSnackBar(SnackBar(content: Text('Could not save PDF: $error')));
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
              DocFormat.excel => _isConvertibleOffice(pathFile.path)
                  ? _ExcelViewer(file: file)
                  : _UnsupportedViewer(
                      file: file,
                      icon: file.format.icon,
                      message:
                          'Offline preview for ${file.format.label} files is '
                          'not available. Use Share to open it in another '
                          'app.',
                    ),
              DocFormat.powerpoint => _isConvertibleOffice(pathFile.path)
                  ? _PptxViewer(file: file)
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

// ---------------------------------------------------------------------------
// DOCX Viewer – page-like view matching the Word/PDF screenshot style
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Excel Viewer – sheet tabs with scrollable table grid
// ---------------------------------------------------------------------------

class _ExcelViewer extends StatefulWidget {
  const _ExcelViewer({required this.file});

  final RecentFile file;

  @override
  State<_ExcelViewer> createState() => _ExcelViewerState();
}

class _ExcelViewerState extends State<_ExcelViewer> {
  late final Future<List<ExcelSheet>> _load = _loadSheets();
  int _activeSheet = 0;

  Future<List<ExcelSheet>> _loadSheets() async {
    final bytes = await File(widget.file.path).readAsBytes();
    return extractExcelSheets(bytes);
  }

  Future<void> _convertToPdf() async {
    final baseName = sanitizeFileName(
      p.basenameWithoutExtension(widget.file.path),
    );
    final fileName = '${baseName}_converted.pdf';
    try {
      final sheets = await _load;
      final buffer = StringBuffer();
      for (final sheet in sheets) {
        buffer.writeln('--- ${sheet.name} ---');
        for (final row in sheet.rows) {
          buffer.writeln(row.join('\t'));
        }
        buffer.writeln();
      }
      final content = buffer.toString();
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
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<List<ExcelSheet>>(
      future: _load,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _CenterMessage(
            icon: Icons.table_chart_outlined,
            title: 'Could not open this file',
            subtitle:
                '${widget.file.name} is not a readable Excel document. '
                'Use Share to open it in another app.',
          );
        }
        final sheets = snapshot.data!;
        if (sheets.isEmpty) {
          return _CenterMessage(
            icon: Icons.table_chart_outlined,
            title: 'Empty spreadsheet',
            subtitle: 'This file has no readable data.',
          );
        }
        final index = _activeSheet.clamp(0, sheets.length - 1);
        final sheet = sheets[index];
        return Column(
          children: [
            // Sheet tabs
            if (sheets.length > 1)
              Container(
                height: 40,
                color: scheme.surfaceContainerLow,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: sheets.length,
                  itemBuilder: (context, i) {
                    final selected = i == index;
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 6,
                      ),
                      child: ChoiceChip(
                        label: Text(
                          sheets[i].name,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: selected
                                ? scheme.onPrimaryContainer
                                : scheme.onSurface,
                          ),
                        ),
                        selected: selected,
                        selectedColor: scheme.primaryContainer,
                        onSelected: (_) => setState(() => _activeSheet = i),
                        visualDensity: VisualDensity.compact,
                      ),
                    );
                  },
                ),
              ),
            // Table
            Expanded(
              child: sheet.rows.isEmpty
                  ? const Center(child: Text('Empty sheet'))
                  : _buildTable(sheet, scheme),
            ),
            _ToolsBar(
              tools: [
                _ToolItem(
                  icon: Icons.picture_as_pdf_outlined,
                  label: 'Convert',
                  onTap: _convertToPdf,
                ),
                _ToolItem(
                  icon: Icons.share_outlined,
                  label: 'Share',
                  onTap: () async {
                    final pathFile = File(widget.file.path);
                    if (pathFile.existsSync()) {
                      await SharePlus.instance.share(
                        ShareParams(
                          files: [XFile(pathFile.path)],
                          subject: widget.file.name,
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildTable(ExcelSheet sheet, ColorScheme scheme) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Table(
          border: TableBorder.all(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
            width: 0.5,
          ),
          defaultColumnWidth: const IntrinsicColumnWidth(),
          children: [
            for (var r = 0; r < sheet.rows.length; r++)
              TableRow(
                decoration: r == 0
                    ? BoxDecoration(color: scheme.primaryContainer.withValues(alpha: 0.3))
                    : null,
                children: [
                  for (var c = 0; c < sheet.rows[r].length; c++)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Text(
                        sheet.rows[r][c],
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight:
                              r == 0 ? FontWeight.w600 : FontWeight.w400,
                          color: r == 0
                              ? scheme.onPrimaryContainer
                              : scheme.onSurface,
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PPTX Viewer – slide-by-slide view
// ---------------------------------------------------------------------------

class _PptxViewer extends StatefulWidget {
  const _PptxViewer({required this.file});

  final RecentFile file;

  @override
  State<_PptxViewer> createState() => _PptxViewerState();
}

class _PptxViewerState extends State<_PptxViewer> {
  late final Future<_PptxResult> _load = _loadSlides();
  final PageController _controller = PageController();
  int _current = 0;

  Future<_PptxResult> _loadSlides() async {
    try {
      final text = await extractOfficeText(widget.file.path);
      final bytes = await File(widget.file.path).readAsBytes();
      final slides = extractPptxSlides(bytes);
      if (text.trim().isEmpty && slides.every((s) => s.content.trim().isEmpty)) {
        return _PptxResult(slides: const []);
      }
      return _PptxResult(slides: slides);
    } catch (e) {
      return _PptxResult(error: e);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _convertToPdf() async {
    final baseName = sanitizeFileName(
      p.basenameWithoutExtension(widget.file.path),
    );
    final fileName = '${baseName}_converted.pdf';
    try {
      final result = await _load;
      final slides = result.slides;
      final buffer = StringBuffer();
      for (final slide in slides) {
        buffer.writeln('--- Slide ${slide.index} ---');
        buffer.writeln(slide.content);
        buffer.writeln();
      }
      final content = buffer.toString();
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

  Widget _pptxErrorView({required String title, required String subtitle}) {
    return Column(
      children: [
        Expanded(
          child: _CenterMessage(
            icon: Icons.slideshow_outlined,
            title: title,
            subtitle: subtitle,
          ),
        ),
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<_PptxResult>(
      future: _load,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final result = snapshot.data ?? _PptxResult(error: 'Unknown error');
        if (result.error != null) {
          return _pptxErrorView(
            title: 'Could not open this file',
            subtitle:
                'This is not a readable PowerPoint document. '
                'Use Share to open it in another app.',
          );
        }
        final slides = result.slides;
        final hasContent =
            slides.any((s) => s.content.trim().isNotEmpty);
        if (slides.isEmpty || !hasContent) {
          return _pptxErrorView(
            title: 'Empty presentation',
            subtitle: 'No readable text found in this file. '
                'Use Share to open it in another app.',
          );
        }
        final total = slides.length;
        final current = _current.clamp(0, total - 1);
        return Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: total,
                onPageChanged: (i) => setState(() => _current = i),
                itemBuilder: (context, index) {
                  final slide = slides[index];
                  return Container(
                    margin: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: scheme.outlineVariant.withValues(alpha: 0.4),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(12),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.slideshow,
                                size: 18,
                                color: scheme.onPrimaryContainer,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Slide ${slide.index}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: scheme.onPrimaryContainer,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: slide.content.trim().isEmpty
                                ? Center(
                                    child: Text(
                                      '(Empty slide)',
                                      style: TextStyle(
                                        color: scheme.onSurfaceVariant,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  )
                                : SelectionArea(
                                    child: SingleChildScrollView(
                                      child: Text(
                                        slide.content,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          height: 1.5,
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'Slide ${current + 1} of $total',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            _ToolsBar(
              tools: [
                _ToolItem(
                  icon: Icons.picture_as_pdf_outlined,
                  label: 'Convert',
                  onTap: _convertToPdf,
                ),
                _ToolItem(
                  icon: Icons.share_outlined,
                  label: 'Share',
                  onTap: () async {
                    final pathFile = File(widget.file.path);
                    if (pathFile.existsSync()) {
                      await SharePlus.instance.share(
                        ShareParams(
                          files: [XFile(pathFile.path)],
                          subject: widget.file.name,
                        ),
                      );
                    }
                  },
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

class _PptxResult {
  const _PptxResult({this.slides = const [], this.error});

  final List<PptxSlide> slides;
  final Object? error;
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
