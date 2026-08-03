import 'package:flutter/material.dart';

import '../models/recent_file.dart';
import '../utils/doc_format.dart';

class RecentFileTile extends StatelessWidget {
  const RecentFileTile({super.key, required this.file, this.onTap, this.onDismiss});

  final RecentFile file;
  final VoidCallback? onTap;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
      child: ListTile(
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: _FormatIcon(format: file.format),
        title: Text(
          file.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          '${file.format.label}  •  ${_relativeTime(context, file.lastOpened)}',
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
        ),
        trailing: _formatSize(context, file.sizeBytes),
      ),
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
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(format.icon, color: scheme.onPrimaryContainer, size: 24),
    );
  }
}
