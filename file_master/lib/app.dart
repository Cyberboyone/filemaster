import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/settings_provider.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

class FileMasterApp extends ConsumerWidget {
  const FileMasterApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    return MaterialApp(
      title: 'File Master',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: settings.themeMode,
      home: const HomeScreen(),
    );
  }
}
