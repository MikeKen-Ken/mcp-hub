import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_locale.dart';

enum AppThemePreference {
  system,
  light,
  dark;

  String get wireName => name;

  ThemeMode get themeMode => switch (this) {
    AppThemePreference.system => ThemeMode.system,
    AppThemePreference.light => ThemeMode.light,
    AppThemePreference.dark => ThemeMode.dark,
  };

  String get label => switch (this) {
    AppThemePreference.system => tr('跟随系统', 'System'),
    AppThemePreference.light => tr('浅色', 'Light'),
    AppThemePreference.dark => tr('深色', 'Dark'),
  };

  IconData get icon => switch (this) {
    AppThemePreference.system => Icons.brightness_auto_outlined,
    AppThemePreference.light => Icons.light_mode_outlined,
    AppThemePreference.dark => Icons.dark_mode_outlined,
  };

  AppThemePreference next() => switch (this) {
    AppThemePreference.system => AppThemePreference.light,
    AppThemePreference.light => AppThemePreference.dark,
    AppThemePreference.dark => AppThemePreference.system,
  };

  static AppThemePreference fromWire(String? value) {
    return switch (value) {
      'light' => AppThemePreference.light,
      'dark' => AppThemePreference.dark,
      _ => AppThemePreference.system,
    };
  }
}

/// 应用主题模式设置：默认跟随系统，支持亮/暗切换并持久化。
abstract final class AppThemeMode {
  static const _prefsKey = 'mcp_hub_theme_mode';

  static final ValueNotifier<AppThemePreference> notifier =
      ValueNotifier<AppThemePreference>(AppThemePreference.system);

  static AppThemePreference get current => notifier.value;

  static Future<void> load({
    Future<SharedPreferences> Function()? prefsLoader,
  }) async {
    try {
      final prefs = await (prefsLoader ?? SharedPreferences.getInstance)();
      notifier.value = AppThemePreference.fromWire(prefs.getString(_prefsKey));
    } catch (_) {
      notifier.value = AppThemePreference.system;
    }
  }

  static Future<void> setPreference(
    AppThemePreference preference, {
    Future<SharedPreferences> Function()? prefsLoader,
  }) async {
    notifier.value = preference;
    try {
      final prefs = await (prefsLoader ?? SharedPreferences.getInstance)();
      await prefs.setString(_prefsKey, preference.wireName);
    } catch (_) {}
  }

  static Future<void> cycle({
    Future<SharedPreferences> Function()? prefsLoader,
  }) {
    return setPreference(current.next(), prefsLoader: prefsLoader);
  }
}
