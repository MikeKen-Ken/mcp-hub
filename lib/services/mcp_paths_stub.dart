/// Non-IO platforms: no user config paths.
abstract final class McpPaths {
  static String? get cursorMcpJsonPath => null;
  static String? get cursorConfigDirectory => null;
  static String? get codexConfigTomlPath => null;
  static String? get codexConfigDirectory => null;
  static String? get hubDataRoot => null;
  static String? get serversRoot => null;
  static String? get catalogPath => null;
  static String? get syncBasePath => null;
  static String? get skillsCacheRoot => null;
  static String? get cursorSkillsCachePath => null;
  static String? get codexSkillsCachePath => null;
  static String? get agentResourcesCacheRoot => null;
  static String? resourceCachePath(String resource, String target) => null;
  static String? get cursorSkillsPath => null;
  static String? get codexSkillsPath => null;
  static String? get cursorCommandsPath => null;
  static String? get codexCommandsPath => null;
  static String? get cursorRulesPath => null;
  static String? get codexRulesPath => null;
  static String? get codexAgentsMdPath => null;
  static bool get isDesktopSupported => false;
}
