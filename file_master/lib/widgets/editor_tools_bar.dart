import 'package:flutter/material.dart';

/// Alignment choices for created documents.
enum DocAlign { left, center, right, justify }

/// Horizontal toolbar with the basic text formatting controls shared by the
/// Create PDF and Create Word screens.
class EditorToolsBar extends StatelessWidget {
  const EditorToolsBar({
    super.key,
    required this.fontSize,
    required this.bold,
    required this.italic,
    required this.underline,
    required this.align,
    required this.onFontSize,
    required this.onBold,
    required this.onItalic,
    required this.onUnderline,
    required this.onAlign,
  });

  final double fontSize;
  final bool bold;
  final bool italic;
  final bool underline;
  final DocAlign align;
  final ValueChanged<double> onFontSize;
  final ValueChanged<bool> onBold;
  final ValueChanged<bool> onItalic;
  final ValueChanged<bool> onUnderline;
  final ValueChanged<DocAlign> onAlign;

  static const List<double> sizes = [10, 12, 14, 16, 20, 28];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final size in sizes)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text('${size.round()}'),
                selected: fontSize == size,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => onFontSize(size),
              ),
            ),
          const SizedBox(width: 6),
          ToggleButtons(
            isSelected: [bold, italic, underline],
            onPressed: (index) {
              switch (index) {
                case 0:
                  onBold(!bold);
                  break;
                case 1:
                  onItalic(!italic);
                  break;
                case 2:
                  onUnderline(!underline);
                  break;
              }
            },
            children: const [
              Icon(Icons.format_bold, size: 18),
              Icon(Icons.format_italic, size: 18),
              Icon(Icons.format_underlined, size: 18),
            ],
          ),
          const SizedBox(width: 8),
          SegmentedButton<DocAlign>(
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            segments: const [
              ButtonSegment(
                value: DocAlign.left,
                icon: Icon(Icons.format_align_left, size: 18),
                tooltip: 'Left',
              ),
              ButtonSegment(
                value: DocAlign.center,
                icon: Icon(Icons.format_align_center, size: 18),
                tooltip: 'Center',
              ),
              ButtonSegment(
                value: DocAlign.right,
                icon: Icon(Icons.format_align_right, size: 18),
                tooltip: 'Right',
              ),
              ButtonSegment(
                value: DocAlign.justify,
                icon: Icon(Icons.format_align_justify, size: 18),
                tooltip: 'Justify',
              ),
            ],
            selected: {align},
            onSelectionChanged: (selection) => onAlign(selection.first),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}