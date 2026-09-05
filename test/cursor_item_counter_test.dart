import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_hub/features/sync_status/cursor_item_counter.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('cursor_item_counter_');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('counts Cursor MCP keys including extras', () async {
    final jsonFile = File(p.join(temp.path, 'mcp.json'));
    await jsonFile.writeAsString(
      '{"mcpServers":{"hubMCP":{},"alpha":{},"":{},"beta":{"command":"x"}}}',
    );
    expect(await CursorItemCounter.countMcpServers(jsonFile.path), 3);
    expect(
      await CursorItemCounter.countMcpServers(
        p.join(temp.path, 'missing.json'),
      ),
      0,
    );
  });

  test('counts skill packages, non-dot files, and hook bundle files', () async {
    final skills = Directory(p.join(temp.path, 'skills'));
    await Directory(p.join(skills.path, 'good')).create(recursive: true);
    await File(p.join(skills.path, 'good', 'SKILL.md')).writeAsString('# s');
    await Directory(p.join(skills.path, 'empty')).create();
    await Directory(p.join(skills.path, '.hidden')).create();
    await File(p.join(skills.path, '.hidden', 'SKILL.md')).writeAsString('# h');

    final commands = Directory(p.join(temp.path, 'commands'));
    await commands.create();
    await File(p.join(commands.path, 'a.md')).writeAsString('a');
    await File(p.join(commands.path, '.skip')).writeAsString('x');
    await Directory(p.join(commands.path, 'nested')).create();
    await File(p.join(commands.path, 'nested', 'b.md')).writeAsString('b');

    final hooksJson = File(p.join(temp.path, 'hooks.json'));
    await hooksJson.writeAsString('{}');
    final hooksDir = Directory(p.join(temp.path, 'hooks'));
    await hooksDir.create();
    await File(p.join(hooksDir.path, 'run.sh')).writeAsString('echo');
    await File(p.join(hooksDir.path, '.secret')).writeAsString('x');

    final counts = await CursorItemCounter(
      mcpJsonPath: p.join(temp.path, 'missing.json'),
      skillsDir: skills.path,
      commandsDir: commands.path,
      rulesDir: p.join(temp.path, 'rules'),
      hooksJsonPath: hooksJson.path,
      hooksDir: hooksDir.path,
    ).load();

    expect(counts.mcp, 0);
    expect(counts.skills, 1);
    expect(counts.commands, 2);
    expect(counts.rules, 0);
    expect(counts.hooks, 2);
  });
}
