/// Non-IO platforms: no user config paths.
abstract final class McpPaths {
  static String? get cursorMcpJsonPath => null;
  static String? get codexConfigTomlPath => null;
  static String? get hubDataRoot => null;
  static String? get serversRoot => null;
  static String? get catalogPath => null;
  static String? get syncBasePath => null;
  static bool get isDesktopSupported => false;
}
