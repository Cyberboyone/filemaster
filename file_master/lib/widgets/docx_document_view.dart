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
  late final Future<ParsedDocx> _load = parseDocx(widget.path);

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
        return SelectionArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
            children: [
              for (final block in blocks) ..._buildBlocks(block, scheme),
            ],
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
          const Divider(height: 40),
          const SizedBox(height: 24),
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
                  TextSpan(
                    text: span.text,
                    style: _spanStyle(span, p, scheme),
                  ),
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
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  block.picture.bytes,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  errorBuilder: (context, error, stackTrace) => const SizedBox(
                    height: 48,
                    child: Center(child: Icon(Icons.image_outlined)),
                  ),
                ),
              ),
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
        ? [1.9, 1.6, 1.35, 1.2, 1.1, 1.05]
            .elementAt(paragraph.headingLevel.clamp(1, 6) - 1)
        : 1.0;
    return TextStyle(
      fontSize: span.sizePt * (96 / 72) * headingScale,
      fontWeight: span.bold || paragraph.isHeading
          ? FontWeight.w700
          : FontWeight.w400,
      fontStyle: span.italic ? FontStyle.italic : FontStyle.normal,
      decoration: span.underline ? TextDecoration.underline : null,
      height: 1.35,
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Table(
          border: TableBorder.all(
            color: scheme.outlineVariant.withValues(alpha: 0.7),
            width: 1,
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
                          height: 1.35,
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