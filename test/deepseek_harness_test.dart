import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_hub/common/agent_platforms.dart';
import 'package:mcp_hub/features/skill_sync/agent_resource_kind.dart';
import 'package:mcp_hub/features/skill_sync/convert/cursor_to_deepseek_converter.dart';
import 'package:mcp_hub/models/mcp_server_entry.dart';
import 'package:mcp_hub/models/mcp_transport.dart';
import 'package:mcp_hub/services/dsh_cordis_patch.dart';
import 'package:mcp_hub/services/mcp_paths.dart';
import 'package:path/path.dart' as p;

void main() {
  group('DeepSeek Harness platform', () {
    test('is registered for MCP writes and Cursor conversion', () {
      final platform = AgentPlatforms.deepSeekHarness;
      expect(
        AgentPlatforms.mcpConfigurable.map((e) => e.id),
        contains(platform.id),
      );
      expect(platform.mcpConfig?.format, AgentMcpConfigFormat.cordisPatchYaml);
      expect(platform.skillConversionFromCursor, isTrue);
      expect(p.basename(platform.mcpConfigDirectoryPath!), '.dsh');
      expect(p.basename(platform.mcpConfigFilePath!), 'cordis.patch.yml');
      expect(platform.mcpConfigFilePath, McpPaths.deepSeekMcpConfigPath);
      expect(
        platform.localResourcePath(AgentResourceKind.skill),
        McpPaths.deepSeekSkillsPath,
      );
      expect(
        platform.localResourcePath(AgentResourceKind.rule),
        McpPaths.deepSeekAgentsMdPath,
      );
      expect(platform.localResourcePath(AgentResourceKind.command), isNull);
      expect(platform.localResourcePath(AgentResourceKind.hook), isNull);
    });

    test('converts Skill and Rule only', () {
      for (final resource in AgentResourceKind.values) {
        final supported =
            resource == AgentResourceKind.skill ||
            resource == AgentResourceKind.rule;
        expect(
          resource.canConvertTo(AgentPlatformId.deepSeekHarness),
          supported,
          reason: '$resource',
        );
        expect(
          resource.supportsLocalPath(AgentPlatformId.deepSeekHarness),
          supported,
        );
      }
    });

    test('tryParse accepts harness aliases', () {
      expect(
        AgentPlatformDefinition.tryParse('deepSeekHarness'),
        AgentPlatformId.deepSeekHarness,
      );
      expect(
        AgentPlatformDefinition.tryParse('DeepSeek Harness'),
        AgentPlatformId.deepSeekHarness,
      );
      expect(
        AgentPlatformDefinition.tryParse('dsh'),
        AgentPlatformId.deepSeekHarness,
      );
      expect(AgentPlatformId.deepSeekHarness.label, 'DeepSeek Harness');
    });
  });

  group('CursorToDeepSeekConverter', () {
    late Directory temp;
    const converter = CursorToDeepSeekConverter();

    setUp(() => temp = Directory.systemTemp.createTempSync('dsh_conv_'));
    tearDown(() => temp.deleteSync(recursive: true));

    File file(String relative, [String content = 'x']) {
      final f = File(p.join(temp.path, relative));
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(content);
      return f;
    }

    test(
      'copies Skill packages and rewrites frontmatter DeepSeek would drop',
      () async {
        const valid =
            '---\nname: alpha\ndescription: Alpha skill\n---\n\n# Alpha\n';
        file('cursor/skills/alpha/SKILL.md', valid);
        file('cursor/skills/alpha/scripts/run.sh', 'echo');
        file('cursor/skills/My Skill/SKILL.md', '# Notes\n');
        file(
          'cursor/skills/legacy/SKILL.md',
          '---\nname: legacy\ndescription: Legacy\ndisableModelInvocation: true\nlicense: MIT\nmetadata:\n  tag: v1\n---\n\nBody\n',
        );
        file('cursor/skills/no-skill-md/readme.txt');
        file('cursor/skills/.hidden/SKILL.md');
        file('dsh/skills/alpha/SKILL.md', 'old');
        file('dsh/skills/alpha/stale.txt');
        file('dsh/skills/marketplace/SKILL.md', 'keep');

        final result = await converter.convertSkills(
          sourceDir: p.join(temp.path, 'cursor', 'skills'),
          targetDir: p.join(temp.path, 'dsh', 'skills'),
        );

        expect(result.packages, 3);
        expect(result.rewrittenSkills, 2);
        expect(
          File(
            p.join(temp.path, 'dsh/skills/alpha/SKILL.md'),
          ).readAsStringSync(),
          valid,
        );
        expect(
          File(
            p.join(temp.path, 'dsh/skills/alpha/scripts/run.sh'),
          ).existsSync(),
          isTrue,
        );
        expect(
          File(p.join(temp.path, 'dsh/skills/alpha/stale.txt')).existsSync(),
          isFalse,
        );
        final rewritten = File(
          p.join(temp.path, 'dsh/skills/My Skill/SKILL.md'),
        ).readAsStringSync();
        expect(rewritten, contains('name: my-skill'));
        expect(rewritten, contains('description: "Notes"'));
        final legacy = File(
          p.join(temp.path, 'dsh/skills/legacy/SKILL.md'),
        ).readAsStringSync();
        expect(legacy, contains('disable-model-invocation: true'));
        expect(legacy, contains('license: MIT'));
        expect(legacy, contains('metadata:\n  tag: v1'));
        expect(legacy, isNot(contains('disableModelInvocation')));
        expect(legacy, contains('Body'));
        expect(
          File(
            p.join(temp.path, 'dsh/skills/marketplace/SKILL.md'),
          ).readAsStringSync(),
          'keep',
        );
        expect(
          Directory(p.join(temp.path, 'dsh/skills/.hidden')).existsSync(),
          isFalse,
        );
      },
    );

    test('updates only the managed AGENTS.md section', () async {
      file(
        'cursor/rules/a.mdc',
        '---\nalwaysApply: true\n---\n\n# Always\n\nDo this.\n',
      );
      file('cursor/rules/nested/b.md', '# Sometimes\n\nMaybe.\n');
      file(
        'cursor/rules/conditional.mdc',
        '---\nalwaysApply: false\n---\n\n# Conditional\n\nHidden.\n',
      );
      file('cursor/rules/notes.txt', 'ignored');
      file('dsh/AGENTS.md', 'User preface.\n\nUser ending.\n');

      final count = await converter.convertRules(
        sourceDir: p.join(temp.path, 'cursor', 'rules'),
        agentsMdPath: p.join(temp.path, 'dsh', 'AGENTS.md'),
      );
      final text = File(
        p.join(temp.path, 'dsh', 'AGENTS.md'),
      ).readAsStringSync();

      expect(count, 2);
      expect(text, startsWith('User preface.'));
      expect(
        text.indexOf('User ending.'),
        lessThan(text.indexOf(CursorToDeepSeekConverter.rulesBegin)),
      );
      expect(text.indexOf('## Always'), lessThan(text.indexOf('## Sometimes')));
      expect(text, isNot(contains('## Always\n\n# Always')));
      expect(text, isNot(contains('Hidden.')));
      expect(text, contains('Do this.'));
      expect(text, isNot(contains('ignored')));

      file('cursor/rules/a.mdc', '---\n---\n\n# Always\n\nUpdated.\n');
      await converter.convertRules(
        sourceDir: p.join(temp.path, 'cursor', 'rules'),
        agentsMdPath: p.join(temp.path, 'dsh', 'AGENTS.md'),
      );
      final again = File(
        p.join(temp.path, 'dsh', 'AGENTS.md'),
      ).readAsStringSync();
      expect(again, startsWith('User preface.'));
      expect('## Always'.allMatches(again), hasLength(1));
      expect(again, contains('Updated.'));
      expect(again, isNot(contains('Do this.')));
    });
  });

  group('DshCordisPatch', () {
    McpServerEntry server({
      required String id,
      McpTransport transport = McpTransport.stdio,
      String? command,
      List<String> args = const [],
      Map<String, String> env = const {},
      String? cwd,
      String? url,
      bool enabled = true,
    }) {
      return McpServerEntry(
        id: id,
        name: id,
        transport: transport,
        command: command,
        args: args,
        env: env,
        cwd: cwd,
        url: url,
        enabled: enabled,
      );
    }

    test('merges MCP rows without touching other patches', () {
      const existing = '''
- insert:
    - id: theme
      name: "@deepseek-ai/dsh-theme"
      config:
        accent: "blue"
''';
      final stdio = server(
        id: 'file system',
        command: r'C:\tools\npx.cmd',
        args: ['-y', 'pkg "quoted"'],
        env: {'API_TOKEN': 'a:b'},
        cwd: r'C:\work',
      );
      final http = server(
        id: 'remote',
        transport: McpTransport.http,
        url: 'http://localhost:3000/mcp',
      );
      final disabled = server(id: 'old', command: 'gone', enabled: false);

      final once = DshCordisPatch.upsert(
        existing,
        servers: [stdio, http, disabled],
        managedIds: {'file system', 'remote', 'old'},
      );
      expect(once, contains('name: "@deepseek-ai/dsh-theme"'));
      expect(once, contains('# mcp-hub-server: file system'));
      expect(once, contains('serverName: "file_system"'));
      expect(once, contains(r'command: "C:\\tools\\npx.cmd"'));
      expect(once, contains('transport: "streamable-http"'));
      expect(once, isNot(contains('mcp-hub-server: old')));

      final parsed = DshCordisPatch.parseServers(once);
      expect(parsed.map((s) => s.id), ['file system', 'remote']);
      final fileServer = parsed.first;
      expect(fileServer.command, r'C:\tools\npx.cmd');
      expect(fileServer.args, ['-y', 'pkg "quoted"']);
      expect(fileServer.env['API_TOKEN'], 'a:b');
      expect(fileServer.cwd, r'C:\work');
      expect(parsed.last.transport, McpTransport.http);
      expect(parsed.last.url, 'http://localhost:3000/mcp');

      for (final entry in [stdio, http, disabled]) {
        expect(DshCordisPatch.diagnose(once, server: entry).isAligned, isTrue);
      }

      final twice = DshCordisPatch.upsert(
        once,
        servers: [http],
        managedIds: {'file system', 'remote', 'old'},
        removeIds: {'file system'},
      );
      expect(twice, contains('name: "@deepseek-ai/dsh-theme"'));
      expect('# mcp-hub:begin'.allMatches(twice), hasLength(1));
      expect(DshCordisPatch.parseServers(twice).map((s) => s.id), ['remote']);
      expect(DshCordisPatch.diagnose(twice, server: stdio).missing, isTrue);
    });

    test('refuses to write when the managed markers are incomplete', () {
      expect(
        () => DshCordisPatch.upsert(
          '# mcp-hub:begin\n- insert:\n',
          servers: [
            server(id: 'remote', transport: McpTransport.http, url: 'http://x'),
          ],
        ),
        throwsFormatException,
      );
    });
  });
}
