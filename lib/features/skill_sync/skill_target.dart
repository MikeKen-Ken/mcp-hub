/// Skill 下载/上传目标客户端。
enum SkillTarget {
  cursor,
  codex,
  openCode;

  String get wireName => name;

  String get label => switch (this) {
    SkillTarget.cursor => 'Cursor',
    SkillTarget.codex => 'Codex',
    SkillTarget.openCode => 'Open Code',
  };

  /// 当前可由 Cursor 转换的目标列表。新目标应先在这里登记，再接入具体格式转换器。
  static const conversionTargets = <SkillTarget>[
    SkillTarget.codex,
    SkillTarget.openCode,
  ];

  /// 只有仓库已确认目标格式时才允许真正写入。
  bool get hasConfirmedConversionFormat => this == SkillTarget.codex;

  String? get conversionBlockReason => hasConfirmedConversionFormat
      ? null
      : '仓库未确认 Open Code 的本地配置格式，当前仅提供入口，不会写入文件';

  static SkillTarget? tryParse(String? raw) {
    final value = raw?.trim().toLowerCase();
    return switch (value) {
      'cursor' => SkillTarget.cursor,
      'codex' => SkillTarget.codex,
      'open_code' || 'opencode' || 'open code' => SkillTarget.openCode,
      _ => null,
    };
  }
}
