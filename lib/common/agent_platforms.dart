import '../features/skill_sync/agent_resource_kind.dart';
import '../services/mcp_paths.dart';
import 'agent_platform_id.dart';

export 'agent_platform_id.dart';

/// 客户端 MCP 配置文件格式。
enum AgentMcpConfigFormat { cursorJson, codexToml, openCodeJson }

/// 单个平台的元数据与能力标记。
class AgentPlatformDefinition {
  const AgentPlatformDefinition({
    required this.id,
    required this.label,
    required this.wireName,
    this.mcpConfig,
    this.skillConversionFromCursor = false,
    this.webDavAuthoritative = false,
  });

  final AgentPlatformId id;
  final String label;
  final String wireName;
  final AgentMcpConfigDefinition? mcpConfig;

  /// 是否支持从 Cursor 一键转换 Skill / Rule / Command。
  final bool skillConversionFromCursor;

  /// 是否作为 WebDAV 上下行的权威源（目前仅 Cursor）。
  final bool webDavAuthoritative;

  bool get supportsMcpConfigure => mcpConfig != null;

  String? get mcpConfigFilePath => mcpConfig?.configFilePath();

  String? get mcpConfigDirectoryPath => mcpConfig?.configDirectoryPath();

  /// 某类 Agent 资源在本机的部署目录；无对等目录时返回 `null`。
  String? localResourcePath(AgentResourceKind resource) =>
      AgentPlatforms.localResourcePath(resource, id);

  /// 某类 Agent 资源在 Hub 缓存中的目录。
  String? cacheResourcePath(AgentResourceKind resource) =>
      McpPaths.resourceCachePath(resource.wireName, wireName);

  static AgentPlatformId? tryParse(String? raw) {
    final value = raw?.trim().toLowerCase();
    if (value == null || value.isEmpty) return null;
    for (final platform in AgentPlatforms.all) {
      if (platform.wireName.toLowerCase() == value) {
        return platform.id;
      }
    }
    return switch (value) {
      'open_code' || 'open code' => AgentPlatformId.openCode,
      _ => null,
    };
  }
}

class AgentMcpConfigDefinition {
  const AgentMcpConfigDefinition({
    required this.format,
    required this.configFilePath,
    required this.configDirectoryPath,
  });

  final AgentMcpConfigFormat format;
  final String? Function() configFilePath;
  final String? Function() configDirectoryPath;
}

/// 平台注册表：新增平台时在此维护，UI / MCP 配置 / 转换 / 目录浏览统一读取。
abstract final class AgentPlatforms {
  static const cursor = AgentPlatformDefinition(
    id: AgentPlatformId.cursor,
    label: 'Cursor',
    wireName: 'cursor',
    mcpConfig: AgentMcpConfigDefinition(
      format: AgentMcpConfigFormat.cursorJson,
      configFilePath: _cursorMcpConfigPath,
      configDirectoryPath: _cursorConfigDirectory,
    ),
    webDavAuthoritative: true,
  );

  static const codex = AgentPlatformDefinition(
    id: AgentPlatformId.codex,
    label: 'Codex',
    wireName: 'codex',
    mcpConfig: AgentMcpConfigDefinition(
      format: AgentMcpConfigFormat.codexToml,
      configFilePath: _codexMcpConfigPath,
      configDirectoryPath: _codexConfigDirectory,
    ),
    skillConversionFromCursor: true,
  );

  static const openCode = AgentPlatformDefinition(
    id: AgentPlatformId.openCode,
    label: 'Open Code',
    wireName: 'openCode',
    mcpConfig: AgentMcpConfigDefinition(
      format: AgentMcpConfigFormat.openCodeJson,
      configFilePath: _openCodeMcpConfigPath,
      configDirectoryPath: _openCodeConfigDirectory,
    ),
    skillConversionFromCursor: true,
  );

  static const all = <AgentPlatformDefinition>[cursor, codex, openCode];

