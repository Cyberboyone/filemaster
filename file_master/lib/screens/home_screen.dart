import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/recent_file.dart';
import '../providers/recents_provider.dart';
import '../providers/settings_provider.dart';
import '../services/ad_banner.dart';
import '../utils/doc_format.dart';
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('File Master'),
        actions: [
          Consumer(
            builder: (context, ref, _) {
              final settings = ref.watch(settingsControllerProvider);
              return IconButton(
                tooltip: settings.darkMode
                    ? 'Switch to light'
                    : 'Switch to dark',
                icon: Icon(
                  settings.darkMode
                      ? Icons.light_mode_outlined
                      : Icons.dark_mode_outlined,
                ),
                onPressed: () => ref
                    .read(settingsControllerProvider.notifier)
                    .toggleDarkMode(),
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
      floatingActionButton: FloatingActionButton(
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
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
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

  @override
  Widget build(BuildContext context) {
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
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Text(
                  'Recent files',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(child: _buildRecentsList()),
            ],
          ),
        ),
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
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
          itemCount: filtered.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final file = filtered[index];
            return RecentFileTile(
              file: file,
              onTap: () => _openFile(file),
              onDismiss: () => ref
                  .read(recentsControllerProvider.notifier)
                  .remove(file.path),
            );
          },
        );
      },
    );
  }
}
