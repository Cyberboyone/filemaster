import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/recents_provider.dart';
import '../providers/settings_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionCard(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.dark_mode_outlined),
                title: const Text('Dark mode'),
                subtitle: const Text('Persisted on this device'),
                value: settings.darkMode,
                onChanged: (value) =>
                    ref.read(settingsControllerProvider.notifier).setDarkMode(value),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SectionCard(
            children: [
              ListTile(
                leading: const Icon(Icons.delete_sweep_outlined),
                title: const Text('Clear recent files'),
                onTap: () async {
                  final controller = ref.read(recentsControllerProvider.notifier);
                  await controller.clear();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Recent files cleared')),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          const AboutListTile(
            icon: Icon(Icons.info_outline),
            applicationName: 'File Master',
            applicationVersion: '1.0.0',
            applicationLegalese: 'Free document utility. Works fully offline.',
            aboutBoxChildren: [
              Text('File Master is a free, ad-supported document utility.'),
              SizedBox(height: 8),
              Text('No account required. Your files never leave your device.'),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 56),
            children[i],
          ],
        ],
      ),
    );
  }
}
