import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'last_sync_attempt.dart';

/// Persists the last WebDAV attempt per package across app restarts.
class LastSyncAttemptStore {
  LastSyncAttemptStore({Future<SharedPreferences> Function()? prefsLoader})
    : _prefsLoader = prefsLoader ?? SharedPreferences.getInstance;

  static const _prefsKey = 'mcp_hub_last_sync_attempts';

  final Future<SharedPreferences> Function() _prefsLoader;
  final Map<String, LastSyncAttempt> _attempts = {};

  LastSyncAttempt? get(String key) => _attempts[key];

  Map<String, LastSyncAttempt> snapshot() => Map.unmodifiable(_attempts);

  LastSyncAttempt? latest() {
    LastSyncAttempt? best;
    for (final attempt in _attempts.values) {
      if (best == null || attempt.at.isAfter(best.at)) best = attempt;
    }
    return best;
  }

  Map<String, Object?> toStatusJson() {
    return {
      for (final key in LastSyncAttemptKeys.all) key: _attempts[key]?.toJson(),
    };
  }

  Future<void> load() async {
    _attempts.clear();
    try {
      final prefs = await _prefsLoader();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      for (final entry in decoded.entries) {
        final attempt = LastSyncAttempt.fromJson(
          entry.key.toString(),
          entry.value,
        );
        if (attempt != null) _attempts[attempt.packageKey] = attempt;
      }
    } catch (_) {}
  }

  Future<void> record(String key, {required bool ok, DateTime? at}) async {
    final attempt = LastSyncAttempt(
      packageKey: key,
      ok: ok,
      at: (at ?? DateTime.now()).toUtc(),
    );
    _attempts[key] = attempt;
    try {
      final prefs = await _prefsLoader();
      await prefs.setString(
        _prefsKey,
        jsonEncode({
          for (final e in _attempts.entries) e.key: e.value.toJson(),
        }),
      );
    } catch (_) {}
  }
}
