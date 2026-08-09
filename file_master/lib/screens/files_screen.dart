import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import '../models/recent_file.dart';
import '../providers/recents_provider.dart';
import '../utils/doc_format.dart';
import '../utils/output_utils.dart';
import '../widgets/message_view.dart';
import 'viewer_screen.dart';

/// Device file browser.
///
/// Browsing the device works with any of:
///  - "All files access" on Android 11+ (full storage),
///  - legacy storage permission on Android 10,
///  - "Files and media" on Android 13+ (media files only, decided by the OS).
/// The screen re-checks permissions when the app returns from settings.
class FilesScreen extends ConsumerStatefulWidget {
  const FilesScreen({super.key, this.initialPath});

  /// Directory to open on start; defaults to the shared storage root.
  final String? initialPath;

  @override
  ConsumerState<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends ConsumerState<FilesScreen>
    with WidgetsBindingObserver {
  Directory? _current;
  List<FileSystemEntity> _entries = const [];
  String? _error;
  bool _loading = true;
  bool _allowRootAccess = false;

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
    // The user returns from the permission/settings screen.
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final allowed = await _hasAnyAccess();
    if (!mounted) return;
    if (allowed == _allowRootAccess) {
      if (allowed) await _reload();
    } else {
      await _init();
    }
  }

  /// True if the app can read any of the user's files.
  static Future<bool> _hasAnyAccess() async {
    if (!Platform.isAndroid) return true;
    final manage = await Permission.manageExternalStorage.status;
    if (manage.isGranted) return true;
    final storage = await Permission.storage.status;
    if (storage.isGranted) return true;
    const media = [
      Permission.photos,
      Permission.videos,
      Permission.audio,
    ];
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
    await _openDirectory(initial);
  }

  Future<void> _reload() async {
    final dir = _current;
    if (dir != null) await _openDirectory(dir);
  }

  Future<void> _openDirectory(Directory dir) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await dir.list(followLinks: false).toList();
      entries.sort(_compareEntries);
      if (!mounted) return;
      setState(() {
        _current = dir;
        _entries = entries;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  static int _compareEntries(FileSystemEntity a, FileSystemEntity b) {
    final aIsDir = a is Directory ? 0 : 1;
    final bIsDir = b is Directory ? 0 : 1;
    if (aIsDir != bIsDir) return aIsDir - bIsDir;
    return a.path.toLowerCase().compareTo(b.path.toLowerCase());
  }

  /// Asks for storage access step by step:
  /// "All files access" → legacy storage → media only (Android 13+).
  Future<void> _requestAccess() async {
    final manage = await Permission.manageExternalStorage.request();
    if (!manage.isGranted) {
      final storage = await Permission.storage.request();
      if (!storage.isGranted) {
        const media = [
          Permission.photos,
          Permission.videos,
          Permission.audio,
        ];
        await media.request();
      }
    }
    await _init();
  }

  Future<void> _browseViaPicker() async {
    final path = await FilePicker.getDirectoryPath();
    if (path == null) return;
    setState(() => _allowRootAccess = true);
    await _openDirectory(Directory(path));
  }

  Future<void> _openEntry(FileSystemEntity entry) async {
    if (entry is Directory) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FilesScreen(initialPath: entry.path),
        ),
      );
      return;
    }
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
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ViewerScreen(file: recent)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not open file: $error')));
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
                SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
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
      await _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not rename: $error')));
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
      await _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not delete: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_allowRootAccess) {
      return _buildGate();
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return MessageView(
        icon: Icons.error_outline,
        title: 'Could not open this folder',
        subtitle: _error,
        action: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () => _reload(),
              child: const Text('Retry'),
            ),
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
      subtitle: 'Allow "All files access" to see your documents, or '
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
    if (dir == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  dir.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              IconButton(
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh),
                onPressed: _reload,
              ),
            ],
          ),
        ),
        Expanded(
          child: _entries.isEmpty
              ? const MessageView(
                  icon: Icons.folder_outlined,
                  title: 'Empty folder',
                  subtitle: 'Nothing here yet',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  itemCount: _entries.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final entry = _entries[index];
                    return _EntryTile(
                      entry: entry,
                      onTap: () => _openEntry(entry),
                      onLongPress: () => _showActions(entry),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.onTap,
    required this.onLongPress,
  });

  final FileSystemEntity entry;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDir = entry is Directory;
    final icon = isDir
        ? Icons.folder
        : DocFormat.fromPath(entry.path).icon;
    return ListTile(
      leading: Icon(
        icon,
        color: isDir ? scheme.primary : scheme.onSurfaceVariant,
      ),
      title: Text(
        p.basename(entry.path),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: isDir
          ? null
          : Text(
              DocFormat.fromPath(entry.path).label,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}