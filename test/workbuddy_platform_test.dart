import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_hub/common/agent_platforms.dart';
import 'package:mcp_hub/features/skill_sync/agent_resource_kind.dart';
import 'package:mcp_hub/services/mcp_paths.dart';
import 'package:path/path.dart' as p;

void main() {
  group('WorkBuddy platforms', () {
    test('are registered as MCP-configurable with the Cursor JSON format', () {
      final ids = AgentPlatforms.mcpConfigurable.map((e) => e.id);
      expect(ids, contains(AgentPlatformId.workBuddy));
      expect(ids, contains(AgentPlatformId.workBuddyAi));
      for (final id in [
        AgentPlatformId.workBuddy,
        AgentPlatformId.workBuddyAi,
      ]) {
        expect(
          AgentPlatforms.of(id).mcpConfig?.format,
          AgentMcpConfigFormat.cursorJson,
        );
      }
    });

    test('use separate user-level mcp.json paths', () {
      final cn = AgentPlatforms.workBuddy.mcpConfigFilePath;
      final intl = AgentPlatforms.workBuddyAi.mcpConfigFilePath;
      expect(cn, isNotNull);
      expect(intl, isNotNull);
      expect(p.basename(p.dirname(cn!)), '.workbuddy');
      expect(p.basename(p.dirname(intl!)), '.workbuddy-ai');
      expect(p.basename(cn), 'mcp.json');
      expect(p.basename(intl), 'mcp.json');
      expect(cn, McpPaths.workBuddyMcpConfigPath);
      expect(intl, McpPaths.workBuddyAiMcpConfigPath);
    });

    test('are excluded from folder resource sync and conversion', () {
      final folderIds = AgentPlatforms.folderResourcePlatforms.map((e) => e.id);
      expect(folderIds, isNot(contains(AgentPlatformId.workBuddy)));
      expect(folderIds, isNot(contains(AgentPlatformId.workBuddyAi)));
      expect(
        AgentPlatforms.skillConversionTargets.map((e) => e.id),
        isNot(contains(AgentPlatformId.workBuddy)),
      );
      for (final resource in AgentResourceKind.values) {
        for (final id in [
          AgentPlatformId.workBuddy,
          AgentPlatformId.workBuddyAi,
        ]) {
          expect(resource.supportsLocalPath(id), isFalse);
          expect(resource.canConvertTo(id), isFalse);
          expect(AgentPlatforms.localResourcePath(resource, id), isNull);
        }
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
}
