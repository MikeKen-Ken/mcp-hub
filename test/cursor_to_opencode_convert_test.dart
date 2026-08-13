import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_hub/features/skill_sync/convert/cursor_to_opencode_converter.dart';
import 'package:mcp_hub/features/skill_sync/convert/opencode_skill_md.dart';
import 'package:mcp_hub/features/skill_sync/convert/skill_md_document.dart';
import 'package:path/path.dart' as p;

void main() {
  test('转换 OpenCode Skill、Rule、Command 且保留无关 JSONC', () async {
    final root = await Directory.systemTemp.createTemp('opencode_convert_');
    addTearDown(() => root.delete(recursive: true));
    final cursor = Directory(p.join(root.path, 'cursor'))..createSync();
    final skills = Directory(p.join(cursor.path, 'skills', 'demo'))
      ..createSync(recursive: true);
    await File(p.join(skills.path, 'SKILL.md')).writeAsString('''
---
name: demo
description: 演示技能，用于转换测试。
disable-model-invocation: true
---

# demo
''');
    await Directory(p.join(skills.path, 'scripts')).create();
    await File(p.join(skills.path, 'scripts', 'run.py')).writeAsString('print(1)\n');
    await Directory(p.join(skills.path, 'references')).create();
    await File(
      p.join(skills.path, 'references', 'format.md'),
    ).writeAsString('# fmt\n');
    final rules = Directory(p.join(cursor.path, 'rules'))..createSync();
    await File(
      p.join(rules.path, 'team.mdc'),
    ).writeAsString('---\nfoo: bar\n---\n# Team\n\nUse it.\n');
    final commands = Directory(p.join(cursor.path, 'commands'))..createSync();
    await File(p.join(commands.path, 'ship.md')).writeAsString('# Ship\n');
    final target = Directory(p.join(root.path, 'opencode'))..createSync();
    await File(
      p.join(target.path, 'opencode.jsonc'),
    ).writeAsString('{"unrelated":true}\n');
    await Directory(p.join(target.path, 'skills', 'stale')).create(recursive: true);
    await File(
      p.join(target.path, 'skills', 'stale', 'SKILL.md'),
    ).writeAsString('# stale\n');
    await Directory(p.join(target.path, 'commands')).create();
    await File(p.join(target.path, 'commands', 'old.md')).writeAsString('# old\n');

    final result = await const CursorToOpenCodeConverter().convertAll(
      cursorSkillsDir: p.join(cursor.path, 'skills'),
      cursorRulesDir: rules.path,
      cursorCommandsDir: commands.path,
      openCodeSkillsDir: p.join(target.path, 'skills'),
      openCodeAgentsMdPath: p.join(target.path, 'AGENTS.md'),
      openCodeCommandsDir: p.join(target.path, 'commands'),
    );

    expect(result.total, 3);
    expect(
      await File(p.join(target.path, 'skills', 'demo', 'SKILL.md')).exists(),
      isTrue,
    );
    final skillMd = await File(
      p.join(target.path, 'skills', 'demo', 'SKILL.md'),
    ).readAsString();
    expect(skillMd, contains('name: demo'));
    expect(skillMd, contains('opencode/autoinvoke: "false"'));
    expect(skillMd, isNot(contains('disable-model-invocation')));
    expect(
      await File(
        p.join(target.path, 'skills', 'demo', 'scripts', 'run.py'),
      ).exists(),
      isTrue,
    );
    expect(
      await File(
        p.join(target.path, 'skills', 'demo', 'references', 'format.md'),
      ).exists(),
      isTrue,
    );
    expect(
      await Directory(p.join(target.path, 'skills', 'stale')).exists(),
      isFalse,
    );
    expect(
      await File(p.join(target.path, 'AGENTS.md')).readAsString(),
      contains('Use it.'),
    );
    expect(
      await File(p.join(target.path, 'commands', 'ship.md')).exists(),
      isTrue,
    );
    expect(
      await File(p.join(target.path, 'commands', 'old.md')).exists(),
      isFalse,
    );
    expect(
      await File(p.join(target.path, 'opencode.jsonc')).readAsString(),
      contains('unrelated'),
    );
  });

  test('Rule 源为空时覆盖写出空 AGENTS.md', () async {
    final root = await Directory.systemTemp.createTemp('opencode_rules_');
    addTearDown(() => root.delete(recursive: true));
    final rules = Directory(p.join(root.path, 'rules'))..createSync();
    final agents = File(p.join(root.path, 'AGENTS.md'));
    await agents.writeAsString('# leftover\n');

    final count = await const CursorToOpenCodeConverter().convertRules(
      sourceDir: rules.path,
      targetPath: agents.path,
    );

    expect(count, 0);
    expect(await agents.readAsString(), isEmpty);
  });

  test('OpenCodeSkillMd 映射 disable-model-invocation', () {
    final converted = const OpenCodeSkillMd().convert(
      SkillMdDocument.parse('''
---
name: daily-report
description: 根据提交生成日报。用户要求生成日报时使用。
disable-model-invocation: true
---

# 生成工作日报
'''),
    );
    expect(converted, contains('name: daily-report'));
    expect(converted, contains('opencode/autoinvoke: "false"'));
    expect(converted, isNot(contains('disable-model-invocation')));
    expect(converted, contains('# 生成工作日报'));
  });
}
