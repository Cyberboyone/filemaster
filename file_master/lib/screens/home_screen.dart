import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/recent_file.dart';
import '../providers/recents_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/doc_format.dart';
import '../widgets/recent_file_tile.dart';
import 'settings_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _pickAndRecord() async {
    final picked = await FilePicker.pickFile();
    final path = picked?.path;
    if (picked == null || path == null) return;

    await ref.read(recentsControllerProvider.notifier).recordOpen(
          RecentFile(
            name: picked.name,
            path: path,
            format: DocFormat.fromPath(path),
            sizeBytes: picked.size,
            lastOpened: DateTime.now(),
          ),
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Opened ${picked.name}')));
  }

  Future<void> _openFile(RecentFile file) async {
    await ref.read(recentsControllerProvider.notifier).recordOpen(file.copyWith(
          lastOpened: DateTime.now(),
        ));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Viewer coming in Phase 2: ${file.name}')));
  }

  void _showQuickActions() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('Open file'),
              subtitle: const Text('Browse device storage'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickAndRecord();
              },
            ),
            ListTile(
              leading: const Icon(Icons.document_scanner_outlined),
              title: const Text('Scan to PDF'),
              subtitle: const Text('Coming in Phase 3'),
              onTap: () {
                Navigator.pop(sheetContext);
                _comingSoon('Scan to PDF');
              },
            ),
            ListTile(
              leading: const Icon(Icons.note_add_outlined),
              title: const Text('Create PDF'),
              subtitle: const Text('Coming in Phase 3'),
              onTap: () {
                Navigator.pop(sheetContext);
                _comingSoon('Create PDF');
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _comingSoon(String feature) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$feature — coming in Phase 3')));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('File Master'),
        actions: [
          Consumer(
            builder: (context, ref, _) {
              final settings = ref.watch(settingsControllerProvider);
              return IconButton(
                tooltip: settings.darkMode ? 'Switch to light' : 'Switch to dark',
                icon: Icon(
                  settings.darkMode ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                ),
                onPressed: () =>
                    ref.read(settingsControllerProvider.notifier).toggleDarkMode(),
              );
            },
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
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
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                Expanded(child: _buildRecentsList()),
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

  Widget _buildRecentsList() {
    final recents = ref.watch(recentsControllerProvider);
    return recents.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => _Message(
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
          return const _Message(
            icon: Icons.history,
            title: 'No recent files',
            subtitle: 'Tap + to open a file from your device',
          );
        }
        if (filtered.isEmpty) {
          return const _Message(
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
              onDismiss: () =>
                  ref.read(recentsControllerProvider.notifier).remove(file.path),
            );
          },
        );
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, this.subtitle, this.action});

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: scheme.outline),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 8),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
