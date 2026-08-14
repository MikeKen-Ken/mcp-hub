import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_hub/features/config_backup/auto_backup_settings.dart';
import 'package:mcp_hub/features/config_backup/auto_config_backup_service.dart';
import 'package:mcp_hub/features/config_backup/config_backup_manifest.dart';
import 'package:mcp_hub/features/config_backup/config_backup_paths.dart';
import 'package:mcp_hub/features/config_backup/config_backup_service.dart';
import 'package:mcp_hub/features/skill_sync/agent_resource_kind.dart';
import 'package:mcp_hub/features/skill_sync/skill_target.dart';
import 'package:mcp_hub/models/mcp_server_entry.dart';
import 'package:mcp_hub/models/mcp_transport.dart';
import 'package:path/path.dart' as p;

void main() {
  group('AutoBackupSettings', () {
    test('默认每 10 分钟且启用，自动备份保留 14 天', () {
      const settings = AutoBackupSettings();
      expect(settings.enabled, isTrue);
      expect(settings.intervalMinutes, 10);
      expect(settings.retentionDays, 14);
      expect(settings.directory, isNull);
    });

    test('读取设置时把过短间隔和保留天数限制为 1', () {
      final settings = AutoBackupSettings.fromJson({
        'enabled': true,
        'directory': '  D:/backups  ',
        'intervalMinutes': 0,
        'retentionDays': 0,
      });
      expect(settings.enabled, isTrue);
      expect(settings.directory, 'D:/backups');
      expect(settings.intervalMinutes, 1);
      expect(settings.retentionDays, 1);
    });
  });

  group('ConfigBackupManifest', () {
    test('json roundtrip', () {
      final original = ConfigBackupManifest(
        formatVersion: ConfigBackupManifest.currentFormatVersion,
        exportedAt: DateTime.utc(2026, 8, 7, 9),
        appName: 'Agent Hub',
        fileCount: 3,
        notes: 'test',
      );
      final restored = ConfigBackupManifest.fromJson(original.toJson());
      expect(restored.formatVersion, original.formatVersion);
      expect(restored.appName, original.appName);
      expect(restored.fileCount, 3);
      expect(restored.notes, 'test');
      expect(restored.exportedAt.toUtc(), DateTime.utc(2026, 8, 7, 9));
    });
  });

  group('ConfigBackupPaths', () {
    test('zip 相对路径稳定', () {
      expect(
        ConfigBackupPaths.resourceZipDir(
          AgentResourceKind.skill,
          SkillTarget.cursor,
        ),
        'resources/skills/cursor',
      );
      expect(
        ConfigBackupPaths.resourceZipDir(
          AgentResourceKind.command,
          SkillTarget.cursor,
        ),
        'resources/commands/cursor',
      );
      expect(
        ConfigBackupPaths.codexAgentsMdZipPath,
        'resources/codex/AGENTS.md',
      );
    });
  });

  group('ConfigBackupService', () {
    test('suggestedFileName 含时间戳', () {
      final name = ConfigBackupService().suggestedFileName(
        DateTime(2026, 8, 7, 15, 2, 9),
      );
      expect(name, 'AgentHub-backup-20260807-150209.zip');
    });

    test('export/import roundtrip catalog', () async {
      final temp = await Directory.systemTemp.createTemp(
        'mcp_hub_backup_test_',
      );
      addTearDown(() async {
        if (await temp.exists()) await temp.delete(recursive: true);
      });

      final zipPath = p.join(temp.path, 'backup.zip');
      final servers = [
        const McpServerEntry(
          id: 'demo',
          name: 'Demo',
          transport: McpTransport.stdio,
          command: 'npx',
          args: ['-y', 'demo'],
          enabled: true,
        ),
      ];

      final service = ConfigBackupService();
      final exported = await service.exportToZip(
        zipPath: zipPath,
        servers: servers,
      );
      expect(exported.ok, isTrue, reason: exported.message);
      expect(File(zipPath).existsSync(), isTrue);

      // 校验 zip 内有 manifest
      final bytes = await File(zipPath).readAsBytes();
      expect(bytes.length, greaterThan(0));

      // 用手动解压目录结构验证 catalog 内容：通过 import 的 servers 字段
      // 注意：import 会写入真实部署路径；在 CI/无桌面路径时可能仍 ok 但 servers 可解析。
      // 这里直接读 zip 字节不够方便，改为解压后读 catalog。
      final extractDir = Directory(p.join(temp.path, 'out'));
      await extractDir.create();
      // 复用 service 私有逻辑不便；用 archive 解压在测试里直接验证建议用 export 后的 staging——
      // 简化：确认文件存在且 message 含 MCP 数量。
      expect(exported.serverCount, 1);
      expect(exported.message, contains('1 个 MCP'));

      // 再验证 catalog.json 可被 Json 解析：用 ZipDecoder
      final archive = ZipDecoder().decodeBytes(bytes);
      final catalogEntry = archive.findFile('catalog.json');
      expect(catalogEntry, isNotNull);
      final catalogJson =
          jsonDecode(utf8.decode(catalogEntry!.content as List<int>))
              as Map<String, dynamic>;
      expect((catalogJson['servers'] as List).length, 1);
      expect((catalogJson['servers'] as List).first['id'], 'demo');

      final manifestEntry = archive.findFile('manifest.json');
      expect(manifestEntry, isNotNull);
    });

    test('内容指纹覆盖 MCP、资源文件和 AGENTS.md，且不含原文', () async {
      final temp = await Directory.systemTemp.createTemp('backup_hash_test_');
      addTearDown(() async {
        if (await temp.exists()) await temp.delete(recursive: true);
      });
      final resources = Directory(p.join(temp.path, 'skills'));
      await resources.create();
      final skill = File(p.join(resources.path, 'example.md'));
      await skill.writeAsString('first');
      final agents = File(p.join(temp.path, 'AGENTS.md'));
      await agents.writeAsString('agent first');
      final service = ConfigBackupService(
        resourceSourcesProvider: () => [
          ConfigBackupResourceSource(
            sourcePath: resources.path,
            zipPath: 'resources/skills/cursor',
          ),
        ],
        codexAgentsMdPathProvider: () => agents.path,
      );
      const servers = [
        McpServerEntry(id: 'demo', name: 'Demo', transport: McpTransport.stdio),
      ];

      final original = await service.contentFingerprint(servers: servers);
      expect(await service.contentFingerprint(servers: servers), original);
      expect(original, isNot(contains('first')));

      await skill.writeAsString('changed');
      expect(
        await service.contentFingerprint(servers: servers),
        isNot(original),
      );

      await skill.writeAsString('first');
      await agents.writeAsString('agent changed');
      expect(
        await service.contentFingerprint(servers: servers),
        isNot(original),
      );

      await agents.writeAsString('agent first');
      const changedServers = [
        McpServerEntry(
          id: 'demo',
          name: 'Changed',
          transport: McpTransport.stdio,
        ),
      ];
      expect(
        await service.contentFingerprint(servers: changedServers),
        isNot(original),
      );
    });
  });

  group('AutoConfigBackupService', () {
    test('自动备份使用指定目录和当前 MCP 清单', () async {
      final temp = await Directory.systemTemp.createTemp('auto_backup_test_');
      addTearDown(() async {
        if (await temp.exists()) await temp.delete(recursive: true);
      });
      final fake = _FakeConfigBackupService();
      final service = AutoConfigBackupService(
        backupService: fake,
        settingsStore: _MemoryAutoBackupSettingsStore(),
        defaultDirectory: temp.path,
        now: () => DateTime(2026, 8, 9, 12, 30),
        loadServers: () async => const [
          McpServerEntry(
            id: 'demo',
            name: 'Demo',
            transport: McpTransport.stdio,
          ),
        ],
      );
      addTearDown(service.dispose);

      await service.initialize();
      final result = await service.backupNow();

      expect(result.ok, isTrue);
      expect(fake.lastServers.single.id, 'demo');
      expect(
        p.basename(fake.lastPath!),
        'AgentHub-auto-backup-20260809-123000.zip',
      );
      expect(service.lastBackupPath, fake.lastPath);
      expect(service.status, AutoBackupStatus.success);
    });

    test('定时备份只在内容变化时导出，立即备份始终导出', () async {
      final temp = await Directory.systemTemp.createTemp('auto_changed_test_');
      addTearDown(() async {
        if (await temp.exists()) await temp.delete(recursive: true);
      });
      var serverName = 'Demo';
      final fake = _FakeConfigBackupService();
      final service = AutoConfigBackupService(
        backupService: fake,
        settingsStore: _MemoryAutoBackupSettingsStore(),
        defaultDirectory: temp.path,
        loadServers: () async => [
          McpServerEntry(
            id: 'demo',
            name: serverName,
            transport: McpTransport.stdio,
          ),
        ],
      );
      addTearDown(service.dispose);

      await service.initialize();
      final skipped = await service.backupIfChanged();
      expect(skipped.message, '配置未变化，已跳过自动备份');
      expect(fake.exportCalls, 0);

      serverName = 'Changed';
      expect((await service.backupIfChanged()).ok, isTrue);
      expect(fake.exportCalls, 1);

      expect((await service.backupNow()).ok, isTrue);
      expect(fake.exportCalls, 2);
    });

    test('只清理超过保留天数的自动备份', () async {
      final temp = await Directory.systemTemp.createTemp('auto_cleanup_test_');
      addTearDown(() async {
        if (await temp.exists()) await temp.delete(recursive: true);
      });
      final oldAuto = File(
        p.join(temp.path, 'AgentHub-auto-backup-20260801-000000.zip'),
      );
      final recentAuto = File(
        p.join(temp.path, 'AgentHub-auto-backup-20260810-000000.zip'),
      );
      final manual = File(p.join(temp.path, 'AgentHub-backup-manual.zip'));
      for (final file in [oldAuto, recentAuto, manual]) {
        await file.writeAsString('test');
      }
      await oldAuto.setLastModified(DateTime(2026, 8, 1));
      await recentAuto.setLastModified(DateTime(2026, 8, 10));
      await manual.setLastModified(DateTime(2026, 8, 1));

      final service = AutoConfigBackupService(
        loadServers: () async => const [],
        settingsStore: _MemoryAutoBackupSettingsStore(),
        defaultDirectory: temp.path,
        now: () => DateTime(2026, 8, 20),
      );
      addTearDown(service.dispose);
      await service.initialize();

      final result = await service.cleanupNow();

      expect(result.ok, isTrue);
      expect(result.fileCount, 1);
      expect(result.message, contains('当前目录'));
      expect(await oldAuto.exists(), isFalse);
      expect(await recentAuto.exists(), isTrue);
      expect(await manual.exists(), isTrue);
    });

    test('清理过期备份使用当前设置的保留天数', () async {
      final temp = await Directory.systemTemp.createTemp(
        'auto_cleanup_custom_test_',
      );
      addTearDown(() async {
        if (await temp.exists()) await temp.delete(recursive: true);
      });
      final threeDaysOld = File(
        p.join(temp.path, 'AgentHub-auto-backup-20260806-000000.zip'),
      );
      await threeDaysOld.writeAsString('test');
      await threeDaysOld.setLastModified(DateTime(2026, 8, 6));

      final store = _MemoryAutoBackupSettingsStore()
        ..value = const AutoBackupSettings(retentionDays: 2);
      final service = AutoConfigBackupService(
        loadServers: () async => const [],
        settingsStore: store,
        defaultDirectory: temp.path,
        now: () => DateTime(2026, 8, 9),
      );
      addTearDown(service.dispose);
      await service.initialize();

      expect(await service.cleanupExpiredBackups(temp.path), 1);
      expect(await threeDaysOld.exists(), isFalse);
    });
  });
}

class _FakeConfigBackupService extends ConfigBackupService {
  String? lastPath;
  List<McpServerEntry> lastServers = const [];
  int exportCalls = 0;

  @override
  Future<ConfigBackupResult> exportToZip({
    required String zipPath,
    required List<McpServerEntry> servers,
  }) async {
    exportCalls += 1;
    lastPath = zipPath;
    lastServers = servers;
    await File(zipPath).writeAsString('backup');
    return ConfigBackupResult(
      ok: true,
      message: '自动备份完成',
      path: zipPath,
      serverCount: servers.length,
    );
  }
}

class _MemoryAutoBackupSettingsStore extends AutoBackupSettingsStore {
  AutoBackupSettings value = const AutoBackupSettings();

  @override
  Future<AutoBackupSettings> load() async => value;

  @override
  Future<void> save(AutoBackupSettings settings) async {
    value = settings;
  }
}
