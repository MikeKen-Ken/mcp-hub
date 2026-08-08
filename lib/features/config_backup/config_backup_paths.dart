import '../../features/skill_sync/agent_resource_kind.dart';
import '../../features/skill_sync/skill_target.dart';
import '../../services/mcp_paths.dart';

/// 备份包内相对路径约定，以及本机源/目标目录映射。
abstract final class ConfigBackupPaths {
  static const catalogFile = 'catalog.json';
  static const resourcesRoot = 'resources';

  /// zip 内：`resources/{skills|commands|rules}/cursor/`（权威源与 WebDAV 一致）。
  /// 旧包中可能仍有 `.../codex/`，导入时可选兼容恢复。
  static String resourceZipDir(AgentResourceKind resource, SkillTarget target) =>
      '$resourcesRoot/${resource.wireName}/${target.wireName}';

  /// zip 内：Codex `AGENTS.md`（Rule 一键转换产物）。
  static const codexAgentsMdZipPath = '$resourcesRoot/codex/AGENTS.md';

  static String? localDeployPath(
    AgentResourceKind resource,
    SkillTarget target,
  ) =>
      switch ((resource, target)) {
        (AgentResourceKind.skill, SkillTarget.cursor) =>
          McpPaths.cursorSkillsPath,
        (AgentResourceKind.skill, SkillTarget.codex) => McpPaths.codexSkillsPath,
        (AgentResourceKind.command, SkillTarget.cursor) =>
          McpPaths.cursorCommandsPath,
        (AgentResourceKind.command, SkillTarget.codex) =>
          McpPaths.codexCommandsPath,
        (AgentResourceKind.rule, SkillTarget.cursor) => McpPaths.cursorRulesPath,
        (AgentResourceKind.rule, SkillTarget.codex) => McpPaths.codexRulesPath,
      };

  static String? localCachePath(
    AgentResourceKind resource,
    SkillTarget target,
  ) =>
      McpPaths.resourceCachePath(resource.wireName, target.wireName);
}
