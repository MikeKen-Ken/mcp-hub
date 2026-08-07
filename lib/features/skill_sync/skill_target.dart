/// Skill 同步目标客户端。
enum SkillTarget {
  cursor,
  codex;

  String get wireName => name;

  String get label => switch (this) {
        SkillTarget.cursor => 'Cursor',
        SkillTarget.codex => 'Codex',
      };

  static SkillTarget? tryParse(String? raw) {
    final value = raw?.trim().toLowerCase();
    return switch (value) {
      'cursor' => SkillTarget.cursor,
      'codex' => SkillTarget.codex,
      _ => null,
    };
  }
}
