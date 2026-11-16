import '../features/skill_sync/agent_resource_kind.dart';
import '../services/mcp_paths.dart';
import 'agent_platform_id.dart';

export 'agent_platform_id.dart';

/// 客户端 MCP 配置文件格式。
enum AgentMcpConfigFormat {
  cursorJson,
  codexToml,
  openCodeJson,
  cordisPatchYaml,

  /// Antigravity `mcp_config.json`：`mcpServers`，远程用 `serverUrl`，
  /// 禁用用 `disabled`（与 Cursor 的 `url` + 移除条目不同）。
  antigravityJson,
}

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
      'workbuddy_ai' || 'workbuddy ai' => AgentPlatformId.workBuddyAi,
      'deepseek' ||
      'deepseek harness' ||
      'deepseek-harness' ||
      'deepseek_harness' ||
      'dsh' => AgentPlatformId.deepSeekHarness,
      'antigravity' ||
      'antigravity ide' ||
      'antigravity cli' ||
      'agy' ||
      'google antigravity' => AgentPlatformId.antigravity,
      'doubao' ||
      'doubao work' ||
      'doubao-work' ||
      '豆包' => AgentPlatformId.doubao,
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

  static const workBuddy = AgentPlatformDefinition(
    id: AgentPlatformId.workBuddy,
    label: 'WorkBuddy',
    wireName: 'workBuddy',
    mcpConfig: AgentMcpConfigDefinition(
      format: AgentMcpConfigFormat.cursorJson,
      configFilePath: _workBuddyMcpConfigPath,
      configDirectoryPath: _workBuddyConfigDirectory,
    ),
    skillConversionFromCursor: true,
  );

  static const workBuddyAi = AgentPlatformDefinition(
    id: AgentPlatformId.workBuddyAi,
    label: 'WorkBuddy AI',
    wireName: 'workBuddyAi',
    mcpConfig: AgentMcpConfigDefinition(
      format: AgentMcpConfigFormat.cursorJson,
      configFilePath: _workBuddyAiMcpConfigPath,
      configDirectoryPath: _workBuddyAiConfigDirectory,
    ),
    skillConversionFromCursor: true,
  );

  static const deepSeekHarness = AgentPlatformDefinition(
    id: AgentPlatformId.deepSeekHarness,
    label: 'DeepSeek Harness',
    wireName: 'deepSeekHarness',
    mcpConfig: AgentMcpConfigDefinition(
      format: AgentMcpConfigFormat.cordisPatchYaml,
      configFilePath: _deepSeekMcpConfigPath,
      configDirectoryPath: _deepSeekConfigDirectory,
    ),
    skillConversionFromCursor: true,
  );

  /// 豆包电脑版：连接器（MCP）只在客户端界面里配置，没有用户可写的本地
  /// MCP 文件，因此只支持 Skill 转换。
  static const doubao = AgentPlatformDefinition(
    id: AgentPlatformId.doubao,
    label: 'Doubao',
    wireName: 'doubao',
    skillConversionFromCursor: true,
  );

  /// Google Antigravity：MCP、Skill、Rule 都有确认的本地位置。
  static const antigravity = AgentPlatformDefinition(
    id: AgentPlatformId.antigravity,
    label: 'Antigravity',
    wireName: 'antigravity',
    mcpConfig: AgentMcpConfigDefinition(
      format: AgentMcpConfigFormat.antigravityJson,
      configFilePath: _antigravityMcpConfigPath,
      configDirectoryPath: _antigravityConfigDirectory,
    ),
    skillConversionFromCursor: true,
  );

  static const all = <AgentPlatformDefinition>[
    cursor,
    codex,
    openCode,
    workBuddy,
    workBuddyAi,
    deepSeekHarness,
    antigravity,
    doubao,
  ];

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
    AgentPlatformId.workBuddy => workBuddy,
    AgentPlatformId.workBuddyAi => workBuddyAi,
    AgentPlatformId.deepSeekHarness => deepSeekHarness,
    AgentPlatformId.antigravity => antigravity,
    AgentPlatformId.doubao => doubao,
  };

  static String labelOf(AgentPlatformId id) => of(id).label;

  /// Skill 缓存根目录（skills 与 agent-resources 分流逻辑与 [McpPaths] 一致）。
  static String? skillCachePath(AgentPlatformId id) => switch (id) {
    AgentPlatformId.cursor => McpPaths.cursorSkillsCachePath,
    AgentPlatformId.codex => McpPaths.codexSkillsCachePath,
    AgentPlatformId.openCode => McpPaths.openCodeSkillsPath,
    AgentPlatformId.workBuddy ||
    AgentPlatformId.workBuddyAi ||
    AgentPlatformId.deepSeekHarness ||
    AgentPlatformId.antigravity ||
    AgentPlatformId.doubao => null,
  };

  static String? localSkillPath(AgentPlatformId id) => switch (id) {
    AgentPlatformId.cursor => McpPaths.cursorSkillsPath,
    AgentPlatformId.codex => McpPaths.codexSkillsPath,
    AgentPlatformId.openCode => McpPaths.openCodeSkillsPath,
    AgentPlatformId.workBuddy => McpPaths.workBuddySkillsPath,
    AgentPlatformId.workBuddyAi => McpPaths.workBuddyAiSkillsPath,
    AgentPlatformId.deepSeekHarness => McpPaths.deepSeekSkillsPath,
    AgentPlatformId.antigravity => McpPaths.antigravitySkillsPath,
    AgentPlatformId.doubao => McpPaths.doubaoSkillsPath,
  };

  static String? localResourcePath(
    AgentResourceKind resource,
    AgentPlatformId id,
  ) => switch ((resource, id)) {
    (AgentResourceKind.skill, AgentPlatformId.workBuddy) =>
      McpPaths.workBuddySkillsPath,
    (AgentResourceKind.skill, AgentPlatformId.workBuddyAi) =>
      McpPaths.workBuddyAiSkillsPath,
    (AgentResourceKind.rule, AgentPlatformId.workBuddy) =>
      McpPaths.workBuddyRulesPath,
    (AgentResourceKind.rule, AgentPlatformId.workBuddyAi) =>
      McpPaths.workBuddyAiRulesPath,
    // WorkBuddy 桌面版的 Command / Hook 位置尚未确认（CodeBuddy CLI 用
    // ~/.codebuddy/commands 与 settings.json），暂不写入。
    (
      AgentResourceKind.command || AgentResourceKind.hook,
      AgentPlatformId.workBuddy || AgentPlatformId.workBuddyAi,
    ) =>
      null,
    (AgentResourceKind.skill, AgentPlatformId.deepSeekHarness) =>
      McpPaths.deepSeekSkillsPath,
    (AgentResourceKind.rule, AgentPlatformId.deepSeekHarness) =>
      McpPaths.deepSeekAgentsMdPath,
    // DeepSeek Harness 没有已确认的用户级 Command 目录。Hook 要在
    // cordis 里显式挂 dsh-hooks 并指定 configPath，不会自动读取 hooks.json。
    (
      AgentResourceKind.command || AgentResourceKind.hook,
      AgentPlatformId.deepSeekHarness,
    ) =>
      null,
    (AgentResourceKind.skill, AgentPlatformId.antigravity) =>
      McpPaths.antigravitySkillsPath,
    // Antigravity 的全局 Rule 是单个 ~/.gemini/GEMINI.md。
    (AgentResourceKind.rule, AgentPlatformId.antigravity) =>
      McpPaths.antigravityGeminiMdPath,
    // Antigravity 没有已确认的全局 Command / Hook 文件位置。
    (
      AgentResourceKind.command || AgentResourceKind.hook,
      AgentPlatformId.antigravity,
    ) =>
      null,
    (AgentResourceKind.skill, AgentPlatformId.doubao) =>
      McpPaths.doubaoSkillsPath,
    // 豆包工作任务只读取本地技能；Rule / Command / Hook 无对等目录。
    (
      AgentResourceKind.rule ||
      AgentResourceKind.command ||
      AgentResourceKind.hook,
      AgentPlatformId.doubao,
    ) =>
      null,
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

  static String? _workBuddyMcpConfigPath() => McpPaths.workBuddyMcpConfigPath;

  static String? _workBuddyConfigDirectory() =>
      McpPaths.workBuddyConfigDirectory;

  static String? _workBuddyAiMcpConfigPath() =>
      McpPaths.workBuddyAiMcpConfigPath;

  static String? _workBuddyAiConfigDirectory() =>
      McpPaths.workBuddyAiConfigDirectory;

  static String? _deepSeekMcpConfigPath() => McpPaths.deepSeekMcpConfigPath;

  static String? _deepSeekConfigDirectory() => McpPaths.deepSeekConfigDirectory;

  static String? _antigravityMcpConfigPath() =>
      McpPaths.antigravityMcpConfigPath;

  static String? _antigravityConfigDirectory() =>
      McpPaths.antigravityConfigDirectory;
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
