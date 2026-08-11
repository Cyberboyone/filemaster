import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart' as pw;
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import '../models/recent_file.dart';
import '../providers/recents_provider.dart';
import '../theme/format_colors.dart';
import '../utils/doc_format.dart';
import '../utils/output_utils.dart';
import '../widgets/message_view.dart';
import 'viewer_screen.dart';

/// Device file browser grouped by format type (PDF, Word, Text). Sections
/// are always expanded and sit at the top; the folder picker, select and
/// refresh actions are in the header. Files can be multi-selected (long
/// press) and deleted/shared together. PDF tiles show their page count.
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

  /// Multi-select state (paths of selected files).
  bool _selecting = false;
  final Set<String> _selected = {};

  final ScrollController _scrollController = ScrollController();

  /// Lazily computed page counts for PDF files (path -> future).
  final Map<String, Future<int?>> _pageCounts = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
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
      _selecting = false;
      _selected.clear();
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
  /// Images, PowerPoint, Excel and archives are excluded.
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
    // Exclude images, archives, PowerPoint/Excel (removed) and other
    // unsupported formats.
    return format != DocFormat.other &&
        format != DocFormat.archive &&
        format != DocFormat.image &&
        format != DocFormat.powerpoint &&
        format != DocFormat.excel;
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

  // --- multi-select --------------------------------------------------------

  void _enterSelection(String path) {
    setState(() {
      _selecting = true;
      _selected.add(path);
    });
  }

  void _exitSelection() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  void _toggleSelected(String path) {
    setState(() {
      if (!_selected.remove(path)) _selected.add(path);
    });
  }

  Future<void> _shareSelection() async {
    final files = _selected.map((path) => XFile(path)).toList();
    await SharePlus.instance.share(ShareParams(files: files));
  }

  Future<void> _renameSelected() async {
    if (_selected.length != 1) return;
    final file = File(_selected.first);
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
      _exitSelection();
      await _scan();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not rename: $error')));
    }
  }

  Future<void> _deleteSelection() async {
    final count = _selected.length;
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete $count file${count == 1 ? '' : 's'}?'),
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
    var failed = 0;
    for (final path in _selected.toList()) {
      try {
        await File(path).delete();
        await ref.read(recentsControllerProvider.notifier).remove(path);
      } catch (_) {
        failed++;
      }
    }
    _exitSelection();
    await _scan();
    if (!mounted) return;
    if (failed > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$failed file${failed == 1 ? '' : 's'} could not be deleted')),
      );
    }
  }

  // --- page counts ---------------------------------------------------------

  Future<int?> _pageCount(File file) {
    return _pageCounts.putIfAbsent(file.path, () async {
      try {
        final doc = await pw.PdfDocument.openFile(file.path);
        final count = doc.pages.count;
        await doc.close();
        return count;
      } catch (_) {
        return null;
      }
    });
  }

  /// Groups entries by format type (PDF, Word, Text).
  Map<DocFormat, List<File>> _grouped() {
    final grouped = <DocFormat, List<File>>{
      DocFormat.pdf: [],
      DocFormat.word: [],
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
        // Header: folder picker, select, refresh.
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: _browseViaPicker,
                icon: const Icon(Icons.folder_open_outlined, size: 18),
                label: const Text('Choose folder'),
              ),
              const Spacer(),
              if (!_selecting)
                TextButton.icon(
                  onPressed: () => setState(() => _selecting = true),
                  icon: const Icon(Icons.check_box_outlined, size: 18),
                  label: const Text('Select'),
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
                      'Word and text files.\n'
                      'Tap the folder icon to scan another folder.',
                )
              : _buildFileList(sections, scheme),
        ),
        if (_selecting) _buildSelectionBar(scheme),
      ],
    );
  }

  /// Flattens the sections into one lazily built list (fast scrolling) with
  /// always-visible section headers and a draggable scrollbar.
  Widget _buildFileList(
    List<MapEntry<DocFormat, List<File>>> sections,
    ColorScheme scheme,
  ) {
    final items = <Object>[];
    for (final section in sections) {
      items.add(section);
      items.addAll(section.value);
    }
    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      trackVisibility: true,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          if (item is MapEntry<DocFormat, List<File>>) {
            return _SectionHeader(
              format: item.key,
              count: item.value.length,
              scheme: scheme,
            );
          }
          final file = item as File;
          final format = DocFormat.fromPath(file.path);
          return _FormatFileTile(
            file: file,
            selecting: _selecting,
            selected: _selected.contains(file.path),
            pageCountFuture: format == DocFormat.pdf
                ? _pageCount(file)
                : null,
            onTap: () {
              if (_selecting) {
                _toggleSelected(file.path);
              } else {
                _openEntry(file);
              }
            },
            onLongPress: () {
              if (!_selecting) _enterSelection(file.path);
            },
          );
        },
      ),
    );
  }

  Widget _buildSelectionBar(ColorScheme scheme) {
    return Material(
      elevation: 8,
      color: scheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Cancel selection',
                icon: const Icon(Icons.close),
                onPressed: _exitSelection,
              ),
              Text(
                '${_selected.length} selected',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              if (_selected.length == 1)
                IconButton(
                  tooltip: 'Rename',
                  icon: const Icon(Icons.drive_file_rename_outline),
                  onPressed: _renameSelected,
                ),
              IconButton(
                tooltip: 'Share',
                icon: const Icon(Icons.share_outlined),
                onPressed: _selected.isEmpty ? null : _shareSelection,
              ),
              IconButton(
                tooltip: 'Delete',
                icon: Icon(Icons.delete_outline, color: scheme.error),
                onPressed: _selected.isEmpty ? null : _deleteSelection,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Always-expanded section header (icon, format label, file count).
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.format,
    required this.count,
    required this.scheme,
  });

  final DocFormat format;
  final int count;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final color = FormatColors.of(format);
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: FormatColors.container(color, brightness),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              format.icon,
              color: FormatColors.glyph(color, brightness),
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              format.label,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
          Text(
            '$count file${count == 1 ? '' : 's'}',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _FormatFileTile extends StatelessWidget {
  const _FormatFileTile({
    required this.file,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    this.pageCountFuture,
  });

  final File file;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final Future<int?>? pageCountFuture;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final format = DocFormat.fromPath(file.path);
    final brightness = Theme.of(context).brightness;
    final color = FormatColors.of(format);

    return Material(
      color: selected
          ? scheme.primaryContainer.withValues(alpha: 0.4)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              if (selecting) ...[
                Icon(
                  selected
                      ? Icons.check_circle
                      : Icons.circle_outlined,
                  size: 22,
                  color: selected ? scheme.primary : scheme.outline,
                ),
                const SizedBox(width: 8),
              ],
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.basename(file.path),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (pageCountFuture != null)
                      FutureBuilder<int?>(
                        future: pageCountFuture,
                        builder: (context, snapshot) {
                          final pages = snapshot.data;
                          if (pages == null) return const SizedBox.shrink();
                          return Text(
                            '$pages page${pages == 1 ? '' : 's'}',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (!selecting)
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