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

  static String get cursorHooksJsonPath =>
      p.join(_userProfile, '.cursor', 'hooks.json');

  static String get cursorHooksPath => p.join(_userProfile, '.cursor', 'hooks');

  static String get cursorRulesPath => p.join(_userProfile, '.cursor', 'rules');

  static String get codexRulesPath => p.join(_userProfile, '.codex', 'rules');

  /// Codex global agent instructions (written by Cursor `~/.cursor/rules` conversion).
  static String get codexAgentsMdPath =>
      p.join(_userProfile, '.codex', 'AGENTS.md');

  static String get codexHooksJsonPath =>
      p.join(_userProfile, '.codex', 'hooks.json');

  static String get codexHooksPath => p.join(_userProfile, '.codex', 'hooks');

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

  /// WorkBuddy 国内版配置目录（`~/.workbuddy`）。
  static String get workBuddyConfigDirectory =>
      p.join(_userProfile, '.workbuddy');

  /// WorkBuddy 国内版用户级 MCP 配置（`~/.workbuddy/mcp.json`）。
  static String get workBuddyMcpConfigPath =>
      p.join(workBuddyConfigDirectory, 'mcp.json');

  /// WorkBuddy AI 国际版配置目录（`~/.workbuddy-ai`，路径待本机核实）。
  static String get workBuddyAiConfigDirectory =>
      p.join(_userProfile, '.workbuddy-ai');

  /// WorkBuddy AI 国际版用户级 MCP 配置（`~/.workbuddy-ai/mcp.json`）。
  static String get workBuddyAiMcpConfigPath =>
      p.join(workBuddyAiConfigDirectory, 'mcp.json');

  /// WorkBuddy 用户级 Skill 目录（`~/.workbuddy/skills`）。
  static String get workBuddySkillsPath =>
      p.join(workBuddyConfigDirectory, 'skills');

  /// WorkBuddy 用户级 Rule 目录（`~/.workbuddy/rules`，递归加载 `.md` / `.mdc`）。
  static String get workBuddyRulesPath =>
      p.join(workBuddyConfigDirectory, 'rules');

  static String get workBuddyAiSkillsPath =>
      p.join(workBuddyAiConfigDirectory, 'skills');

  static String get workBuddyAiRulesPath =>
      p.join(workBuddyAiConfigDirectory, 'rules');

  /// DeepSeek Harness 配置根（`$DSH_HOME`，默认 `~/.dsh`）。
  static String get deepSeekConfigDirectory => p.join(_userProfile, '.dsh');

  /// 用户级 Cordis patch。Hub 只改写其中的 `mcp-hub` 标记段。
  static String get deepSeekMcpConfigPath =>
      p.join(deepSeekConfigDirectory, 'cordis.patch.yml');

  /// 用户级 Skill 根（rank 400，`~/.dsh/skills`）。
  static String get deepSeekSkillsPath =>
      p.join(deepSeekConfigDirectory, 'skills');

  /// 用户级全局说明。Harness 把它放进每个 Session 的基线。
  static String get deepSeekAgentsMdPath =>
      p.join(deepSeekConfigDirectory, 'AGENTS.md');

  /// Google Antigravity 用户目录（`~/.gemini`，IDE / CLI 共用）。
  static String get antigravityHomeDirectory => p.join(_userProfile, '.gemini');

  /// Google Antigravity 全局配置目录（`~/.gemini/config`）。
  static String get antigravityConfigDirectory =>
      p.join(antigravityHomeDirectory, 'config');

  /// Antigravity MCP 配置（`~/.gemini/config/mcp_config.json`）。
  static String get antigravityMcpConfigPath =>
      p.join(antigravityConfigDirectory, 'mcp_config.json');

  /// Antigravity 全局 Skill 目录（`~/.gemini/config/skills`，IDE / CLI / App 共用）。
  static String get antigravitySkillsPath =>
      p.join(antigravityConfigDirectory, 'skills');

  /// Antigravity 全局 Rule 文件（`~/.gemini/GEMINI.md`，单个文件）。
  static String get antigravityGeminiMdPath =>
      p.join(_userProfile, '.gemini', 'GEMINI.md');

  /// 豆包电脑版数据目录（Windows：`%LOCALAPPDATA%\Doubao\User Data\Default`）。
  static String get _doubaoUserDataDirectory {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    final base = (localAppData != null && localAppData.isNotEmpty)
        ? localAppData
        : p.join(_userProfile, 'AppData', 'Local');
    return p.join(base, 'Doubao', 'User Data', 'Default');
  }

  /// 豆包工作任务的本地工作区（`.doubao/agent_mode/workspace`）。
  static String get doubaoWorkspacePath =>
      p.join(_doubaoUserDataDirectory, '.doubao', 'agent_mode', 'workspace');

  /// 豆包本地技能目录（`.user_skills`）。豆包没有用户可写的本地 MCP 文件。
  static String get doubaoSkillsPath =>
      p.join(doubaoWorkspacePath, '.user_skills');

  static bool get isDesktopSupported =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;
}
