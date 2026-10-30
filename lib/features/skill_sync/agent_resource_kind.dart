import 'skill_target.dart';

/// Folder resources that WebDAV can move between machines.
///
/// Remote source of truth is Cursor only, as `{skills|commands|rules|hooks}` packs.
/// Codex is produced on this machine from Cursor; it is not a WebDAV target.
enum AgentResourceKind {
  skill,
  command,
  rule,
  hook;

  String get wireName => switch (this) {
    AgentResourceKind.skill => 'skills',
    AgentResourceKind.command => 'commands',
    AgentResourceKind.rule => 'rules',
    AgentResourceKind.hook => 'hooks',
  };

  String get label => switch (this) {
    AgentResourceKind.skill => 'Skill',
    AgentResourceKind.command => 'Command',
    AgentResourceKind.rule => 'Rule',
    AgentResourceKind.hook => 'Hook',
  };

  /// WebDAV 是否下载/上传该客户端目录（仅 Cursor）。
  bool supportsWebDav(SkillTarget target) => target == SkillTarget.cursor;

  /// 该资源在 WebDAV 上下载/上传的客户端列表（恒为 Cursor）。
  Iterable<SkillTarget> get webDavTargets => const [SkillTarget.cursor];

  /// 兼容旧名：等同 [webDavTargets]（远端不再含 Codex）。
  Iterable<SkillTarget> get supportedTargets => webDavTargets;

  /// 兼容旧名：等同 [supportsWebDav]。
  bool supports(SkillTarget target) => supportsWebDav(target);

  /// 本机是否展示该客户端路径（含 Codex / OpenCode 转换产物）。
  bool supportsLocalPath(SkillTarget target) => switch ((this, target)) {
    (_, SkillTarget.workBuddy || SkillTarget.workBuddyAi) =>
      canConvertToWorkBuddy,
    (_, SkillTarget.cursor) => true,
    (_, SkillTarget.codex) => this != AgentResourceKind.command,
    (_, SkillTarget.openCode) => this != AgentResourceKind.hook,
  };

  /// 是否支持以本机 Cursor 为源一键转换到 Codex。
  bool get canConvertToCodex => switch (this) {
    AgentResourceKind.command => false,
    AgentResourceKind.skill ||
    AgentResourceKind.rule ||
    AgentResourceKind.hook => true,
  };

  /// 是否有已确认格式的 Cursor 转换器。
  bool canConvertTo(SkillTarget target) => switch (target) {
    SkillTarget.codex => canConvertToCodex,
    SkillTarget.openCode => this != AgentResourceKind.hook,
    SkillTarget.workBuddy || SkillTarget.workBuddyAi => canConvertToWorkBuddy,
    SkillTarget.cursor => false,
  };

  /// WorkBuddy 仅确认了 Skill（`skills/`）与 Rule（`rules/`）目录。
  bool get canConvertToWorkBuddy =>
      this == AgentResourceKind.skill || this == AgentResourceKind.rule;
}
