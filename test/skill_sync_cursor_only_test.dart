import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_hub/features/skill_sync/agent_resource_kind.dart';
import 'package:mcp_hub/features/skill_sync/skill_sync_service.dart';
import 'package:mcp_hub/features/skill_sync/skill_target.dart';
import 'package:mcp_hub/webdav/webdav_config.dart';

void main() {
  group('SkillSyncService Cursor-only WebDAV', () {
    late SkillSyncService service;

    setUp(() {
      service = SkillSyncService(loadConfig: () async => WebDavConfig.empty);
    });

    test('拒绝将 Codex 作为 WebDAV 下载/上传目标', () async {
      final pull = await service.syncResourceFromWebDav(
        AgentResourceKind.skill,
        SkillTarget.codex,
      );
      expect(pull.ok, isFalse);
      expect(pull.message, contains('仅下载/上传 Cursor'));

      final push = await service.pushResourceToWebDav(
        AgentResourceKind.rule,
        SkillTarget.codex,
      );
      expect(push.ok, isFalse);
      expect(push.message, contains('仅下载/上传 Cursor'));
    });

    test('Command 一键转换明确不支持', () async {
      final result = await service.convertFromCursor(AgentResourceKind.command);
      expect(result.ok, isFalse);
      expect(result.message, contains('暂无 Codex 对等目录'));
    });

    test('Open Code 入口明确阻塞且不猜写入格式', () async {
      final service = SkillSyncService(
        loadConfig: () async => WebDavConfig.empty,
      );

      final result = await service.convertFromCursor(
        AgentResourceKind.skill,
        target: SkillTarget.openCode,
      );

      expect(result.ok, isFalse);
      expect(result.target, SkillTarget.openCode);
      expect(result.message, contains('未确认 Open Code'));
    });
  });
}
