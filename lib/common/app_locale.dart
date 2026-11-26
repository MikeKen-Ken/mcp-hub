import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguage {
  zh,
  en;

  String get wireName => switch (this) {
    AppLanguage.zh => 'zh',
    AppLanguage.en => 'en',
  };

  String get label => switch (this) {
    AppLanguage.zh => '简体中文',
    AppLanguage.en => 'English',
  };

  static AppLanguage fromWire(String? value) {
    if (value == 'en') return AppLanguage.en;
    return AppLanguage.zh;
  }
}

/// 应用语言设置：默认使用简体中文，支持切换为英文并持久化。
abstract final class AppLocale {
  static const _prefsKey = 'mcp_hub_app_language';

  static final ValueNotifier<AppLanguage> notifier = ValueNotifier<AppLanguage>(
    AppLanguage.zh,
  );

  static AppLanguage get current => notifier.value;

  static bool get isZh => current == AppLanguage.zh;

  static Future<void> load({
    Future<SharedPreferences> Function()? prefsLoader,
  }) async {
    try {
      final prefs = await (prefsLoader ?? SharedPreferences.getInstance)();
      notifier.value = AppLanguage.fromWire(prefs.getString(_prefsKey));
    } catch (_) {
      notifier.value = AppLanguage.zh;
    }
  }

  static Future<void> setLanguage(
    AppLanguage language, {
    Future<SharedPreferences> Function()? prefsLoader,
  }) async {
    notifier.value = language;
    try {
      final prefs = await (prefsLoader ?? SharedPreferences.getInstance)();
      await prefs.setString(_prefsKey, language.wireName);
    } catch (_) {}
  }
}

/// 根据当前语言返回中文（默认）或英文文案。
String tr(String zh, String en) => AppLocale.isZh ? zh : en;
