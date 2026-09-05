import '../skill_sync/agent_resource_kind.dart';

/// How many of each item Cursor currently has on this machine.
class CursorItemCounts {
  const CursorItemCounts({
    this.mcp = 0,
    this.skills = 0,
    this.commands = 0,
    this.rules = 0,
    this.hooks = 0,
  });

  final int mcp;
  final int skills;
  final int commands;
  final int rules;
  final int hooks;

  static const empty = CursorItemCounts();

  int forResource(AgentResourceKind resource) => switch (resource) {
    AgentResourceKind.skill => skills,
    AgentResourceKind.command => commands,
    AgentResourceKind.rule => rules,
    AgentResourceKind.hook => hooks,
  };
}
