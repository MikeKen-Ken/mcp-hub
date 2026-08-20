import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_hub/features/skill_sync/convert/cursor_to_codex_hooks_converter.dart';
import 'package:mcp_hub/features/skill_sync/cursor_hooks_bundle.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('cursor_hooks_');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('导出/应用只动 hooks.json 与 hooks/，不碰其它配置', () async {
    final cursorDir = Directory(p.join(temp.path, 'cursor'))..createSync();
    await File(
      p.join(cursorDir.path, 'mcp.json'),
    ).writeAsString('{"keep":true}');
    await File(
      p.join(cursorDir.path, 'hooks.json'),
    ).writeAsString('{"version":1,"hooks":{}}');
    await Directory(p.join(cursorDir.path, 'hooks')).create();
    await File(
      p.join(cursorDir.path, 'hooks', 'gate.sh'),
    ).writeAsString('#!/bin/sh\n');
    await File(
      p.join(cursorDir.path, 'hooks', 'stale.sh'),
    ).writeAsString('old');

    final layout = CursorHooksLayout(configDirectory: cursorDir.path);
    const bundle = CursorHooksBundle();
    final pack = Directory(p.join(temp.path, 'pack'));
    await bundle.exportFromLayout(layout: layout, bundleDir: pack.path);

    expect(await File(p.join(pack.path, 'hooks.json')).exists(), isTrue);
    expect(await File(p.join(pack.path, 'hooks', 'gate.sh')).exists(), isTrue);

    await File(p.join(pack.path, 'hooks', 'stale.sh')).delete();
    await File(p.join(pack.path, 'hooks', 'gate.sh')).writeAsString('new');

    await bundle.applyToLayout(bundleDir: pack.path, layout: layout);
    expect(
      await File(p.join(cursorDir.path, 'mcp.json')).readAsString(),
      '{"keep":true}',
    );
    expect(
      await File(p.join(cursorDir.path, 'hooks', 'gate.sh')).readAsString(),
      'new',
    );
    expect(
      await File(p.join(cursorDir.path, 'hooks', 'stale.sh')).exists(),
      isFalse,
    );
  });

  test('Cursor hooks.json 转成 Codex 三层结构并改写脚本路径', () async {
    final cursorDir = Directory(p.join(temp.path, 'cursor'))..createSync();
    final codexDir = Directory(p.join(temp.path, 'codex'))..createSync();
    await Directory(p.join(cursorDir.path, 'hooks')).create();
    await File(
      p.join(cursorDir.path, 'hooks', 'approve.sh'),
    ).writeAsString('echo ok');
    await File(p.join(cursorDir.path, 'hooks.json')).writeAsString(
      jsonEncode({
        'version': 1,
        'hooks': {
          'beforeShellExecution': [
            {
              'command': './hooks/approve.sh',
              'matcher': 'curl|wget',
              'timeout': 12,
            },
          ],
          'beforeSubmitPrompt': [
            {'command': 'hooks/prompt.sh'},
          ],
          'afterAgentThought': [
            {'command': './hooks/thought.sh'},
          ],
        },
      }),
    );

    final toml = File(p.join(codexDir.path, 'config.toml'));
    await toml.writeAsString('[features]\nrmcp_client = true\n');

    final result = await const CursorToCodexHooksConverter().convertAll(
      cursor: CursorHooksLayout(configDirectory: cursorDir.path),
      codex: CursorHooksLayout(configDirectory: codexDir.path),
      codexConfigTomlPath: toml.path,
    );

    expect(result.convertedHooks, 2);
    expect(result.skippedEvents, ['afterAgentThought']);
    expect(result.enabledFeatureFlag, isTrue);
    expect(
      await File(p.join(codexDir.path, 'hooks', 'approve.sh')).exists(),
      isTrue,
    );

    final decoded =
        jsonDecode(
              await File(p.join(codexDir.path, 'hooks.json')).readAsString(),
            )
            as Map<String, dynamic>;
    final hooks = decoded['hooks'] as Map<String, dynamic>;
    final preTool = (hooks['PreToolUse'] as List).first as Map<String, dynamic>;
    expect(preTool['matcher'], 'Bash');
    final handler = (preTool['hooks'] as List).first as Map<String, dynamic>;
    expect(handler['command'], '~/.codex/hooks/approve.sh');
    expect(handler['commandWindows'], r'%USERPROFILE%\.codex\hooks\approve.sh');
    expect(handler['timeout'], 12);

    final submit = hooks['UserPromptSubmit'] as List;
    expect(submit, isNotEmpty);
    expect(await toml.readAsString(), contains('codex_hooks = true'));
  });

  test('relocateHookCommand 识别多种相对路径', () {
    final relocated = CursorToCodexHooksConverter.relocateHookCommand(
      'python3 ./hooks/check.py',
    );
    expect(relocated.unix, 'python3 ~/.codex/hooks/check.py');
    expect(relocated.windows, r'python3 %USERPROFILE%\.codex\hooks\check.py');
  });
}
