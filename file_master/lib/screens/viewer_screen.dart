import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
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
import '../utils/pptx_renderer.dart';
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
              DocFormat.word =>
                pathFile.path.toLowerCase().endsWith('.docx')
                    ? _DocxViewer(file: file)
                    : _UnsupportedViewer(
                        file: file,
                        icon: file.format.icon,
                        message:
                            'Offline preview for older Word files (.doc) is '
                            'not available. Use Share to open it in another '
                            'app, or Convert to turn it into a PDF.',
                      ),
              DocFormat.excel =>
                _isConvertibleOffice(pathFile.path)
                    ? _ExcelViewer(file: file)
                    : _UnsupportedViewer(
                        file: file,
                        icon: file.format.icon,
                        message:
                            'Offline preview for ${file.format.label} files is '
                            'not available. Use Share to open it in another '
                            'app.',
                      ),
              DocFormat.powerpoint =>
                _isConvertibleOffice(pathFile.path)
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

/// PDF viewer that renders pages in the background and caches them, so
/// swiping between pages never blocks on the native renderer (the default
/// pdfx pinch view re-renders while scrolling, which freezes on large
/// files and low-end devices).
class _PdfViewerState extends State<_PdfViewer> {
  late final Future<PdfDocument> _document = PdfDocument.openFile(widget.path);
  final ScrollController _scrollController = ScrollController();
  double _viewportWidth = 0;
  int _pageCount = 0;
  static const double _pageGap = 12;

  /// Rendered page images, evicted oldest-first.
  final Map<int, ui.Image> _images = {};
  final List<int> _order = [];

  /// Pages currently being rendered (dedupe).
  final Set<int> _rendering = {};

  /// Page aspect ratios (width / height), from the native page.
  final Map<int, double> _aspects = {};

  /// How much sharper than screen size pages are rendered (crisp, cheap).
  static const double _quality = 1.5;

  /// Maximum rendered pages kept in memory.
  static const int _maxCached = 16;

