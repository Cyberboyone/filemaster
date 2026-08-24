import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'navigation.dart';
import 'providers/settings_provider.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

class FileMasterApp extends ConsumerWidget {
  const FileMasterApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final auto = ref.watch(autoThemeModeProvider);
    final themeMode =
        settings.preference == ThemePreference.auto
            ? (auto.value ?? settings.themeMode)
            : settings.themeMode;
    return MaterialApp(
      title: 'File Master',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      navigatorKey: navigatorKey,
      home: const HomeScreen(),
    );
  }
}
