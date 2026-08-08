import 'skill_target.dart';

/// 可通过 WebDAV 在设备间同步的 Agent 配置资源。
///
/// 远端权威源**仅 Cursor**（`{skills|commands|rules}/cursor`）。
/// Codex 由本机从 Cursor 转换生成，不作为 WebDAV 上下行目标。
enum AgentResourceKind {
  skill,
  command,
  rule;

  String get wireName => switch (this) {
        AgentResourceKind.skill => 'skills',
        AgentResourceKind.command => 'commands',
        AgentResourceKind.rule => 'rules',
      };

  String get label => switch (this) {
        AgentResourceKind.skill => 'Skill',
        AgentResourceKind.command => 'Command',
        AgentResourceKind.rule => 'Rule',
      };

  /// WebDAV 是否同步该客户端目录（仅 Cursor）。
  bool supportsWebDav(SkillTarget target) => target == SkillTarget.cursor;

  /// 该资源在 WebDAV 上同步的客户端列表（恒为 Cursor）。
  Iterable<SkillTarget> get webDavTargets => const [SkillTarget.cursor];

  /// 兼容旧名：等同 [webDavTargets]（远端不再含 Codex）。
  Iterable<SkillTarget> get supportedTargets => webDavTargets;

  /// 兼容旧名：等同 [supportsWebDav]。
  bool supports(SkillTarget target) => supportsWebDav(target);

  /// 本机是否展示该客户端路径（含 Codex 转换产物）。
  bool supportsLocalPath(SkillTarget target) => switch ((this, target)) {
        (_, SkillTarget.cursor) => true,
        (AgentResourceKind.command, SkillTarget.codex) => false,
        (_, SkillTarget.codex) => true,
      };

  /// 是否支持以本机 Cursor 为源一键转换到 Codex。
  bool get canConvertToCodex => switch (this) {
        AgentResourceKind.command => false,
        AgentResourceKind.skill || AgentResourceKind.rule => true,
      };
}
