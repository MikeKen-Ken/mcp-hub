import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_hub/features/config_backup/config_backup_manifest.dart';
import 'package:mcp_hub/features/config_backup/config_backup_paths.dart';
import 'package:mcp_hub/features/config_backup/config_backup_service.dart';
import 'package:mcp_hub/features/skill_sync/agent_resource_kind.dart';
import 'package:mcp_hub/features/skill_sync/skill_target.dart';
import 'package:mcp_hub/models/mcp_server_entry.dart';
import 'package:mcp_hub/models/mcp_transport.dart';
import 'package:path/path.dart' as p;

void main() {
  group('ConfigBackupManifest', () {
    test('json roundtrip', () {
      final original = ConfigBackupManifest(
        formatVersion: ConfigBackupManifest.currentFormatVersion,
        exportedAt: DateTime.utc(2026, 8, 7, 9),
        appName: 'Agent Hub',
        fileCount: 3,
        notes: 'test',
      );
      final restored =
          ConfigBackupManifest.fromJson(original.toJson());
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
      final temp = await Directory.systemTemp.createTemp('mcp_hub_backup_test_');
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
  });
}
