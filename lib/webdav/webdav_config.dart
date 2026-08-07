import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// WebDAV connection (credentials stay on this machine only).
class WebDavConfig {
  static const minPollIntervalSeconds = 60;
  static const maxPollIntervalSeconds = 600;
  static const defaultPollIntervalSeconds = 300;
  static const minPushDebounceSeconds = 5;
  static const maxPushDebounceSeconds = 60;
  static const defaultPushDebounceSeconds = 15;
  static const defaultRemotePath = '/AgentHub';

  const WebDavConfig({
    required this.enabled,
    required this.serverUrl,
    required this.username,
    required this.password,
    required this.remotePath,
    required this.autoSync,
    required this.autoPull,
    required this.pollIntervalSeconds,
    required this.pushDebounceSeconds,
  });

  final bool enabled;
  final String serverUrl;
  final String username;
  final String password;
  final String remotePath;
  final bool autoSync;
  final bool autoPull;
  final int pollIntervalSeconds;
  final int pushDebounceSeconds;

  static int clampPollIntervalSeconds(int seconds) => seconds.clamp(
        minPollIntervalSeconds,
        maxPollIntervalSeconds,
      );

  static int clampPushDebounceSeconds(int seconds) => seconds.clamp(
        minPushDebounceSeconds,
        maxPushDebounceSeconds,
      );

  bool get isConfigured =>
      serverUrl.trim().isNotEmpty &&
      username.trim().isNotEmpty &&
      password.isNotEmpty;

  WebDavConfig copyWith({
    bool? enabled,
    String? serverUrl,
    String? username,
    String? password,
    String? remotePath,
    bool? autoSync,
    bool? autoPull,
    int? pollIntervalSeconds,
    int? pushDebounceSeconds,
  }) {
    return WebDavConfig(
      enabled: enabled ?? this.enabled,
      serverUrl: serverUrl ?? this.serverUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      remotePath: remotePath ?? this.remotePath,
      autoSync: autoSync ?? this.autoSync,
      autoPull: autoPull ?? this.autoPull,
      pollIntervalSeconds: clampPollIntervalSeconds(
        pollIntervalSeconds ?? this.pollIntervalSeconds,
      ),
      pushDebounceSeconds: clampPushDebounceSeconds(
        pushDebounceSeconds ?? this.pushDebounceSeconds,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'serverUrl': serverUrl,
        'username': username,
        'password': password,
        'remotePath': remotePath,
        'autoSync': autoSync,
        'autoPull': autoPull,
        'pollIntervalSeconds': pollIntervalSeconds,
        'pushDebounceSeconds': pushDebounceSeconds,
      };

  factory WebDavConfig.fromJson(Map<String, dynamic> json) {
    return WebDavConfig(
      enabled: json['enabled'] as bool? ?? false,
      serverUrl: json['serverUrl'] as String? ?? '',
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
      remotePath: json['remotePath'] as String? ?? defaultRemotePath,
      autoSync: json['autoSync'] as bool? ?? true,
      autoPull: json['autoPull'] as bool? ?? true,
      pollIntervalSeconds: clampPollIntervalSeconds(
        json['pollIntervalSeconds'] as int? ?? defaultPollIntervalSeconds,
      ),
      pushDebounceSeconds: clampPushDebounceSeconds(
        json['pushDebounceSeconds'] as int? ?? defaultPushDebounceSeconds,
      ),
    );
  }

  static const empty = WebDavConfig(
    enabled: false,
    serverUrl: '',
    username: '',
    password: '',
    remotePath: defaultRemotePath,
    autoSync: true,
    autoPull: true,
    pollIntervalSeconds: defaultPollIntervalSeconds,
    pushDebounceSeconds: defaultPushDebounceSeconds,
  );
}

class WebDavConfigStore {
  static const _key = 'mcp_hub_webdav_config';

  Future<WebDavConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return WebDavConfig.empty;
    return WebDavConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> save(WebDavConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(config.toJson()));
  }
}