  static const List<double> _zoomLevels = [1.0, 1.5, 2.0];
  double _zoom = 1.0;
  int _current = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateCurrent);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    for (final image in _images.values) {
      image.dispose();
    }
    unawaited(_document.then((doc) => doc.close()));
    super.dispose();
  }

  Future<void> _renderPage(int index, double viewportWidth) async {
    if (_rendering.contains(index) || _images.containsKey(index)) return;
    _rendering.add(index);
    try {
      final document = await _document;
      final page = await document.getPage(index + 1);
      _aspects[index] = page.width / page.height;
      ui.Image? image;
      try {
        final renderWidth = (viewportWidth * _zoom * _quality).clamp(
          100.0,
          4096.0,
        );
        final renderHeight = renderWidth / _aspects[index]!;
        final rendered = await page.render(
          width: renderWidth,
          height: renderHeight,
          format: PdfPageImageFormat.png,
        );
        if (rendered != null) {
          final codec = await ui.instantiateImageCodec(rendered.bytes);
          image = (await codec.getNextFrame()).image;
        }
      } catch (_) {
        image = null;
      } finally {
        await page.close();
      }
      if (!mounted || image == null) return;
      final ready = image;
      setState(() {
        _images.remove(index)?.dispose();
        _images[index] = ready;
        _order.add(index);
        while (_order.length > _maxCached) {
          final victim = _order.removeAt(0);
          final cached = _images.remove(victim);
          if (cached != null && cached != ready) cached.dispose();
        }
      });
      _updateCurrent();
    } catch (_) {
      // Unreadable page: keep the placeholder.
    } finally {
      _rendering.remove(index);
    }
  }

  void _setZoom(double zoom) {
    setState(() {
      _zoom = zoom;
      for (final image in _images.values) {
        image.dispose();
      }
      _images.clear();
      _order.clear();
      _aspects.clear();
    });
  }

  double _itemHeight(int index) {
    final aspect = _aspects[index];
    final pageHeight = aspect != null
        ? (_viewportWidth * _zoom) / aspect
        : _viewportWidth * _zoom * 1.414;
    return pageHeight + _pageGap;
  }

  void _updateCurrent() {
    if (!_scrollController.hasClients || _pageCount == 0) return;
    final offset = _scrollController.offset;
    double acc = 0;
    var idx = 0;
    for (var i = 0; i < _pageCount; i++) {
      final h = _itemHeight(i);
      if (acc + h * 0.5 >= offset) {
        idx = i;
        break;
      }
      acc += h;
      idx = i;
    }
    if (idx != _current) {
      _current = idx;
      if (mounted) setState(() {});
    }
  }

  Widget _buildPage(int index, double viewportWidth) {
    final image = _images[index];
    final aspect = _aspects[index];
    if (image == null || aspect == null) {
      // Kick off the render from a post-frame callback so this build
      // completes instantly; the page pops in when ready.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _renderPage(index, viewportWidth);
      });
      return const Center(
        child: SizedBox(
          width: 36,
          height: 36,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      );
    }
    final width = viewportWidth * _zoom;
    final height = width / aspect;
    final page = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Theme.of(context).colorScheme.surfaceContainerHigh
            : Colors.white,
        borderRadius: BorderRadius.circular(2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: RawImage(image: image, fit: BoxFit.fill),
    );
    if (_zoom > 1.0) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: page,
      );
    }
    return Center(child: page);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
        final document = snapshot.data!;
        final pages = document.pagesCount;
        if (pages == 0) {
          return const _CenterMessage(
            icon: Icons.picture_as_pdf,
            title: 'Empty PDF',
            subtitle: 'This document has no pages.',
          );
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final viewportWidth = constraints.maxWidth;
            _viewportWidth = viewportWidth;
            _pageCount = pages;
            return Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    cacheExtent: 800, // ignore: deprecated_member_use
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: pages,
                    itemBuilder: (context, index) {
                      if (!_images.containsKey(index) &&
                          !_rendering.contains(index)) {
                        _renderPage(index, viewportWidth);
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: _pageGap),
                        child: _buildPage(index, viewportWidth),
                      );
                    },
                  ),
                ),
                Material(
                  color: scheme.surfaceContainerLow,
                  elevation: 3,
                  child: SafeArea(
                    top: false,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: scheme.outlineVariant.withValues(alpha: 0.6),
                            width: 1,
                          ),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            tooltip: 'Zoom out',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.zoom_out),
                            onPressed: () {
                              final index =
                                  _zoomLevels.lastIndexWhere((z) => z < _zoom);
                              if (index >= 0) _setZoom(_zoomLevels[index]);
                            },
                          ),
                          Text(
                            'Page ${_current + 1} of $pages',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Zoom in',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.zoom_in),
                            onPressed: () {
                              final index = _zoomLevels.indexWhere(
                                (z) => z > _zoom,
                              );
                              if (index >= 0) _setZoom(_zoomLevels[index]);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
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
  bool _editing = false;
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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

  void _enterEdit(String content) {
    _controller.text = content;
    setState(() => _editing = true);
  }

  Future<void> _saveEdit() async {
    try {
      await File(widget.path).writeAsString(_controller.text, flush: true);
      if (!mounted) return;
      setState(() {
        _editing = false;
        _load = _read();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Saved')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save: $error')));
    }
  }

  void _cancelEdit() {
    setState(() => _editing = false);
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
        if (_editing) {
          // Inline editing: the text area replaces the read-only view and the
          // bottom bar switches to Save / Cancel. No separate screen.
          return Column(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  maxLines: null,
                  expands: true,
                  autofocus: true,
                  keyboardType: TextInputType.multiline,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(20),
                    hintText: 'Type your text...',
                  ),
                ),
              ),
              _ToolsBar(
                tools: [
                  _ToolItem(
                    icon: Icons.check,
                    label: 'Save',
                    onTap: _saveEdit,
                  ),
                  _ToolItem(
                    icon: Icons.close,
                    label: 'Cancel',
                    onTap: _cancelEdit,
                  ),
                ],
              ),
            ],
          );
        }
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
              ),
            ),
            _ToolsBar(
              tools: [
                _ToolItem(
                  icon: Icons.edit_outlined,
                  label: 'Edit',
                  onTap: () => _enterEdit(result.content),
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

  Future<void> _convertToPdf(String content) async {
    final baseName = sanitizeFileName(p.basenameWithoutExtension(widget.path));
    final fileName = '${baseName}_converted.pdf';
    try {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Converting to PDF…')));
      final bytes = await compute(
        _buildTextPdfInBackground,
        {'title': p.basename(widget.path), 'content': content},
      );
      final file = await saveOutput(bytes, fileName);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Saved to ${file.path}')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save PDF: $error')));
    }
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
  late Future<String> _content;

  @override
  void initState() {
    super.initState();
    _content = _extract();
  }

  Future<String> _extract() async {
    final text = await extractOfficeText(widget.file.path);
    return text.trim().isEmpty
        ? '(No readable text found in this file.)'
        : text;
  }

  Future<void> _convertToPdf() async {
    final baseName = sanitizeFileName(
      p.basenameWithoutExtension(widget.file.path),
    );
    final fileName = '${baseName}_converted.pdf';
    try {
      final content = await _content;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Converting to PDF…')));
      final bytes = await compute(
        _buildTextPdfInBackground,
        {'title': p.basename(widget.file.path), 'content': content},
      );
      final file = await saveOutput(bytes, fileName);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Saved to ${file.path}')));
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Converting to PDF…')));
      final bytes = await compute(
        _buildTextPdfInBackground,
        {'title': p.basename(widget.file.path), 'content': content},
      );
      final file = await saveOutput(bytes, fileName);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Saved to ${file.path}')));
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
                'Older .xls files are not supported — use Share to open it '
                'in another app.',
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
    const maxRows = 500;
    const maxCols = 40;
    final rows = sheet.rows.take(maxRows).toList();
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
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
                  for (var r = 0; r < rows.length; r++)
                    TableRow(
                      decoration: r == 0
                          ? BoxDecoration(
                              color: scheme.primaryContainer.withValues(
                                alpha: 0.3,
                              ),
                            )
                          : null,
                      children: [
                        for (var c = 0; c < rows[r].length && c < maxCols; c++)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            child: Text(
                              rows[r][c],
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: r == 0
                                    ? FontWeight.w600
                                    : FontWeight.w400,
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
          ),
          if (sheet.rows.length > maxRows ||
              rows.any((r) => r.length > maxCols))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Text(
                'Showing the first $maxRows rows of '
                '${sheet.rows.length} (Convert to PDF keeps everything).',
                style: TextStyle(
                  fontSize: 11.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PPTX Viewer – renders the actual slides (layout, shapes, colors, images)
// ---------------------------------------------------------------------------

class _PptxViewer extends StatefulWidget {
  const _PptxViewer({required this.file});

  final RecentFile file;

  @override
  State<_PptxViewer> createState() => _PptxViewerState();
}

class _PptxViewerState extends State<_PptxViewer> {
  late final Future<_PptxRenderResult> _load = _loadSlides();
  final PageController _controller = PageController();
  int _current = 0;

  Future<_PptxRenderResult> _loadSlides() async {
    try {
      final bytes = await File(widget.file.path).readAsBytes();
      final slides = parsePptxRender(bytes);
      final decoded = <int, Map<int, ui.Image>>{};
      for (var s = 0; s < slides.length; s++) {
        final slide = slides[s];
        final images = <int, ui.Image>{};
        final bkg = slide.backgroundImageBytes;
        final codec = bkg == null ? null : await ui.instantiateImageCodec(bkg);
        if (codec != null) {
          images[-1] = (await codec.getNextFrame()).image;
        }
        for (var i = 0; i < slide.shapes.length; i++) {
          final imageBytes = slide.shapes[i].imageBytes;
          if (imageBytes == null) continue;
          final shapeCodec = await ui.instantiateImageCodec(imageBytes);
          images[i] = (await shapeCodec.getNextFrame()).image;
        }
        if (images.isNotEmpty) decoded[s] = images;
      }
      return _PptxRenderResult(slides: slides, decodedImages: decoded);
    } catch (e) {
      return _PptxRenderResult(error: e);
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
        for (final shape in slide.shapes) {
          for (final line in shape.lines) {
            buffer.writeln(line.text);
          }
        }
        buffer.writeln();
      }
      final content = buffer.toString();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Converting to PDF…')));
      final bytes = await compute(
        _buildTextPdfInBackground,
        {'title': p.basename(widget.file.path), 'content': content},
      );
      final file = await saveOutput(bytes, fileName);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Saved to ${file.path}')));
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
    return FutureBuilder<_PptxRenderResult>(
      future: _load,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final result =
            snapshot.data ?? _PptxRenderResult(error: 'Unknown error');
        if (result.error != null) {
          return _pptxErrorView(
            title: 'Could not open this file',
            subtitle:
                'This is not a readable PowerPoint document, or it '
                'uses an older .ppt format. Use Share to open it in '
                'another app.',
          );
        }
        final slides = result.slides;
        if (slides.isEmpty || slides.every((s) => !s.hasContent)) {
          return _pptxErrorView(
            title: 'Empty presentation',
            subtitle:
                'No readable text found in this file. '
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
                  return InteractiveViewer(
                    maxScale: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: PptxSlideView(
                        slide: slide,
                        images:
                            result.decodedImages[index] ??
                            const <int, ui.Image>{},
                      ),
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

class _PptxRenderResult {
  const _PptxRenderResult({
    this.slides = const [],
    this.decodedImages = const {},
    this.error,
  });

  final List<PptxRenderSlide> slides;
  final Map<int, Map<int, ui.Image>> decodedImages;
  final Object? error;
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
      elevation: 3,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.6),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              for (final tool in tools)
                Expanded(child: _ToolButton(item: tool)),
            ],
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
      color: Colors.transparent,
      child: InkWell(
        onTap: item.onTap,
        child: SizedBox(
          height: 60,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(item.icon, size: 22, color: scheme.primary),
              const SizedBox(height: 6),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                  color: scheme.onSurface,
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

/// Runs [buildTextPdf] on a background isolate so the UI thread stays free
/// (building a large document on the main thread froze the app / triggered an
/// ANR). Must be top-level so it can be sent to the isolate via [compute].
Future<Uint8List> _buildTextPdfInBackground(Map<String, dynamic> args) =>
    buildTextPdf(title: args['title'] as String, content: args['content'] as String);
