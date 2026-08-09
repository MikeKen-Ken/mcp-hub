import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_hub/features/skill_sync/convert/cursor_to_opencode_converter.dart';
import 'package:path/path.dart' as p;

void main() {
  test('转换 OpenCode Skill、Rule、Command 且保留无关 JSONC', () async {
    final root = await Directory.systemTemp.createTemp('opencode_convert_');
    addTearDown(() => root.delete(recursive: true));
    final cursor = Directory(p.join(root.path, 'cursor'))..createSync();
    final skills = Directory(p.join(cursor.path, 'skills', 'demo'))
      ..createSync(recursive: true);
    await File(p.join(skills.path, 'SKILL.md')).writeAsString('# demo\n');
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
    expect(
      await File(p.join(target.path, 'AGENTS.md')).readAsString(),
      contains('Use it.'),
    );
    expect(
      await File(p.join(target.path, 'commands', 'ship.md')).exists(),
      isTrue,
    );
    expect(
      await File(p.join(target.path, 'opencode.jsonc')).readAsString(),
      contains('unrelated'),
    );
  });
}
