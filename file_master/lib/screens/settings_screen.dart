import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/recents_provider.dart';
import '../providers/settings_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionCard(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: Text(
                  'Theme',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              _ThemeOption(
                preference: ThemePreference.auto,
                title: 'Automatic',
                subtitle: 'Light by day, dark by night (device time)',
                icon: Icons.brightness_auto,
              ),
              _ThemeOption(
                preference: ThemePreference.light,
                title: 'Light',
                subtitle: 'Always light',
                icon: Icons.light_mode_outlined,
              ),
              _ThemeOption(
                preference: ThemePreference.dark,
                title: 'Dark',
                subtitle: 'Always dark',
                icon: Icons.dark_mode_outlined,
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
                  final controller = ref.read(
                    recentsControllerProvider.notifier,
                  );
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
            applicationVersion: '1.0.9',
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

class _ThemeOption extends ConsumerWidget {
  const _ThemeOption({
    required this.preference,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final ThemePreference preference;
  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected =
        ref.watch(settingsControllerProvider).preference == preference;
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Icon(
        selected
            ? Icons.radio_button_checked
            : Icons.radio_button_unchecked,
        color: selected
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.outline,
      ),
      onTap: () =>
          ref.read(settingsControllerProvider.notifier).setPreference(
                preference,
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
