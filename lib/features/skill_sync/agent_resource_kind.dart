import 'skill_target.dart';

/// 可通过 WebDAV 在设备间同步的 Agent 配置资源。
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

  bool supports(SkillTarget target) => switch ((this, target)) {
        // Codex 没有与 Cursor ~/.cursor/commands 对等的全局 Command 目录。
        (AgentResourceKind.command, SkillTarget.codex) => false,
        _ => true,
      };
}
