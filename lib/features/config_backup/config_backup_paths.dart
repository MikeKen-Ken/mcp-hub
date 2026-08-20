import '../../common/agent_platforms.dart';
import '../../features/skill_sync/agent_resource_kind.dart';
import '../../features/skill_sync/skill_target.dart';
import '../../services/mcp_paths.dart';

/// 备份包内相对路径约定，以及本机源/目标目录映射。
abstract final class ConfigBackupPaths {
  static const catalogFile = 'catalog.json';
  static const resourcesRoot = 'resources';

  /// zip 内：`resources/{skills|commands|rules|hooks}/cursor/`（权威源与 WebDAV 一致）。
  /// 旧包中可能仍有 `.../codex/`，导入时可选兼容恢复。
  static String resourceZipDir(
    AgentResourceKind resource,
    SkillTarget target,
  ) => '$resourcesRoot/${resource.wireName}/${target.wireName}';

  /// zip 内：Codex `AGENTS.md`（Rule 一键转换产物）。
  static const codexAgentsMdZipPath = '$resourcesRoot/codex/AGENTS.md';

  static String? localDeployPath(
    AgentResourceKind resource,
    SkillTarget target,
  ) => AgentPlatforms.localResourcePath(resource, target);

  static String? localCachePath(
    AgentResourceKind resource,
    SkillTarget target,
  ) => AgentPlatforms.of(target).cacheResourcePath(resource);
}
