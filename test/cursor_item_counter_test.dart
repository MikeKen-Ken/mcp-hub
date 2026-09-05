import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_hub/features/sync_status/cursor_item_counter.dart';
import 'package:mcp_hub/features/sync_status/widgets/cursor_count_refresh_scope.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('cursor_item_counter_');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('counts Cursor MCP keys including extras', () {
    final jsonFile = File(p.join(temp.path, 'mcp.json'));
    jsonFile.writeAsStringSync(
      '{"mcpServers":{"hubMCP":{},"alpha":{},"":{},"beta":{"command":"x"}}}',
    );
    expect(CursorItemCounter.countMcpServers(jsonFile.path), 3);
    expect(
      CursorItemCounter.countMcpServers(p.join(temp.path, 'missing.json')),
      0,
    );
  });

  test('counts skill packages, non-dot files, and hook bundle files', () {
    final skills = Directory(p.join(temp.path, 'skills'));
    Directory(p.join(skills.path, 'good')).createSync(recursive: true);
    File(p.join(skills.path, 'good', 'SKILL.md')).writeAsStringSync('# s');
    Directory(p.join(skills.path, 'empty')).createSync();
    Directory(p.join(skills.path, '.hidden')).createSync();
    File(p.join(skills.path, '.hidden', 'SKILL.md')).writeAsStringSync('# h');

    final commands = Directory(p.join(temp.path, 'commands'));
    commands.createSync();
    File(p.join(commands.path, 'a.md')).writeAsStringSync('a');
    File(p.join(commands.path, '.skip')).writeAsStringSync('x');
    Directory(p.join(commands.path, 'nested')).createSync();
    File(p.join(commands.path, 'nested', 'b.md')).writeAsStringSync('b');

    final hooksJson = File(p.join(temp.path, 'hooks.json'));
    hooksJson.writeAsStringSync('{}');
    final hooksDir = Directory(p.join(temp.path, 'hooks'));
    hooksDir.createSync();
    File(p.join(hooksDir.path, 'run.sh')).writeAsStringSync('echo');
    File(p.join(hooksDir.path, '.secret')).writeAsStringSync('x');

    final counts = CursorItemCounter(
      mcpJsonPath: p.join(temp.path, 'missing.json'),
      skillsDir: skills.path,
      commandsDir: commands.path,
      rulesDir: p.join(temp.path, 'rules'),
      hooksJsonPath: hooksJson.path,
      hooksDir: hooksDir.path,
    ).loadSync();

    expect(counts.mcp, 0);
    expect(counts.skills, 1);
    expect(counts.commands, 2);
    expect(counts.rules, 0);
    expect(counts.hooks, 2);
  });

  test('loadSync sees a skill package written after the first read', () {
    final skills = Directory(p.join(temp.path, 'skills'))..createSync();
    final counter = CursorItemCounter(skillsDir: skills.path);
    expect(counter.loadSync().skills, 0);

    Directory(p.join(skills.path, 'later')).createSync();
    File(p.join(skills.path, 'later', 'SKILL.md')).writeAsStringSync('# later');
    expect(counter.loadSync().skills, 1);
  });

  testWidgets('refresh scope reloads counts on first frame', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: CursorCountRefreshScope(
          refresh: () async {
            calls += 1;
          },
          child: const SizedBox(key: Key('child')),
        ),
      ),
    );
    await tester.pump();
    expect(calls, 1);
    expect(find.byKey(const Key('child')), findsOneWidget);
  });
}
