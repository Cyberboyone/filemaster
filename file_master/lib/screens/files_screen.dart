import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import '../models/recent_file.dart';
import '../providers/recents_provider.dart';
import '../theme/format_colors.dart';
import '../utils/doc_format.dart';
import '../utils/output_utils.dart';
import '../widgets/message_view.dart';
import 'viewer_screen.dart';

/// Device file browser grouped by format type (PDF, Word, PowerPoint, Excel,
/// Text). Image files are excluded.
class FilesScreen extends ConsumerStatefulWidget {
  const FilesScreen({super.key, this.initialPath});

  /// Directory to scan; defaults to the shared storage root.
  final String? initialPath;

  @override
  ConsumerState<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends ConsumerState<FilesScreen>
    with WidgetsBindingObserver {
  static const int _maxFiles = 600;

  Directory? _current;
  List<FileSystemEntity> _entries = const [];
  String? _error;
  bool _loading = true;
  bool _allowRootAccess = false;

  /// Which sections are expanded (format label -> expanded).
  final Map<String, bool> _expanded = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final allowed = await _hasAnyAccess();
    if (!mounted) return;
    if (allowed == _allowRootAccess) {
      if (allowed) await _scan();
    } else {
      await _init();
    }
  }

  static Future<bool> _hasAnyAccess() async {
    if (!Platform.isAndroid) return true;
    final manage = await Permission.manageExternalStorage.status;
    if (manage.isGranted) return true;
    final storage = await Permission.storage.status;
    if (storage.isGranted) return true;
    const media = [Permission.photos, Permission.videos, Permission.audio];
    final statuses = await media.request();
    for (final status in statuses.values) {
      if (status.isGranted || status.isLimited) return true;
    }
    return false;
  }

  Future<void> _init() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final allowRoot = await _hasAnyAccess();
    if (!mounted) return;
    setState(() => _allowRootAccess = allowRoot);

