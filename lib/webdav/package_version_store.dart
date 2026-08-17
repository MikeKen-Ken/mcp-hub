import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 本机记录的各压缩包「当前版本」上传时间（下载或上传成功后写入）。
class PackageVersionStore {
  PackageVersionStore({Future<SharedPreferences> Function()? prefsLoader})
    : _prefsLoader = prefsLoader ?? SharedPreferences.getInstance;

  static const _key = 'mcp_hub_package_versions';
  static const catalogKey = 'catalog';

  final Future<SharedPreferences> Function() _prefsLoader;
  final Map<String, DateTime> _times = {};

  DateTime? get(String key) => _times[key];

  Map<String, DateTime> snapshot() => Map.unmodifiable(_times);

  Future<void> load() async {
    _times.clear();
    try {
      final prefs = await _prefsLoader();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      for (final entry in decoded.entries) {
        final parsed = DateTime.tryParse('${entry.value}');
        if (parsed == null) continue;
        _times[entry.key.toString()] = parsed;
      }
    } catch (_) {}
  }

  Future<void> save(String key, DateTime time) async {
    _times[key] = time.toUtc();
    try {
      final prefs = await _prefsLoader();
      await prefs.setString(
        _key,
        jsonEncode({
          for (final e in _times.entries)
            e.key: e.value.toUtc().toIso8601String(),
        }),
      );
    } catch (_) {}
  }
}
