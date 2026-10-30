import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_hub/common/agent_platforms.dart';
import 'package:mcp_hub/features/skill_sync/agent_resource_kind.dart';
import 'package:mcp_hub/features/skill_sync/convert/cursor_to_workbuddy_converter.dart';
import 'package:mcp_hub/services/mcp_paths.dart';
import 'package:path/path.dart' as p;

const _clients = [AgentPlatformId.workBuddy, AgentPlatformId.workBuddyAi];

void main() {
  group('WorkBuddy platforms', () {
    test('are registered as MCP-configurable with the Cursor JSON format', () {
      final ids = AgentPlatforms.mcpConfigurable.map((e) => e.id);
      for (final id in _clients) {
        expect(ids, contains(id));
        expect(
          AgentPlatforms.of(id).mcpConfig?.format,
          AgentMcpConfigFormat.cursorJson,
        );
      }
    });

    test('use separate user-level directories', () {
      final cn = AgentPlatforms.workBuddy.mcpConfigFilePath!;
      final intl = AgentPlatforms.workBuddyAi.mcpConfigFilePath!;
      expect(p.basename(p.dirname(cn)), '.workbuddy');
      expect(p.basename(p.dirname(intl)), '.workbuddy-ai');
      expect(p.basename(cn), 'mcp.json');
      expect(p.basename(intl), 'mcp.json');
      expect(cn, McpPaths.workBuddyMcpConfigPath);
      expect(intl, McpPaths.workBuddyAiMcpConfigPath);
      expect(
        AgentPlatforms.workBuddy.localResourcePath(AgentResourceKind.skill),
        McpPaths.workBuddySkillsPath,
      );
      expect(
        AgentPlatforms.workBuddyAi.localResourcePath(AgentResourceKind.rule),
        McpPaths.workBuddyAiRulesPath,
      );
    });

    test('support Skill and Rule only; Command and Hook are not written', () {
      for (final id in _clients) {
        for (final resource in AgentResourceKind.values) {
          final supported =
              resource == AgentResourceKind.skill ||
              resource == AgentResourceKind.rule;
          expect(resource.canConvertTo(id), supported, reason: '$resource');
          expect(resource.supportsLocalPath(id), supported);
          expect(
            AgentPlatforms.localResourcePath(resource, id),
            supported ? isNotNull : isNull,
          );
        }
        expect(AgentPlatforms.of(id).skillConversionFromCursor, isTrue);
      }
    });

    test('tryParse resolves wire names', () {
      expect(
        AgentPlatformDefinition.tryParse('workBuddy'),
        AgentPlatformId.workBuddy,
      );
      expect(
        AgentPlatformDefinition.tryParse('workBuddyAi'),
        AgentPlatformId.workBuddyAi,
      );
      expect(
        AgentPlatformDefinition.tryParse('WorkBuddy AI'),
        AgentPlatformId.workBuddyAi,
      );
    });

    test('labels distinguish the two editions', () {
      expect(AgentPlatformId.workBuddy.label, 'WorkBuddy');
      expect(AgentPlatformId.workBuddyAi.label, 'WorkBuddy AI');
    });
  });

  group('CursorToWorkBuddyConverter', () {
    late Directory temp;
    const converter = CursorToWorkBuddyConverter();

    setUp(() => temp = Directory.systemTemp.createTempSync('workbuddy_conv_'));
    tearDown(() => temp.deleteSync(recursive: true));

    File file(String relative, [String content = 'x']) {
      final f = File(p.join(temp.path, relative));
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(content);
      return f;
    }

    test('copies Skill packages and keeps Skills that are not in Cursor', () async {
      file('cursor/skills/alpha/SKILL.md', 'alpha-new');
      file('cursor/skills/alpha/scripts/run.sh', 'echo');
      file('cursor/skills/no-skill-md/readme.txt');
      file('cursor/skills/.hidden/SKILL.md');
      file('wb/skills/alpha/SKILL.md', 'alpha-old');
      file('wb/skills/alpha/stale.txt');
      file('wb/skills/marketplace-skill/SKILL.md', 'keep');

      final result = await converter.convertSkills(
        sourceDir: p.join(temp.path, 'cursor', 'skills'),
        targetDir: p.join(temp.path, 'wb', 'skills'),
      );

      expect(result.packages, 1);
      expect(
        File(p.join(temp.path, 'wb/skills/alpha/SKILL.md')).readAsStringSync(),
        'alpha-new',
      );
      expect(
        File(p.join(temp.path, 'wb/skills/alpha/scripts/run.sh')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(temp.path, 'wb/skills/alpha/stale.txt')).existsSync(),
        isFalse,
      );
      expect(
        File(
          p.join(temp.path, 'wb/skills/marketplace-skill/SKILL.md'),
        ).existsSync(),
        isTrue,
      );
      expect(
        Directory(p.join(temp.path, 'wb/skills/no-skill-md')).existsSync(),
        isFalse,
      );
      expect(
        Directory(p.join(temp.path, 'wb/skills/.hidden')).existsSync(),
        isFalse,
      );
    });

    test('mirrors Rules into cursor-sync only', () async {
      file('cursor/rules/a.mdc', 'A');
      file('cursor/rules/nested/b.md', 'B');
      file('cursor/rules/notes.txt', 'ignored');
      file('wb/rules/mine.md', 'user rule');
      file('wb/rules/cursor-sync/old.mdc', 'stale');

      final count = await converter.convertRules(
        sourceDir: p.join(temp.path, 'cursor', 'rules'),
        rulesDir: p.join(temp.path, 'wb', 'rules'),
      );

      final managed = p.join(temp.path, 'wb', 'rules', 'cursor-sync');
      expect(count, 2);
      expect(File(p.join(managed, 'a.mdc')).readAsStringSync(), 'A');
      expect(File(p.join(managed, 'nested', 'b.md')).readAsStringSync(), 'B');
      expect(File(p.join(managed, 'notes.txt')).existsSync(), isFalse);
      expect(File(p.join(managed, 'old.mdc')).existsSync(), isFalse);
      expect(
        File(p.join(temp.path, 'wb', 'rules', 'mine.md')).readAsStringSync(),
        'user rule',
      );
    });
  });
}
