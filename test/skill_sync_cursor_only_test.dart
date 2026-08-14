import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_hub/features/skill_sync/agent_resource_kind.dart';
import 'package:mcp_hub/features/skill_sync/convert/cursor_to_opencode_converter.dart';
import 'package:mcp_hub/features/skill_sync/skill_folder_copy.dart';
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
      expect(folderSync.pushedLocalDir, isNot(McpPaths.cursorSkillsCachePath));
      expect(folderSync.pushedResourceWire, 'skills');
      expect(result.message, contains('正式目录'));
    });

    test('覆盖 Cursor 后不自动转换；需显式一键转换', () async {
      var openCodeCalls = 0;
      final sync = SkillSyncService(
        loadConfig: () async => WebDavConfig.empty,
        folderCopy: const _NoopFolderCopy(),
        openCodeConverter: _RecordingOpenCodeConverter(
          () => openCodeCalls += 1,
        ),
      );

      final apply = await sync.applyResourceFromCache(AgentResourceKind.skill);
      expect(apply.ok, isTrue);
      expect(openCodeCalls, 0);
      expect(apply.message, contains('请使用「一键转换」'));

      final convert = await sync.convertResourceToAllTargets(
        AgentResourceKind.skill,
      );
      expect(convert.ok, isTrue);
      expect(openCodeCalls, 1);
      expect(convert.message, contains('Open Code'));
    });
  });
}

class _NoopFolderCopy extends SkillFolderCopy {
  const _NoopFolderCopy();

  @override
  Future<SkillFolderCopyResult> mirrorContents({
    required String sourceDir,
    required String targetDir,
    bool skipDotEntries = true,
    Set<String> preserveNames = const {},
  }) async {
    return SkillFolderCopyResult(
      copiedFiles: 0,
      copiedDirs: 0,
      sourcePath: sourceDir,
      targetPath: targetDir,
    );
  }
}

class _RecordingOpenCodeConverter extends CursorToOpenCodeConverter {
  _RecordingOpenCodeConverter(this.onCall);

  final void Function() onCall;

  @override
  Future<OpenCodeSkillsConvertResult> convertSkills({
    required String sourceDir,
    required String targetDir,
  }) async {
    onCall();
    return const OpenCodeSkillsConvertResult(
      packages: 2,
      copiedFiles: 2,
      deletedEntries: 0,
    );
  }

  @override
  Future<OpenCodeConvertResult> convertAll({
    required String cursorSkillsDir,
    required String cursorRulesDir,
    required String cursorCommandsDir,
    required String openCodeSkillsDir,
    required String openCodeAgentsMdPath,
    required String openCodeCommandsDir,
  }) async {
    onCall();
    return const OpenCodeConvertResult(skills: 2, rules: 1, commands: 0);
  }
}

class _RecordingFolderSync extends SkillWebDavFolderSync {
  String? pushedLocalDir;
  String? pushedResourceWire;
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
    required WebDavConfig config,
    required String resourceWireName,
    required String localDir,
    void Function(int done, int total)? onProgress,
  }) async {
    pushedLocalDir = localDir;
    pushedResourceWire = resourceWireName;
    pushCount += 1;
    return 0;
  }
}
