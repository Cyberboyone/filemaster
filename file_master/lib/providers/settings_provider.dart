import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kDarkModePrefKey = 'dark_mode';
const String kThemePrefKey = 'theme_preference';

/// User theme choice. `auto` follows the device local time (time zone): light
/// during the day, dark at night.
enum ThemePreference { light, dark, auto }

final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('Override in main()'),
);

/// Returns the [ThemeMode] for a given local time: light between 06:00 and
/// 18:00, dark otherwise. Based purely on the device time zone.
ThemeMode autoThemeMode(DateTime now) {
  final hour = now.hour;
  return (hour >= 6 && hour < 18) ? ThemeMode.light : ThemeMode.dark;
}

class Settings {
  const Settings({required this.preference});

  final ThemePreference preference;

  ThemeMode get themeMode {
    return switch (preference) {
      ThemePreference.light => ThemeMode.light,
      ThemePreference.dark => ThemeMode.dark,
      ThemePreference.auto => autoThemeMode(DateTime.now()),
    };
  }

  /// Kept for callers (e.g. the quick-toggle icon) that only care about the
  /// current effective dark state.
  bool get darkMode =>
      preference == ThemePreference.dark ||
      (preference == ThemePreference.auto &&
          autoThemeMode(DateTime.now()) == ThemeMode.dark);

  Settings copyWith({ThemePreference? preference}) {
    return Settings(preference: preference ?? this.preference);
  }

  static Settings fromPrefs(SharedPreferences prefs) {
    final stored = prefs.getString(kThemePrefKey);
    if (stored != null) {
      final match = ThemePreference.values.where((e) => e.name == stored);
      if (match.isNotEmpty) return Settings(preference: match.first);
    }
    // Backward compatibility: migrate the legacy boolean dark_mode flag so an
    // existing install keeps its exact previous behaviour.
    final dark = prefs.getBool(kDarkModePrefKey);
    if (dark != null) {
      return Settings(
        preference: dark ? ThemePreference.dark : ThemePreference.light,
      );
    }
    // Fresh install defaults to automatic (time based).
    return const Settings(preference: ThemePreference.auto);
  }
}

class SettingsController extends Notifier<Settings> {
  @override
  Settings build() {
    return Settings.fromPrefs(ref.watch(sharedPreferencesProvider));
  }

  Future<void> setPreference(ThemePreference value) async {
    state = state.copyWith(preference: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kThemePrefKey, value.name);
    // Keep the legacy flag in sync so older builds still behave correctly.
    await prefs.setBool(kDarkModePrefKey, value == ThemePreference.dark);
  }

  Future<void> setDarkMode(bool value) async {
    await setPreference(value ? ThemePreference.dark : ThemePreference.light);
  }

  Future<void> toggleDarkMode() async {
    await setPreference(
      state.preference == ThemePreference.dark
          ? ThemePreference.light
          : ThemePreference.dark,
    );
  }

  /// Cycles Auto -> Light -> Dark -> Auto, used by the header toggle.
  Future<void> cycleTheme() async {
    const order = [
      ThemePreference.auto,
      ThemePreference.light,
      ThemePreference.dark,
    ];
    final index = order.indexOf(state.preference);
    await setPreference(order[(index + 1) % order.length]);
  }
}

final settingsControllerProvider =
    NotifierProvider<SettingsController, Settings>(SettingsController.new);

/// Emits the effective [ThemeMode] for the automatic (time based) preference,
/// re-evaluating every minute so day/night flips without a restart.
final autoThemeModeProvider = StreamProvider<ThemeMode>((ref) {
  ThemeMode current() => autoThemeMode(DateTime.now());
  return Stream<ThemeMode>.value(current())
      .asyncExpand(
        (_) => Stream.periodic(const Duration(minutes: 1), (_) => current()),
      )
      .distinct();
});
