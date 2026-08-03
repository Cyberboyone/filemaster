import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kDarkModePrefKey = 'dark_mode';

final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('Override in main()'),
);

class Settings {
  const Settings({required this.darkMode});

  final bool darkMode;

  ThemeMode get themeMode => darkMode ? ThemeMode.dark : ThemeMode.light;

  Settings copyWith({bool? darkMode}) {
    return Settings(darkMode: darkMode ?? this.darkMode);
  }

  static Settings fromPrefs(SharedPreferences prefs) {
    return Settings(darkMode: prefs.getBool(kDarkModePrefKey) ?? false);
  }
}

class SettingsController extends Notifier<Settings> {
  @override
  Settings build() {
    return Settings.fromPrefs(ref.watch(sharedPreferencesProvider));
  }

  Future<void> setDarkMode(bool value) async {
    state = state.copyWith(darkMode: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kDarkModePrefKey, value);
  }

  Future<void> toggleDarkMode() => setDarkMode(!state.darkMode);
}

final settingsControllerProvider =
    NotifierProvider<SettingsController, Settings>(SettingsController.new);
