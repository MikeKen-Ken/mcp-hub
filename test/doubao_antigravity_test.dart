import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_hub/common/agent_platforms.dart';
import 'package:mcp_hub/features/skill_sync/agent_resource_kind.dart';
import 'package:mcp_hub/features/skill_sync/convert/cursor_to_antigravity_converter.dart';
import 'package:mcp_hub/features/skill_sync/convert/cursor_to_doubao_converter.dart';
import 'package:mcp_hub/models/mcp_server_entry.dart';
import 'package:mcp_hub/models/mcp_transport.dart';
import 'package:mcp_hub/services/mcp_client_config.dart';
import 'package:mcp_hub/services/mcp_client_config_reader.dart';
import 'package:mcp_hub/services/mcp_paths.dart';
import 'package:path/path.dart' as p;

void main() {
  group('Doubao platform', () {
    test('registers Skill conversion but no MCP config file', () {
      final platform = AgentPlatforms.doubao;
      expect(
        AgentPlatforms.mcpConfigurable.map((e) => e.id),
        isNot(contains(platform.id)),
      );
      expect(platform.mcpConfig, isNull);
      expect(platform.skillConversionFromCursor, isTrue);
      expect(AgentPlatformId.doubao.label, 'Doubao');
      expect(
        platform.localResourcePath(AgentResourceKind.skill),
        McpPaths.doubaoSkillsPath,
      );
      expect(p.basename(McpPaths.doubaoSkillsPath!), '.user_skills');
      expect(platform.localResourcePath(AgentResourceKind.rule), isNull);
      expect(platform.localResourcePath(AgentResourceKind.command), isNull);
      expect(platform.localResourcePath(AgentResourceKind.hook), isNull);
    });

    test('converts Skill only', () {
      for (final resource in AgentResourceKind.values) {
        final supported = resource == AgentResourceKind.skill;
        expect(resource.canConvertTo(AgentPlatformId.doubao), supported);
        expect(resource.supportsLocalPath(AgentPlatformId.doubao), supported);
      }
      expect(AgentResourceKind.skill.canConvertToDoubao, isTrue);
      expect(AgentResourceKind.rule.canConvertToDoubao, isFalse);
    });

    test('tryParse accepts Doubao aliases', () {
      expect(
        AgentPlatformDefinition.tryParse('doubao'),
        AgentPlatformId.doubao,
      );
      expect(AgentPlatformDefinition.tryParse('豆包'), AgentPlatformId.doubao);
      expect(
        AgentPlatformDefinition.tryParse('Doubao Work'),
        AgentPlatformId.doubao,
      );
    });
  });

  group('Antigravity platform', () {
    test('registers MCP, Skill and Rule locations', () {
      final platform = AgentPlatforms.antigravity;
      expect(
        AgentPlatforms.mcpConfigurable.map((e) => e.id),
        contains(platform.id),
      );
      expect(platform.mcpConfig?.format, AgentMcpConfigFormat.antigravityJson);
      expect(platform.skillConversionFromCursor, isTrue);
      expect(AgentPlatformId.antigravity.label, 'Antigravity');
      expect(platform.mcpConfigFilePath, McpPaths.antigravityMcpConfigPath);
      expect(
        platform.mcpConfigDirectoryPath,
        McpPaths.antigravityConfigDirectory,
      );
      expect(
        platform.localResourcePath(AgentResourceKind.skill),
        McpPaths.antigravitySkillsPath,
      );
      expect(
        platform.localResourcePath(AgentResourceKind.rule),
        McpPaths.antigravityGeminiMdPath,
      );
      expect(platform.localResourcePath(AgentResourceKind.command), isNull);
      expect(platform.localResourcePath(AgentResourceKind.hook), isNull);
    });

    test('converts Skill and Rule only', () {
      for (final resource in AgentResourceKind.values) {
        final supported =
            resource == AgentResourceKind.skill ||
            resource == AgentResourceKind.rule;
        expect(resource.canConvertTo(AgentPlatformId.antigravity), supported);
        expect(
          resource.supportsLocalPath(AgentPlatformId.antigravity),
          supported,
        );
      }
    });

    test('tryParse accepts Antigravity aliases', () {
      expect(
        AgentPlatformDefinition.tryParse('antigravity'),
        AgentPlatformId.antigravity,
      );
      expect(
        AgentPlatformDefinition.tryParse('Google Antigravity'),
        AgentPlatformId.antigravity,
      );
      expect(
        AgentPlatformDefinition.tryParse('agy'),
        AgentPlatformId.antigravity,
      );
    });
  });

  group('CursorToDoubaoConverter', () {
    late Directory temp;
    const converter = CursorToDoubaoConverter();

    setUp(() => temp = Directory.systemTemp.createTempSync('doubao_conv_'));
    tearDown(() => temp.deleteSync(recursive: true));

    File file(String relative, [String content = 'x']) {
      final f = File(p.join(temp.path, relative));
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(content);
      return f;
    }

    test('copies packages, keeps extra Skills and fixes frontmatter', () async {
      const valid =
          '---\nname: alpha\ndescription: Alpha skill\n---\n\n# Alpha\n';
      file('cursor/skills/alpha/SKILL.md', valid);
      file('cursor/skills/alpha/scripts/run.sh', 'echo');
      file('cursor/skills/My Skill/SKILL.md', '# Notes\n');
      file('cursor/skills/no-skill-md/readme.txt');
      file('cursor/skills/.hidden/SKILL.md');
      file('doubao/skills/alpha/SKILL.md', 'old');
      file('doubao/skills/alpha/stale.txt');
      file('doubao/skills/from-market/SKILL.md', 'keep');

      final result = await converter.convertSkills(
        sourceDir: p.join(temp.path, 'cursor', 'skills'),
        targetDir: p.join(temp.path, 'doubao', 'skills'),
      );

      expect(result.packages, 2);
      expect(result.rewrittenSkills, 1);
      expect(
        File(
          p.join(temp.path, 'doubao/skills/alpha/SKILL.md'),
        ).readAsStringSync(),
        valid,
      );
      expect(
        File(
          p.join(temp.path, 'doubao/skills/alpha/scripts/run.sh'),
        ).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(temp.path, 'doubao/skills/alpha/stale.txt')).existsSync(),
        isFalse,
      );
      final rewritten = File(
        p.join(temp.path, 'doubao/skills/my-skill/SKILL.md'),
      ).readAsStringSync();
      expect(rewritten, contains('name: my-skill'));
      expect(rewritten, contains('description: "Notes"'));
      expect(
        File(
          p.join(temp.path, 'doubao/skills/from-market/SKILL.md'),
        ).readAsStringSync(),
        'keep',
      );
      expect(
        Directory(p.join(temp.path, 'doubao/skills/no-skill-md')).existsSync(),
        isFalse,
      );
      expect(
        Directory(p.join(temp.path, 'doubao/skills/.hidden')).existsSync(),
        isFalse,
      );
    });
  });

  group('CursorToAntigravityConverter', () {
    late Directory temp;
    const converter = CursorToAntigravityConverter();

    setUp(
      () => temp = Directory.systemTemp.createTempSync('antigravity_conv_'),
    );
    tearDown(() => temp.deleteSync(recursive: true));

    File file(String relative, [String content = 'x']) {
      final f = File(p.join(temp.path, relative));
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(content);
      return f;
    }

    test('copies Skills and normalizes kebab-case frontmatter', () async {
      file(
        'cursor/skills/alpha/SKILL.md',
        '---\ndescription: Alpha\n---\n\n# Alpha\n',
      );
      file('cursor/skills/Code Review/SKILL.md', '# Review\n\nCheck diffs.\n');
      file('antigravity/skills/from-market/SKILL.md', 'keep');
      file('antigravity/skills/alpha/old.txt', 'stale');

      final result = await converter.convertSkills(
        sourceDir: p.join(temp.path, 'cursor', 'skills'),
        targetDir: p.join(temp.path, 'antigravity', 'skills'),
      );

      expect(result.packages, 2);
      final alpha = File(
        p.join(temp.path, 'antigravity/skills/alpha/SKILL.md'),
      ).readAsStringSync();
      expect(alpha, contains('name: alpha'));
      expect(alpha, contains('description: "Alpha"'));
      final review = File(
        p.join(temp.path, 'antigravity/skills/code-review/SKILL.md'),
      ).readAsStringSync();
      expect(review, contains('name: code-review'));
      expect(review, contains('description: "Review"'));
      expect(
        File(
          p.join(temp.path, 'antigravity/skills/from-market/SKILL.md'),
        ).readAsStringSync(),
        'keep',
      );
      expect(
        File(
          p.join(temp.path, 'antigravity/skills/alpha/old.txt'),
        ).existsSync(),
        isFalse,
      );
    });

    test('writes only the managed GEMINI.md section', () async {
      file(
        'cursor/rules/a.mdc',
        '---\ndescription: Always apply\n---\n\n# Always\n\nDo this.\n',
      );
      file('cursor/rules/nested/b.md', '# Sometimes\n\nMaybe.\n');
      file('cursor/rules/notes.txt', 'ignored');
      file('gemini/GEMINI.md', 'User preface.\n\nUser ending.\n');

      final count = await converter.convertRules(
        sourceDir: p.join(temp.path, 'cursor', 'rules'),
        geminiMdPath: p.join(temp.path, 'gemini', 'GEMINI.md'),
      );
      final text = File(
        p.join(temp.path, 'gemini', 'GEMINI.md'),
      ).readAsStringSync();

      expect(count, 2);
      expect(text, startsWith('User preface.'));
      expect(
        text.indexOf('User ending.'),
        lessThan(text.indexOf(CursorToAntigravityConverter.rulesBegin)),
      );
      expect(text.indexOf('## Always'), lessThan(text.indexOf('## Sometimes')));
      expect(text, contains('Do this.'));
      expect(text, isNot(contains('ignored')));

      file('cursor/rules/a.mdc', '---\n---\n\n# Always\n\nUpdated.\n');
      await converter.convertRules(
        sourceDir: p.join(temp.path, 'cursor', 'rules'),
        geminiMdPath: p.join(temp.path, 'gemini', 'GEMINI.md'),
      );
      final again = File(
        p.join(temp.path, 'gemini', 'GEMINI.md'),
      ).readAsStringSync();
      expect(again, startsWith('User preface.'));
      expect('## Always'.allMatches(again), hasLength(1));
      expect(again, contains('Updated.'));
      expect(again, isNot(contains('Do this.')));
    });

    test('refuses to write when markers are incomplete', () async {
      await expectLater(
        converter.convertRules(
          sourceDir: p.join(temp.path, 'missing'),
          geminiMdPath: p.join(temp.path, 'gemini', 'GEMINI.md'),
        ),
        completion(0),
      );
      final broken = file(
        'gemini/GEMINI.md',
        '${CursorToAntigravityConverter.rulesBegin}\nUser text\n',
      );
      await expectLater(
        converter.convertRules(
          sourceDir: p.join(temp.path, 'missing'),
          geminiMdPath: broken.path,
        ),
        throwsFormatException,
      );
    });
  });

  group('Antigravity MCP config', () {
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

    test('writes serverUrl / disabled and keeps unrelated entries', () {
      final stdio = server(
        id: 'filesystem',
        command: 'npx',
        args: ['-y', 'pkg'],
        env: {'FOO': 'bar'},
        cwd: r'C:\work',
        enabled: false,
      );
      final http = server(
        id: 'remote',
        transport: McpTransport.http,
        url: 'http://127.0.0.1:18765/mcp',
      );
      const existing = '''
{
  "mcpServers": {
    "other": { "command": "keep-me" },
    "remote": { "url": "http://legacy" }
  }
}
''';

      final text = McpClientConfig.upsertAntigravityJson(
        existing,
        servers: [stdio, http],
        managedIds: {'filesystem', 'remote'},
      );
      final root = jsonDecode(text) as Map<String, dynamic>;
      final servers = root['mcpServers'] as Map<String, dynamic>;

      expect(servers['other']['command'], 'keep-me');
      final stdioEntry = servers['filesystem'] as Map<String, dynamic>;
      expect(stdioEntry['command'], 'npx');
      expect(stdioEntry['args'], ['-y', 'pkg']);
      expect(stdioEntry['env'], {'FOO': 'bar'});
      expect(stdioEntry['cwd'], r'C:\work');
      expect(stdioEntry['disabled'], isTrue);
      final httpEntry = servers['remote'] as Map<String, dynamic>;
      expect(httpEntry['serverUrl'], 'http://127.0.0.1:18765/mcp');
      expect(httpEntry.containsKey('url'), isFalse);
      expect(httpEntry.containsKey('type'), isFalse);
      expect(httpEntry.containsKey('disabled'), isFalse);

      expect(
        McpClientConfig.diagnoseAntigravityServer(
          text,
          server: stdio,
        ).isAligned,
        isTrue,
      );
      expect(
        McpClientConfig.diagnoseAntigravityServer(text, server: http).isAligned,
        isTrue,
      );

      final parsed = McpClientConfigReader.parseAntigravityServers(text);
      final parsedById = {for (final s in parsed) s.id: s};
      expect(parsedById['filesystem']!.enabled, isFalse);
      expect(parsedById['remote']!.url, 'http://127.0.0.1:18765/mcp');
    });

    test('removeIds drops managed entries only', () {
      final text = McpClientConfig.upsertAntigravityJson(
        '{"mcpServers":{"a":{"command":"x"},"b":{"command":"y"}}}',
        servers: const [],
        managedIds: {'a'},
        removeIds: {'a'},
      );
      final root = jsonDecode(text) as Map<String, dynamic>;
      expect((root['mcpServers'] as Map<String, dynamic>).keys, ['b']);
    });
  });
}
