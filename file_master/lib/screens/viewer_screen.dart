import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/recent_file.dart';
import '../utils/doc_format.dart';
import '../widgets/docx_document_view.dart';

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
              DocFormat.excel => _UnsupportedViewer(
                file: file,
                icon: file.format.icon,
                message:
                    'Preview for ${file.format.label} files is not available. '
                    'Use Share to open it in another app.',
              ),
              DocFormat.powerpoint => _UnsupportedViewer(
                file: file,
                icon: file.format.icon,
                message:
                    'Preview for ${file.format.label} files is not available. '
                    'Use Share to open it in another app.',
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
  @override
  Widget build(BuildContext context) {
    return DocxDocumentView(path: widget.file.path);
  }
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
