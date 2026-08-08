import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/recent_file.dart';
import '../providers/recents_provider.dart';
import '../utils/doc_format.dart';
import '../utils/output_utils.dart';
import '../utils/pdf_builder.dart';
import '../utils/pdf_render.dart';
import '../widgets/message_view.dart';
import 'viewer_screen.dart';

/// Combine multiple PDF files into a single document.
class MergePdfScreen extends ConsumerStatefulWidget {
  const MergePdfScreen({super.key});

  @override
  ConsumerState<MergePdfScreen> createState() => _MergePdfScreenState();
}

class _MergePdfScreenState extends ConsumerState<MergePdfScreen> {
  final List<String> _paths = [];
  bool _merging = false;

  Future<void> _addPdfs() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result == null) return;
    setState(() {
      for (final file in result.files) {
        final path = file.path;
        if (path != null && !_paths.contains(path)) _paths.add(path);
      }
    });
  }

  Future<void> _merge() async {
    if (_paths.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least two PDFs to merge')),
      );
      return;
    }
    setState(() => _merging = true);
    try {
      final pages = <Uint8List>[];
      for (final path in _paths) {
        pages.addAll(await renderPdfToImages(path));
      }
      final bytes = await buildPdfFromPages(pages);
      final saved = await saveOutput(bytes, timestampedName('Merged', 'pdf'));
      final recent = RecentFile(
        name: p.basename(saved.path),
        path: saved.path,
        format: DocFormat.pdf,
        sizeBytes: await saved.length(),
        lastOpened: DateTime.now(),
      );
      await ref.read(recentsControllerProvider.notifier).recordOpen(recent);
      if (!mounted) return;
      setState(() => _merging = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Merged ${_paths.length} files into one PDF'),
          action: SnackBarAction(
            label: 'Open',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ViewerScreen(file: recent)),
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _merging = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Merge failed: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Merge PDFs')),
      body: _paths.isEmpty
          ? MessageView(
              icon: Icons.merge_type,
              title: 'No PDFs selected',
              subtitle: 'Add two or more PDFs to combine them into one file.',
              action: FilledButton.icon(
                onPressed: _addPdfs,
                icon: const Icon(Icons.add),
                label: const Text('Add PDFs'),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${_paths.length} file(s) — drag to reorder',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Add PDFs',
                        icon: const Icon(Icons.add),
                        onPressed: _addPdfs,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                    itemCount: _paths.length,
                    onReorderItem: (oldIndex, newIndex) {
                      setState(() {
                        final path = _paths.removeAt(oldIndex);
                        _paths.insert(newIndex, path);
                      });
                    },
                    itemBuilder: (context, index) {
                      final path = _paths[index];
                      return ListTile(
                        key: ValueKey(path),
                        leading: const Icon(Icons.picture_as_pdf),
                        title: Text(
                          p.basename(path),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () =>
                              setState(() => _paths.removeAt(index)),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
      floatingActionButton: _paths.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _merging ? null : _merge,
              icon: _merging
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.call_merge),
              label: Text(_merging ? 'Merging…' : 'Merge'),
            ),
    );
  }
}