  /// 支持一键写入 MCP 配置的客户端。
  static List<AgentPlatformDefinition> get mcpConfigurable =>
      all.where((p) => p.supportsMcpConfigure).toList();

  /// 支持从 Cursor 转换的客户端。
  static List<AgentPlatformDefinition> get skillConversionTargets =>
      all.where((p) => p.skillConversionFromCursor).toList();

  static AgentPlatformDefinition of(AgentPlatformId id) => switch (id) {
    AgentPlatformId.cursor => cursor,
    AgentPlatformId.codex => codex,
    AgentPlatformId.openCode => openCode,
  };

  static String labelOf(AgentPlatformId id) => of(id).label;

  /// Skill 缓存根目录（skills 与 agent-resources 分流逻辑与 [McpPaths] 一致）。
  static String? skillCachePath(AgentPlatformId id) => switch (id) {
    AgentPlatformId.cursor => McpPaths.cursorSkillsCachePath,
    AgentPlatformId.codex => McpPaths.codexSkillsCachePath,
    AgentPlatformId.openCode => McpPaths.openCodeSkillsPath,
  };

  static String? localSkillPath(AgentPlatformId id) => switch (id) {
    AgentPlatformId.cursor => McpPaths.cursorSkillsPath,
    AgentPlatformId.codex => McpPaths.codexSkillsPath,
    AgentPlatformId.openCode => McpPaths.openCodeSkillsPath,
  };

  static String? localResourcePath(
    AgentResourceKind resource,
    AgentPlatformId id,
  ) => switch ((resource, id)) {
    (AgentResourceKind.skill, AgentPlatformId.cursor) =>
      McpPaths.cursorSkillsPath,
    (AgentResourceKind.skill, AgentPlatformId.codex) =>
      McpPaths.codexSkillsPath,
    (AgentResourceKind.skill, AgentPlatformId.openCode) =>
      McpPaths.openCodeSkillsPath,
    (AgentResourceKind.command, AgentPlatformId.cursor) =>
      McpPaths.cursorCommandsPath,
    (AgentResourceKind.command, AgentPlatformId.codex) =>
      McpPaths.codexCommandsPath,
    (AgentResourceKind.command, AgentPlatformId.openCode) =>
      McpPaths.openCodeCommandsPath,
    (AgentResourceKind.rule, AgentPlatformId.cursor) =>
      McpPaths.cursorRulesPath,
    (AgentResourceKind.rule, AgentPlatformId.codex) => McpPaths.codexRulesPath,
    (AgentResourceKind.rule, AgentPlatformId.openCode) =>
      McpPaths.openCodeConfigDirectory,
    (AgentResourceKind.hook, AgentPlatformId.cursor) =>
      McpPaths.cursorHooksPath,
    (AgentResourceKind.hook, AgentPlatformId.codex) => McpPaths.codexHooksPath,
    (AgentResourceKind.hook, AgentPlatformId.openCode) => null,
  };

  static String? _cursorMcpConfigPath() => McpPaths.cursorMcpJsonPath;

  static String? _cursorConfigDirectory() => McpPaths.cursorConfigDirectory;

  static String? _codexMcpConfigPath() => McpPaths.codexConfigTomlPath;

  static String? _codexConfigDirectory() => McpPaths.codexConfigDirectory;

  static String? _openCodeMcpConfigPath() => McpPaths.openCodeMcpConfigPath;

  static String? _openCodeConfigDirectory() => McpPaths.openCodeConfigDirectory;
}

extension AgentPlatformIdCompat on AgentPlatformId {
  String get wireName => AgentPlatforms.of(this).wireName;

  String get label => AgentPlatforms.of(this).label;

  bool get hasConfirmedConversionFormat =>
      AgentPlatforms.of(this).skillConversionFromCursor;

  String? get conversionBlockReason => hasConfirmedConversionFormat
      ? null
      : 'The local configuration format for this target is unconfirmed. This entry will not write any files';
}
