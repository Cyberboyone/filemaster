import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/recent_file.dart';
import '../providers/recents_provider.dart';
import '../utils/doc_format.dart';
import '../utils/docx_builder.dart';
import '../utils/output_utils.dart';
import '../widgets/editor_tools_bar.dart';
import 'viewer_screen.dart';

/// Create a Word (.docx) document from a title and free text, with file
/// naming, formatting tools and a choose-your-own save location.
class CreateWordScreen extends ConsumerStatefulWidget {
  const CreateWordScreen({super.key});

  @override
  ConsumerState<CreateWordScreen> createState() => _CreateWordScreenState();
}

class _CreateWordScreenState extends ConsumerState<CreateWordScreen> {
  final _nameController = TextEditingController();
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();

  Directory? _saveDir;
  double _fontSize = 14;
  bool _bold = false;
  bool _italic = false;
  bool _underline = false;
  DocAlign _align = DocAlign.left;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  String _defaultFileName() {
    final title = _titleController.text.trim();
    return sanitizeFileName(title.isEmpty ? 'Untitled' : title);
  }

  Future<void> _pickFolder() async {
    final path = await FilePicker.getDirectoryPath();
    if (path == null) return;
    if (!mounted) return;
    setState(() => _saveDir = Directory(path));
  }

  String get _alignValue {
    switch (_align) {
      case DocAlign.center:
        return 'center';
      case DocAlign.right:
        return 'right';
      case DocAlign.justify:
        return 'justify';
      case DocAlign.left:
        return 'left';
    }
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();
    if (title.isEmpty && body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Write something before saving')),
      );
      return;
    }
    final name = _nameController.text.trim().isEmpty
        ? _defaultFileName()
        : sanitizeFileName(_nameController.text.trim());
    setState(() => _saving = true);
    try {
      final bytes = await buildDocx(
        title: title.isEmpty ? 'Untitled' : title,
        content: body,
        fontSize: _fontSize,
        bold: _bold,
        italic: _italic,
        underline: _underline,
        align: _alignValue,
      );
      final dir = _saveDir ?? await getOutputDir();
      final saved = await saveOutputIn(dir, bytes, '$name.docx');
      final recent = RecentFile(
        name: p.basename(saved.path),
        path: saved.path,
        format: DocFormat.word,
        sizeBytes: await saved.length(),
        lastOpened: DateTime.now(),
      );
      await ref.read(recentsControllerProvider.notifier).recordOpen(recent);
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Word document created'),
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
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not create Word file: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Word'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'File name',
                      hintText: 'e.g. My document',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    '.docx',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.folder_outlined,
                    size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _saveDir?.path ?? 'Default folder (FileMaster)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _pickFolder,
                  icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                  label: const Text('Change'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _titleController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Document title',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            EditorToolsBar(
              fontSize: _fontSize,
              bold: _bold,
              italic: _italic,
              underline: _underline,
              align: _align,
              onFontSize: (size) => setState(() => _fontSize = size),
              onBold: (value) => setState(() => _bold = value),
              onItalic: (value) => setState(() => _italic = value),
              onUnderline: (value) => setState(() => _underline = value),
              onAlign: (value) => setState(() => _align = value),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TextField(
                controller: _bodyController,
                expands: true,
                maxLines: null,
                minLines: null,
                textAlignVertical: TextAlignVertical.top,
                style: TextStyle(
                  fontSize: _fontSize,
                  fontWeight: _bold ? FontWeight.w700 : FontWeight.w400,
                  fontStyle: _italic ? FontStyle.italic : FontStyle.normal,
                  decoration: _underline
                      ? TextDecoration.underline
                      : TextDecoration.none,
                ),
                decoration: const InputDecoration(
                  labelText: 'Content',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}