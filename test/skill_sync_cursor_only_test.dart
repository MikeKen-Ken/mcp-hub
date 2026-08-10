import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_hub/features/skill_sync/agent_resource_kind.dart';
import 'package:mcp_hub/features/skill_sync/skill_sync_service.dart';
import 'package:mcp_hub/features/skill_sync/skill_target.dart';
import 'package:mcp_hub/features/skill_sync/skill_webdav_folder_sync.dart';
import 'package:mcp_hub/services/mcp_paths.dart';
import 'package:mcp_hub/webdav/webdav_config.dart';
import 'package:webdav_client/webdav_client.dart';

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

    test('上传直接读取 Cursor 正式目录，不经缓存', () async {
      final folderSync = _RecordingFolderSync();
      final configured = const WebDavConfig(
        enabled: true,
        serverUrl: 'https://dav.example.com/',
        username: 'user',
        password: 'secret',
        remotePath: '/AgentHub',
        autoSync: false,
        autoPull: false,
        pollIntervalSeconds: WebDavConfig.defaultPollIntervalSeconds,
        pushDebounceSeconds: WebDavConfig.defaultPushDebounceSeconds,
      );
      final sync = SkillSyncService(
        loadConfig: () async => configured,
        folderSync: folderSync,
      );

      final result = await sync.pushResourceToWebDav(
        AgentResourceKind.skill,
        SkillTarget.cursor,
      );

      expect(result.ok, isTrue);
      expect(folderSync.pushCount, 1);
      expect(folderSync.pushedLocalDir, McpPaths.cursorSkillsPath);
      expect(
        folderSync.pushedLocalDir,
        isNot(McpPaths.cursorSkillsCachePath),
      );
      expect(folderSync.pushedRemoteDir, '/AgentHub/skills/cursor');
      expect(result.message, contains('正式目录'));
    });
  });
}

class _RecordingFolderSync extends SkillWebDavFolderSync {
  String? pushedLocalDir;
  String? pushedRemoteDir;
  int pushCount = 0;

  @override
  Client? clientFor(WebDavConfig config) {
    if (!config.isConfigured) return null;
    return newClient(
      config.serverUrl,
      user: config.username,
      password: config.password,
    );
  }

  @override
  Future<int> pushFolder({
    required Client client,
    required String remoteDir,
    required String localDir,
  }) async {
    pushedLocalDir = localDir;
    pushedRemoteDir = remoteDir;
    pushCount += 1;
    return 0;
  }
}
