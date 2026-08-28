import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../models/recent_file.dart';
import '../providers/recents_provider.dart';
import '../providers/selection_provider.dart';
import '../providers/settings_provider.dart';
import '../services/ad_banner.dart';
import '../services/ad_interstitial.dart';
import '../utils/doc_format.dart';
import '../utils/pdf_page_counter.dart';
import '../widgets/message_view.dart';
import '../widgets/recent_file_tile.dart';
import 'convert_screen.dart';
import 'create_pdf_screen.dart';
import 'create_word_screen.dart';
import 'files_screen.dart';
import 'merge_screen.dart';
import 'scan_screen.dart';
import 'settings_screen.dart';
import 'viewer_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    // Show the app-open interstitial only once per app process.
    AdInterstitial.instance.showAppOpen(onDone: () {});
  }

  Future<void> _pickAndRecord() async {
    final picked = await FilePicker.pickFile();
    final path = picked?.path;
    if (picked == null || path == null) return;

    final file = RecentFile(
      name: picked.name,
      path: path,
      format: DocFormat.fromPath(path),
      sizeBytes: picked.size,
      lastOpened: DateTime.now(),
    );
    await ref.read(recentsControllerProvider.notifier).recordOpen(file);
    if (!mounted) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ViewerScreen(file: file)));
  }

  void _openTool(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  void _showQuickActions() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        final tools = <({IconData icon, String title, VoidCallback onTap})>[
          (
            icon: Icons.folder_open_outlined,
            title: 'Open file',
            onTap: () {
              Navigator.pop(sheetContext);
              _pickAndRecord();
            },
          ),
          (
            icon: Icons.document_scanner_outlined,
            title: 'Scan to PDF',
            onTap: () {
              Navigator.pop(sheetContext);
              _openTool(const ScanScreen());
            },
          ),
          (
            icon: Icons.note_add_outlined,
            title: 'Create PDF',
            onTap: () {
              Navigator.pop(sheetContext);
              _openTool(const CreatePdfScreen());
            },
          ),
          (
            icon: Icons.description_outlined,
            title: 'Create Word',
            onTap: () {
              Navigator.pop(sheetContext);
              _openTool(const CreateWordScreen());
            },
          ),
          (
            icon: Icons.call_merge_outlined,
            title: 'Merge PDFs',
            onTap: () {
              Navigator.pop(sheetContext);
              _openTool(const MergePdfScreen());
            },
          ),
          (
            icon: Icons.swap_horiz_outlined,
            title: 'Convert',
            onTap: () {
              Navigator.pop(sheetContext);
              _openTool(const ConvertScreen());
            },
          ),
        ];
        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 380),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                    child: Text(
                      'Quick actions',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.9,
                    children: [
                      for (final tool in tools)
                        _QuickActionCard(
                          icon: tool.icon,
                          title: tool.title,
                          onTap: tool.onTap,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectionActive = ref.watch(selectionActiveProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('File Master'),
        actions: [
          Consumer(
            builder: (context, ref, _) {
              final preference = ref.watch(
                settingsControllerProvider,
              ).preference;
              final (icon, tooltip) = switch (preference) {
                ThemePreference.auto => (
                  Icons.brightness_auto,
                  'Automatic theme',
                ),
                ThemePreference.light => (
                  Icons.light_mode_outlined,
                  'Light theme',
                ),
                ThemePreference.dark => (Icons.dark_mode_outlined, 'Dark theme'),
              };
              return IconButton(
                tooltip: '$tooltip (tap to change)',
                icon: Icon(icon),
                onPressed: () => ref
                    .read(settingsControllerProvider.notifier)
                    .cycleTheme(),
              );
            },
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: IndexedStack(
        index: _tabIndex,
        children: const [_RecentsTab(), FilesScreen()],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: const AdBanner(),
          ),
          SizedBox(
            height: 80,
            child: NavigationBar(
              selectedIndex: _tabIndex,
              onDestinationSelected: (index) =>
                  setState(() => _tabIndex = index),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.history_outlined),
                  selectedIcon: Icon(Icons.history),
                  label: 'Recents',
                ),
                NavigationDestination(
                  icon: Icon(Icons.folder_outlined),
                  selectedIcon: Icon(Icons.folder),
                  label: 'Files',
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: selectionActive
          ? null
          : FloatingActionButton(
              tooltip: 'Quick actions',
              onPressed: _showQuickActions,
              child: const Icon(Icons.add),
            ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: scheme.onSecondaryContainer),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentsTab extends ConsumerStatefulWidget {
  const _RecentsTab();

  @override
  ConsumerState<_RecentsTab> createState() => _RecentsTabState();
}

class _RecentsTabState extends ConsumerState<_RecentsTab> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _query = '';

  /// Multi-select state (paths of selected files).
  bool _selecting = false;
  final Set<String> _selected = {};

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _openFile(RecentFile file) async {
    await ref
        .read(recentsControllerProvider.notifier)
        .recordOpen(file.copyWith(lastOpened: DateTime.now()));
    if (!mounted) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ViewerScreen(file: file)));
  }

  // --- multi-select --------------------------------------------------------

  void _enterSelection(RecentFile file) {
    ref.read(selectionActiveProvider.notifier).state = true;
    setState(() {
      _selecting = true;
      _selected.add(file.path);
    });
  }

  void _startSelection() {
    ref.read(selectionActiveProvider.notifier).state = true;
    setState(() => _selecting = true);
  }

  void _exitSelection() {
    ref.read(selectionActiveProvider.notifier).state = false;
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
      final recent = RecentFile(
        name: newName.trim(),
        path: target.path,
        format: DocFormat.fromPath(target.path),
        sizeBytes: await target.length(),
        lastOpened: DateTime.now(),
      );
      final notifier = ref.read(recentsControllerProvider.notifier);
      await notifier.remove(file.path);
      await notifier.recordOpen(recent);
      _exitSelection();
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
    if (!mounted) return;
    if (failed > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('$failed file${failed == 1 ? '' : 's'} could not be deleted'),
        ),
      );
    }
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final recents = ref.watch(recentsControllerProvider);
    final hasRecents = recents.valueOrNull?.isNotEmpty ?? false;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _searchController,
            onChanged: (value) =>
                setState(() => _query = value.trim().toLowerCase()),
            decoration: InputDecoration(
              hintText: 'Search by name or type',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 12, 4),
                child: Row(
                  children: [
                    Text(
                      'Recent files',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    if (!_selecting && hasRecents)
                      TextButton.icon(
                        onPressed: _startSelection,
                        icon: const Icon(Icons.check_box_outlined, size: 18),
                        label: const Text('Select'),
                      ),
                  ],
                ),
              ),
              Expanded(child: _buildRecentsList()),
            ],
          ),
        ),
        if (_selecting) _buildSelectionBar(scheme),
      ],
    );
  }

  Widget _buildRecentsList() {
    final recents = ref.watch(recentsControllerProvider);
    return recents.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => MessageView(
        icon: Icons.error_outline,
        title: 'Could not load recents',
        subtitle: '$error',
        action: TextButton(
          onPressed: () => ref.invalidate(recentsControllerProvider),
          child: const Text('Retry'),
        ),
      ),
      data: (files) {
        final filtered = _query.isEmpty
            ? files
            : files.where((f) {
                return f.name.toLowerCase().contains(_query) ||
                    f.format.label.toLowerCase().contains(_query);
              }).toList();

        if (files.isEmpty) {
          return const MessageView(
            icon: Icons.history,
            title: 'No recent files',
            subtitle: 'Tap + to open a file from your device',
          );
        }
        if (filtered.isEmpty) {
          return const MessageView(
            icon: Icons.search_off,
            title: 'No results',
            subtitle: 'Try a different search',
          );
        }
        return Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          trackVisibility: true,
          child: ListView.separated(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            itemCount: filtered.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final file = filtered[index];
              return RecentFileTile(
                file: file,
                pageCountFuture: file.format == DocFormat.pdf
                    ? pdfPageCount(file.path)
                    : null,
                selecting: _selecting,
                selected: _selected.contains(file.path),
                onTap: () {
                  if (_selecting) {
                    _toggleSelected(file.path);
                  } else {
                    _openFile(file);
                  }
                },
                onLongPress: () {
                  if (!_selecting) _enterSelection(file);
                },
                onDismiss: _selecting
                    ? null
                    : () => ref
                          .read(recentsControllerProvider.notifier)
                          .remove(file.path),
              );
            },
          ),
        );
      },
    );
  }
}
