import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../utils/docx_parser.dart';

/// Renders a parsed .docx document close to the original: styled
/// paragraphs, headings, aligned text, tables and inline images, in a
/// continuous scrollable page like a Word document.
class DocxDocumentView extends StatefulWidget {
  const DocxDocumentView({super.key, required this.path});

  final String path;

  @override
  State<DocxDocumentView> createState() => _DocxDocumentViewState();
}

class _DocxDocumentViewState extends State<DocxDocumentView> {
  // Parsing runs on a background isolate so large documents never block
  // the UI thread.
  late final Future<ParsedDocx> _load = compute(parseDocx, widget.path);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<ParsedDocx>(
      future: _load,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _DocxError(scheme: scheme);
        }
        final blocks = snapshot.data!.blocks;
        // Widget objects are cheap; layout is what matters, and that is
        // delegated to a lazily laid-out sliver list below.
        final flat = <Widget>[];
        for (final block in blocks) {
          flat.addAll(_buildBlocks(block, scheme));
        }
        return SelectionArea(
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? scheme.surfaceContainerHigh
                  : Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 28,
                  ),
                  sliver: SliverList.builder(
                    itemCount: flat.length,
                    itemBuilder: (context, index) => flat[index],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildBlocks(DocxBlock block, ColorScheme scheme) {
    if (block is DocxBlockParagraph) {
      final p = block.paragraph;
      if (p.isPageBreak && p.spans.isEmpty) {
        return [
          const SizedBox(height: 16),
          Divider(
            height: 1,
            color: scheme.outlineVariant.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
        ];
      }
      return [
        Padding(
          padding: EdgeInsets.only(
            top: p.spaceBeforePt * 96 / 72,
            bottom: p.spaceAfterPt * 96 / 72,
            left: p.indentLeftPt * 96 / 72,
          ),
          child: Text.rich(
            TextSpan(
              children: [
                for (final span in p.spans)
                  TextSpan(text: span.text, style: _spanStyle(span, p, scheme)),
              ],
            ),
            textAlign: _align(p.align),
          ),
        ),
      ];
    }
    if (block is DocxBlockTable) {
      return [_buildTable(block.table, scheme)];
    }
    if (block is DocxBlockPicture) {
      final picture = block.picture;
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Center(
            child: LayoutBuilder(
              builder: (context, constraints) {
                var w = picture.widthPx;
                var h = picture.heightPx;
                if (w != null && h != null) {
                  final available = constraints.maxWidth;
                  final scale = w > available ? available / w : 1.0;
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: w * scale,
                      height: h * scale,
                      child: Image.memory(
                        picture.bytes,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                        errorBuilder: (context, error, stackTrace) =>
                            const SizedBox(
                              height: 64,
                              child: Center(child: Icon(Icons.image_outlined)),
                            ),
                      ),
                    ),
                  );
                }
                return ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 320,
                    maxHeight: 420,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.memory(
                      picture.bytes,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      errorBuilder: (context, error, stackTrace) =>
                          const SizedBox(
                            height: 64,
                            child: Center(child: Icon(Icons.image_outlined)),
                          ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ];
    }
    return const [];
  }

  static TextStyle? _spanStyle(
    DocxSpan span,
    DocxParagraph paragraph,
    ColorScheme scheme,
  ) {
    final headingScale = paragraph.isHeading
        ? [
            1.9,
            1.6,
            1.35,
            1.2,
            1.1,
            1.05,
          ].elementAt(paragraph.headingLevel.clamp(1, 6) - 1)
        : 1.0;
    return TextStyle(
      fontSize: span.sizePt * (96 / 72) * headingScale,
      fontWeight: span.bold || paragraph.isHeading
          ? FontWeight.w700
          : FontWeight.w400,
      fontStyle: span.italic ? FontStyle.italic : FontStyle.normal,
      decoration: span.underline ? TextDecoration.underline : null,
      height: 1.5,
      color: scheme.onSurface,
    );
  }

  static TextAlign _align(DocxAlign align) {
    return switch (align) {
      DocxAlign.center => TextAlign.center,
      DocxAlign.right => TextAlign.right,
      DocxAlign.justify => TextAlign.justify,
      DocxAlign.left => TextAlign.left,
    };
  }

  Widget _buildTable(DocxTable table, ColorScheme scheme) {
    if (table.rows.isEmpty) return const SizedBox.shrink();
    final maxCols = table.rows.map((r) => r.cells.length).fold<int>(
      0,
      (a, b) => b > a ? b : a,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Table(
          border: TableBorder.all(
            color: scheme.outlineVariant.withValues(alpha: 0.6),
            width: 0.5,
          ),
          defaultColumnWidth: const FlexColumnWidth(),
          children: [
            for (final row in table.rows)
              TableRow(
                decoration: row.isHeader
                    ? BoxDecoration(color: scheme.primaryContainer)
                    : null,
                children: [
                  for (final cell in row.cells)
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: DefaultTextStyle.merge(
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          fontWeight: row.isHeader
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: row.isHeader
                              ? scheme.onPrimaryContainer
                              : scheme.onSurface,
                        ),
                        child: Text(cell.plainText),
                      ),
                    ),
                  // Pad shorter rows so every TableRow has [maxCols] cells.
                  for (var i = row.cells.length; i < maxCols; i++)
                    const SizedBox.shrink(),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _DocxError extends StatelessWidget {
  const _DocxError({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.description_outlined, size: 48, color: scheme.outline),
            const SizedBox(height: 16),
            Text(
              'Could not open this Word file',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'The file may be corrupted or use an unsupported format.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
