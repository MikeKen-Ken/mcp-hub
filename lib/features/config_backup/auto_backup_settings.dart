import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 自动配置备份设置。
class AutoBackupSettings {
  const AutoBackupSettings({
    this.enabled = true,
    this.directory,
    this.intervalMinutes = defaultIntervalMinutes,
  });

  static const defaultIntervalMinutes = 10;
  static const minIntervalMinutes = 1;
  static const retentionDays = 7;

  final bool enabled;
  final String? directory;
  final int intervalMinutes;

  AutoBackupSettings copyWith({
    bool? enabled,
    String? directory,
    bool clearDirectory = false,
    int? intervalMinutes,
  }) {
    return AutoBackupSettings(
      enabled: enabled ?? this.enabled,
      directory: clearDirectory ? null : (directory ?? this.directory),
      intervalMinutes: _normalizeInterval(
        intervalMinutes ?? this.intervalMinutes,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    if (directory != null) 'directory': directory,
    'intervalMinutes': intervalMinutes,
  };

  factory AutoBackupSettings.fromJson(Map<String, dynamic> json) {
    final rawDirectory = json['directory'] as String?;
    return AutoBackupSettings(
      enabled: json['enabled'] as bool? ?? true,
      directory: rawDirectory?.trim().isEmpty == true
          ? null
          : rawDirectory?.trim(),
      intervalMinutes: _normalizeInterval(
        json['intervalMinutes'] as int? ?? defaultIntervalMinutes,
      ),
    );
  }

  static int _normalizeInterval(int minutes) =>
      minutes < minIntervalMinutes ? minIntervalMinutes : minutes;
}

class AutoBackupSettingsStore {
  AutoBackupSettingsStore({Future<SharedPreferences> Function()? prefsLoader})
    : _prefsLoader = prefsLoader ?? SharedPreferences.getInstance;

  static const _key = 'mcp_hub_auto_backup_settings';

  final Future<SharedPreferences> Function() _prefsLoader;

  Future<AutoBackupSettings> load() async {
    final prefs = await _prefsLoader();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const AutoBackupSettings();
    try {
      return AutoBackupSettings.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return const AutoBackupSettings();
    }
  }

  Future<void> save(AutoBackupSettings settings) async {
    final prefs = await _prefsLoader();
    await prefs.setString(_key, jsonEncode(settings.toJson()));
  }
}
