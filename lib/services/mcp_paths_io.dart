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

  static String get cursorConfigDirectory => p.dirname(cursorMcpJsonPath);

  static String get codexConfigTomlPath =>
      p.join(_userProfile, '.codex', 'config.toml');

  static String get codexConfigDirectory => p.dirname(codexConfigTomlPath);

  /// Runtime checkouts live outside the packaged app install dir.
  static String get hubDataRoot => p.join(_userProfile, '.mcp-hub');

  static String get serversRoot => p.join(hubDataRoot, 'servers');

  static String get catalogPath => p.join(hubDataRoot, 'catalog.json');

  static String get syncBasePath => p.join(hubDataRoot, 'sync_base.json');

  /// WebDAV 拉取后的 Skill 本地缓存根目录。
  static String get skillsCacheRoot => p.join(hubDataRoot, 'skills');

  static String get cursorSkillsCachePath => p.join(skillsCacheRoot, 'cursor');

  static String get codexSkillsCachePath => p.join(skillsCacheRoot, 'codex');

  static String get agentResourcesCacheRoot =>
      p.join(hubDataRoot, 'agent-resources');

  static String resourceCachePath(String resource, String target) =>
      resource == 'skills'
      ? p.join(skillsCacheRoot, target)
      : p.join(agentResourcesCacheRoot, resource, target);

  /// Cursor 个人 Skill 目录（勿写入 skills-cursor，那是内置目录）。
  static String get cursorSkillsPath =>
      p.join(_userProfile, '.cursor', 'skills');

  /// Codex Skill 目录。
  static String get codexSkillsPath => p.join(_userProfile, '.codex', 'skills');

  static String get cursorCommandsPath =>
      p.join(_userProfile, '.cursor', 'commands');

  static String? get codexCommandsPath => null;

  static String get cursorRulesPath => p.join(_userProfile, '.cursor', 'rules');

  static String get codexRulesPath => p.join(_userProfile, '.codex', 'rules');

  /// Codex 全局 Agent 指引（由 Cursor `~/.cursor/rules` 一键转换写入）。
  static String get codexAgentsMdPath =>
      p.join(_userProfile, '.codex', 'AGENTS.md');

  /// OpenCode 全局配置目录（Windows：`%USERPROFILE%\\.config\\opencode`）。
  static String get openCodeConfigDirectory =>
      p.join(_userProfile, '.config', 'opencode');

  /// OpenCode MCP 配置（`~/.config/opencode/opencode.json`）。
  static String get openCodeMcpConfigPath =>
      p.join(openCodeConfigDirectory, 'opencode.json');

  static String get openCodeSkillsPath =>
      p.join(openCodeConfigDirectory, 'skills');

  static String get openCodeRulesPath =>
      p.join(openCodeConfigDirectory, 'AGENTS.md');

  static String get openCodeCommandsPath =>
      p.join(openCodeConfigDirectory, 'commands');

  static bool get isDesktopSupported =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;
}
