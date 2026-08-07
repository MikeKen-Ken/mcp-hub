import 'dart:io';

import 'package:path/path.dart' as p;

/// Cursor / Codex config paths and Hub data directories.
abstract final class McpPaths {
  static String get _userProfile {
    final fromEnv =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
    return Directory.current.path;
  }

  static String get cursorMcpJsonPath =>
      p.join(_userProfile, '.cursor', 'mcp.json');

  static String get codexConfigTomlPath =>
      p.join(_userProfile, '.codex', 'config.toml');

  /// Runtime checkouts live outside the packaged app install dir.
  static String get hubDataRoot =>
      p.join(_userProfile, '.mcp-hub');

  static String get serversRoot => p.join(hubDataRoot, 'servers');

  static String get catalogPath => p.join(hubDataRoot, 'catalog.json');

  static String get syncBasePath => p.join(hubDataRoot, 'sync_base.json');

  static bool get isDesktopSupported =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;
}
