import 'package:flutter/material.dart';

import '../models/recent_file.dart';
import '../theme/format_colors.dart';
import '../utils/doc_format.dart';

class RecentFileTile extends StatelessWidget {
  const RecentFileTile({
    super.key,
    required this.file,
    this.onTap,
    this.onDismiss,
    this.onLongPress,
    this.selecting = false,
    this.selected = false,
    this.pageCountFuture,
  });

  final RecentFile file;
  final VoidCallback? onTap;
  final VoidCallback? onDismiss;
  final VoidCallback? onLongPress;
  final bool selecting;
  final bool selected;

  /// Page count for PDF files; shown in the subtitle when available.
  final Future<int?>? pageCountFuture;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tile = Material(
      color: selecting
          ? (selected
              ? scheme.primaryContainer.withValues(alpha: 0.4)
              : scheme.surfaceContainerLow)
          : scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: ListTile(
        onTap: onTap,
        onLongPress: onLongPress,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 4,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        leading: selecting
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    selected ? Icons.check_circle : Icons.circle_outlined,
                    size: 22,
                    color: selected ? scheme.primary : scheme.outline,
                  ),
                  const SizedBox(width: 8),
                  _FormatIcon(format: file.format),
                ],
              )
            : _FormatIcon(format: file.format),
        title: Text(
          file.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: pageCountFuture == null
              ? _subtitle(context)
              : FutureBuilder<int?>(
                  future: pageCountFuture,
                  builder: (context, snapshot) {
                    return _subtitle(context, pages: snapshot.data);
                  },
                ),
        ),
        trailing: _formatSize(context, file.sizeBytes),
      ),
    );
    if (selecting || onDismiss == null) return tile;
    return Dismissible(
      key: ValueKey(file.path),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDismiss?.call(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
      ),
      child: tile,
    );
  }

  Widget _subtitle(BuildContext context, {int? pages}) {
    final scheme = Theme.of(context).colorScheme;
    final pagesText = pages == null
        ? ''
        : '  •  $pages page${pages == 1 ? '' : 's'}';
    return Text(
      '${file.format.label}  •  ${_relativeTime(context, file.lastOpened)}'
      '$pagesText',
      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
    );
  }

  static String _relativeTime(BuildContext context, DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${time.day}/${time.month}/${time.year}';
  }

  static Widget _formatSize(BuildContext context, int bytes) {
    if (bytes <= 0) return const SizedBox.shrink();
    String value;
    if (bytes < 1024) {
      value = '$bytes B';
    } else if (bytes < 1024 * 1024) {
      value = '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else {
      value = '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return Text(
      value,
      style: TextStyle(
        fontSize: 12,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _FormatIcon extends StatelessWidget {
  const _FormatIcon({required this.format});

  final DocFormat format;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final color = FormatColors.of(format);
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: FormatColors.container(color, brightness),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(
        format.icon,
        color: FormatColors.glyph(color, brightness),
        size: 24,
      ),
    );
  }
}