    Directory initial;
    if (widget.initialPath != null) {
      initial = Directory(widget.initialPath!);
    } else if (allowRoot) {
      initial = await getDefaultRoot();
    } else {
      initial = await getOutputDir();
    }
    await _scan(initial);
  }

  Future<void> _scan([Directory? target]) async {
    final dir = target ?? _current;
    if (dir == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final entries = await _listUsableFiles(dir);
    entries.sort((a, b) {
      return a.path.toLowerCase().compareTo(b.path.toLowerCase());
    });
    if (!mounted) return;
    setState(() {
      _current = dir;
      _entries = entries;
      _loading = false;
    });
  }

  /// Recursively collects the files this app can open, skipping hidden,
  /// system and app-data folders, capped at [_maxFiles].
  /// Images are excluded.
  static Future<List<File>> _listUsableFiles(Directory root) async {
    const skippedFolders = {
      'android',
      'obb',
      'cache',
      '.thumbnails',
      'lobster.dir',
      'lost.dir',
      'backup',
    };
    final found = <File>[];
    final pending = <Directory>[root];
    var visited = 0;
    while (pending.isNotEmpty && found.length < _maxFiles && visited < 4000) {
      final dir = pending.removeLast();
      visited++;
      List<FileSystemEntity> children;
      try {
        children = await dir.list(followLinks: false).toList();
      } catch (_) {
        continue;
      }
      for (final entry in children) {
        if (found.length >= _maxFiles) break;
        if (entry is Directory) {
          final name = p.basename(entry.path).toLowerCase();
          if (name.startsWith('.') || skippedFolders.contains(name)) continue;
          if (pending.length < 800) pending.add(entry);
        } else if (entry is File && _isUsableFile(entry.path)) {
          found.add(entry);
        }
      }
    }
    return found;
  }

  static bool _isUsableFile(String path) {
    final format = DocFormat.fromPath(path.replaceAll('\\', '/'));
    // Exclude images, archives, and other unsupported formats.
    return format != DocFormat.other &&
        format != DocFormat.archive &&
        format != DocFormat.image;
  }

  Future<void> _requestAccess() async {
    final manage = await Permission.manageExternalStorage.request();
    if (!manage.isGranted) {
      final storage = await Permission.storage.request();
      if (!storage.isGranted) {
        const media = [Permission.photos, Permission.videos, Permission.audio];
        await media.request();
      }
    }
    await _init();
  }

  Future<void> _browseViaPicker() async {
    final path = await FilePicker.getDirectoryPath();
    if (path == null) return;
    setState(() => _allowRootAccess = true);
    await _scan(Directory(path));
  }

  Future<void> _openEntry(FileSystemEntity entry) async {
    if (entry is! File) return;
    final file = File(entry.path);
    try {
      final stat = await file.stat();
      final recent = RecentFile(
        name: p.basename(file.path),
        path: file.path,
        format: DocFormat.fromPath(file.path),
        sizeBytes: stat.size,
        lastOpened: DateTime.now(),
      );
      await ref.read(recentsControllerProvider.notifier).recordOpen(recent);
      if (!mounted) return;
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => ViewerScreen(file: recent)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not open file: $error')));
    }
  }

  Future<void> _showActions(FileSystemEntity entry) async {
    if (entry is! File) return;
    final file = entry;
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('Open'),
              onTap: () {
                Navigator.pop(sheetContext);
                _openEntry(file);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('Share'),
              onTap: () {
                Navigator.pop(sheetContext);
                SharePlus.instance.share(
                  ShareParams(files: [XFile(file.path)]),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('Rename'),
              onTap: () {
                Navigator.pop(sheetContext);
                _rename(file);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: const Text('Delete'),
              textColor: Theme.of(context).colorScheme.error,
              onTap: () {
                Navigator.pop(sheetContext);
                _confirmDelete(file);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _rename(File file) async {
    final controller = TextEditingController(text: p.basename(file.path));
    if (!mounted) return;
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'New name'),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    if (newName == null || newName.trim().isEmpty) return;
    final target = File(p.join(file.parent.path, newName.trim()));
    try {
      await file.rename(target.path);
      await _scan();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not rename: $error')));
    }
  }

  Future<void> _confirmDelete(File file) async {
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete file?'),
        content: Text(p.basename(file.path)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await file.delete();
      await ref.read(recentsControllerProvider.notifier).remove(file.path);
      await _scan();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not delete: $error')));
    }
  }

  /// Groups entries by format type.
  Map<DocFormat, List<File>> _grouped() {
    final grouped = <DocFormat, List<File>>{
      DocFormat.pdf: [],
      DocFormat.word: [],
      DocFormat.powerpoint: [],
      DocFormat.excel: [],
      DocFormat.text: [],
    };
    for (final entry in _entries) {
      if (entry is! File) continue;
      final format = DocFormat.fromPath(entry.path);
      grouped[format]?.add(entry);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    if (!_allowRootAccess) return _buildGate();
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return MessageView(
        icon: Icons.error_outline,
        title: 'Could not scan this folder',
        subtitle: _error,
        action: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(onPressed: () => _scan(), child: const Text('Retry')),
            TextButton(
              onPressed: _browseViaPicker,
              child: const Text('Choose a folder instead'),
            ),
          ],
        ),
      );
    }
    return _buildBrowser();
  }

  Widget _buildGate() {
    return MessageView(
      icon: Icons.folder_special_outlined,
      title: 'Storage access needed',
      subtitle:
          'Allow "All files access" to see your documents, or '
          '"Files and media" access to see photos, videos and audio.',
      action: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.icon(
            onPressed: _requestAccess,
            icon: const Icon(Icons.settings_outlined),
            label: const Text('Allow access'),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: _browseViaPicker,
            child: const Text('Choose a folder instead'),
          ),
        ],
      ),
    );
  }

  Widget _buildBrowser() {
    final dir = _current;
    if (dir == null) return const Center(child: CircularProgressIndicator());
    final scheme = Theme.of(context).colorScheme;
    final grouped = _grouped();
    final sections = grouped.entries.where((e) => e.value.isNotEmpty).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${_entries.length} file${_entries.length == 1 ? '' : 's'} '
                  'in ${dir.path}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Choose a folder',
                icon: const Icon(Icons.folder_open_outlined),
                onPressed: _browseViaPicker,
              ),
              IconButton(
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh),
                onPressed: () => _scan(),
              ),
            ],
          ),
        ),
        Expanded(
          child: sections.isEmpty
              ? MessageView(
                  icon: Icons.filter_alt_off_outlined,
                  title: 'No supported files here',
                  subtitle:
                      'Only files this app can open are shown: PDF, '
                      'Word, PowerPoint, Excel and text.\n'
                      'Tap the folder icon to scan another folder.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  itemCount: sections.length,
                  itemBuilder: (context, index) {
                    final format = sections[index].key;
                    final files = sections[index].value;
                    return _FormatSection(
                      format: format,
                      files: files,
                      expanded:
                          _expanded[format.label] ?? (sections.length <= 3),
                      onToggle: () {
                        setState(() {
                          _expanded[format.label] =
                              !(_expanded[format.label] ??
                                  (sections.length <= 3));
                        });
                      },
                      onTapFile: _openEntry,
                      onLongPressFile: _showActions,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _FormatSection extends StatelessWidget {
  const _FormatSection({
    required this.format,
    required this.files,
    required this.expanded,
    required this.onToggle,
    required this.onTapFile,
    required this.onLongPressFile,
  });

  final DocFormat format;
  final List<File> files;
  final bool expanded;
  final VoidCallback onToggle;
  final void Function(FileSystemEntity) onTapFile;
  final void Function(FileSystemEntity) onLongPressFile;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final color = FormatColors.of(format);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: FormatColors.container(color, brightness),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        format.icon,
                        color: FormatColors.glyph(color, brightness),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            format.label,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            '${files.length} file${files.length == 1 ? '' : 's'}',
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            if (expanded) ...[
              const Divider(height: 1),
              for (final file in files)
                _FormatFileTile(
                  file: file,
                  onTap: () => onTapFile(file),
                  onLongPress: () => onLongPressFile(file),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FormatFileTile extends StatelessWidget {
  const _FormatFileTile({
    required this.file,
    required this.onTap,
    required this.onLongPress,
  });

  final File file;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final format = DocFormat.fromPath(file.path);
    final brightness = Theme.of(context).brightness;
    final color = FormatColors.of(format);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: FormatColors.container(color, brightness),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  format.icon,
                  color: FormatColors.glyph(color, brightness),
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  p.basename(file.path),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
