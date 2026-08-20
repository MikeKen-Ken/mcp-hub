import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../app_brand.dart';
import '../../features/skill_sync/agent_resource_kind.dart';
import '../../features/skill_sync/cursor_hooks_bundle.dart';
import '../../features/skill_sync/skill_folder_copy.dart';
import '../../features/skill_sync/skill_target.dart';
import '../../models/mcp_server_entry.dart';
import '../../services/mcp_paths.dart';
import 'config_backup_manifest.dart';
import 'config_backup_paths.dart';

/// 一次导出/导入的结果摘要。
class ConfigBackupResult {
  const ConfigBackupResult({
    required this.ok,
    required this.message,
    this.path,
    this.fileCount = 0,
    this.serverCount = 0,
  });

  final bool ok;
  final String message;
  final String? path;
  final int fileCount;
  final int serverCount;
}

/// 导入解析结果：资源已写盘；[servers] 需由 Hub 合并进 catalog。
class ConfigBackupImportPayload {
  const ConfigBackupImportPayload({required this.result, this.servers});

  final ConfigBackupResult result;
  final List<McpServerEntry>? servers;
}

/// 一项实际会写入备份包的 Agent 资源目录。
class ConfigBackupResourceSource {
  const ConfigBackupResourceSource({
    required this.sourcePath,
    required this.zipPath,
  });

  final String sourcePath;
  final String zipPath;
}

/// 把 MCP 清单与本机 Agent 配置打成 zip，或从 zip 恢复。
///
/// 不含 WebDAV 账号密码；含 catalog 中的 env/cwd 等本机字段（便于同机恢复）。
class ConfigBackupService {
  ConfigBackupService({
    SkillFolderCopy? folderCopy,
    Iterable<ConfigBackupResourceSource> Function()? resourceSourcesProvider,
    String? Function()? codexAgentsMdPathProvider,
    CursorHooksBundle? hooksBundle,
    CursorHooksLayout? Function()? cursorHooksLayoutProvider,
  }) : _folderCopy = folderCopy ?? const SkillFolderCopy(),
       _resourceSourcesProvider =
           resourceSourcesProvider ?? _defaultResourceSources,
       _codexAgentsMdPathProvider =
           codexAgentsMdPathProvider ?? (() => McpPaths.codexAgentsMdPath),
       _hooksBundle = hooksBundle ?? const CursorHooksBundle(),
       _cursorHooksLayoutProvider =
           cursorHooksLayoutProvider ?? CursorHooksLayout.cursorUser;

  final SkillFolderCopy _folderCopy;
  final Iterable<ConfigBackupResourceSource> Function()
  _resourceSourcesProvider;
  final String? Function() _codexAgentsMdPathProvider;
  final CursorHooksBundle _hooksBundle;
  final CursorHooksLayout? Function() _cursorHooksLayoutProvider;

  /// 建议的备份文件名（含时间戳）。
  String suggestedFileName([DateTime? at]) {
    final t = (at ?? DateTime.now()).toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return 'AgentHub-backup-'
        '${t.year}${two(t.month)}${two(t.day)}-'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}.zip';
  }

  /// 将当前配置导出到 [zipPath]。
  Future<ConfigBackupResult> exportToZip({
    required String zipPath,
    required List<McpServerEntry> servers,
  }) async {
    if (!McpPaths.isDesktopSupported) {
      return const ConfigBackupResult(ok: false, message: '当前平台不支持配置备份');
    }

    final staging = await _createStagingDir('export');
    try {
      var fileCount = 0;

      final catalogPayload = {
        'version': 1,
        'servers': servers.map((s) => s.toJson()).toList(),
      };
      final catalogFile = File(
        p.join(staging.path, ConfigBackupPaths.catalogFile),
      );
      await catalogFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(catalogPayload),
      );
      fileCount += 1;

      // 与 WebDAV 约定一致：资源权威源为 Cursor；Codex 由转换生成（另存 AGENTS.md）。
      for (final source in _resourceSourcesProvider()) {
        final sourceDir = Directory(source.sourcePath);
        if (!await sourceDir.exists()) continue;

        final copied = await _folderCopy.copyContents(
          sourceDir: source.sourcePath,
          targetDir: p.join(staging.path, source.zipPath),
        );
        fileCount += copied.copiedFiles;
      }

      fileCount += await _exportCursorHooks(
        p.join(
          staging.path,
          ConfigBackupPaths.resourceZipDir(
            AgentResourceKind.hook,
            SkillTarget.cursor,
          ),
        ),
      );

      final agentsMd = _codexAgentsMdPathProvider();
      if (agentsMd != null) {
        final src = File(agentsMd);
        if (await src.exists()) {
          final dest = File(
            p.join(staging.path, ConfigBackupPaths.codexAgentsMdZipPath),
          );
          await dest.parent.create(recursive: true);
          await src.copy(dest.path);
          fileCount += 1;
        }
      }

      final manifest = ConfigBackupManifest(
        formatVersion: ConfigBackupManifest.currentFormatVersion,
        exportedAt: DateTime.now().toUtc(),
        appName: AppBrand.displayName,
        fileCount: fileCount,
        notes:
            '含 MCP 清单与本机 Cursor Skill/Command/Rule/Hook，以及 Codex AGENTS.md；'
            '不含 WebDAV 密码与 servers 仓库克隆。Codex Skills / Hooks 请由 Cursor 转换生成。',
      );
      await File(
        p.join(staging.path, ConfigBackupManifest.fileName),
      ).writeAsString(
        const JsonEncoder.withIndent('  ').convert(manifest.toJson()),
      );

      final out = File(zipPath);
      await out.parent.create(recursive: true);
      if (await out.exists()) {
        await out.delete();
      }
      await _zipDirectoryFlat(staging, zipPath);

      return ConfigBackupResult(
        ok: true,
        path: zipPath,
        fileCount: fileCount,
        serverCount: servers.length,
        message: '已导出备份：${servers.length} 个 MCP，$fileCount 个文件 → $zipPath',
      );
    } catch (error) {
      debugPrint('配置导出失败: $error');
      return ConfigBackupResult(ok: false, message: '导出失败：$error');
    } finally {
      await _safeDeleteDir(staging);
    }
  }

  /// 计算所有实际导出来源的内容指纹，不写入原文、密钥或文件路径。
  ///
  /// 自动备份只在该指纹变化时创建 zip；手动导出不依赖此方法。
  Future<String> contentFingerprint({
    required List<McpServerEntry> servers,
  }) async {
    Digest? digest;
    final converter = sha256.startChunkedConversion(
      ChunkedConversionSink.withCallback((digests) => digest = digests.single),
    );

    void addText(String value) {
      final bytes = utf8.encode(value);
      converter.add(utf8.encode('${bytes.length}:'));
      converter.add(bytes);
    }

    addText('catalog.json');
    addText(
      const JsonEncoder.withIndent('  ').convert({
        'version': 1,
        'servers': servers.map((server) => server.toJson()).toList(),
      }),
    );

    for (final source in _resourceSourcesProvider()) {
      final sourceDir = Directory(source.sourcePath);
      if (!await sourceDir.exists()) continue;
      final files = <File>[];
      await for (final entity in sourceDir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File ||
            _hasDotPathSegment(entity.path, sourceDir.path)) {
          continue;
        }
        files.add(entity);
      }
      files.sort(
        (a, b) => p
            .relative(a.path, from: sourceDir.path)
            .compareTo(p.relative(b.path, from: sourceDir.path)),
      );
      for (final file in files) {
        final relativePath = p.posix.joinAll(
          p.split(p.relative(file.path, from: sourceDir.path)),
        );
        addText('${source.zipPath}/$relativePath');
        await for (final bytes in file.openRead()) {
          converter.add(bytes);
        }
      }
    }

    await _hashCursorHooks(addText, converter.add);

    final agentsMd = _codexAgentsMdPathProvider();
    if (agentsMd != null) {
      final file = File(agentsMd);
      if (await file.exists()) {
        addText(ConfigBackupPaths.codexAgentsMdZipPath);
        await for (final bytes in file.openRead()) {
          converter.add(bytes);
        }
      }
    }

    converter.close();
    return digest!.toString();
  }

  static Iterable<ConfigBackupResourceSource> _defaultResourceSources() sync* {
    for (final resource in AgentResourceKind.values) {
      if (resource == AgentResourceKind.hook) continue;
      for (final target in resource.webDavTargets) {
        final path = ConfigBackupPaths.localDeployPath(resource, target);
        if (path == null) continue;
        yield ConfigBackupResourceSource(
          sourcePath: path,
          zipPath: ConfigBackupPaths.resourceZipDir(resource, target),
        );
      }
    }
  }

  static bool _hasDotPathSegment(String path, String from) => p
      .split(p.relative(path, from: from))
      .any((segment) => segment.startsWith('.'));

  /// 从备份 zip 恢复。返回解析出的 servers（由调用方写入 catalog）与资源恢复计数。
  Future<ConfigBackupImportPayload> importFromZip(String zipPath) async {
    if (!McpPaths.isDesktopSupported) {
      return const ConfigBackupImportPayload(
        result: ConfigBackupResult(ok: false, message: '当前平台不支持配置备份'),
      );
    }

    final zipFile = File(zipPath);
    if (!await zipFile.exists()) {
      return ConfigBackupImportPayload(
        result: ConfigBackupResult(ok: false, message: '备份文件不存在：$zipPath'),
      );
    }

    final staging = await _createStagingDir('import');
    try {
      await extractFileToDisk(zipPath, staging.path);

      final root = await _resolveBackupRoot(staging);
      final manifestFile = File(
        p.join(root.path, ConfigBackupManifest.fileName),
      );
      if (!await manifestFile.exists()) {
        return const ConfigBackupImportPayload(
          result: ConfigBackupResult(
            ok: false,
            message: '不是有效的 Agent Hub 备份包（缺少 manifest.json）',
          ),
        );
      }

      final manifestJson =
          jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
      final manifest = ConfigBackupManifest.fromJson(manifestJson);
      if (manifest.formatVersion > ConfigBackupManifest.currentFormatVersion) {
        return ConfigBackupImportPayload(
          result: ConfigBackupResult(
            ok: false,
            message:
                '备份格式过新（v${manifest.formatVersion}），请先升级 ${AppBrand.displayName}',
          ),
        );
      }

      List<McpServerEntry>? servers;
      final catalogFile = File(
        p.join(root.path, ConfigBackupPaths.catalogFile),
      );
      if (await catalogFile.exists()) {
        final decoded = jsonDecode(await catalogFile.readAsString());
        if (decoded is Map<String, dynamic>) {
          final list = decoded['servers'];
          if (list is List) {
            servers = list
                .whereType<Map>()
                .map(
                  (e) => McpServerEntry.fromJson(Map<String, dynamic>.from(e)),
                )
                .toList();
          }
        }
      }

      var restoredFiles = 0;
      for (final resource in AgentResourceKind.values) {
        if (resource == AgentResourceKind.hook) continue;
        for (final target in resource.webDavTargets) {
          final zipRel = ConfigBackupPaths.resourceZipDir(resource, target);
          final zipAbs = p.join(root.path, zipRel);
          if (!await Directory(zipAbs).exists()) continue;

          final deploy = ConfigBackupPaths.localDeployPath(resource, target);
          final cache = ConfigBackupPaths.localCachePath(resource, target);
          if (deploy != null) {
            final copied = await _folderCopy.copyContents(
              sourceDir: zipAbs,
              targetDir: deploy,
            );
            restoredFiles += copied.copiedFiles;
          }
          if (cache != null) {
            await _folderCopy.copyContents(sourceDir: zipAbs, targetDir: cache);
          }
        }
      }

      restoredFiles += await _importCursorHooks(root);

      // 兼容旧备份中的 resources/*/codex（新导出不再写入；忽略缺失即可）。
      for (final resource in [
        AgentResourceKind.skill,
        AgentResourceKind.rule,
      ]) {
        final zipRel = ConfigBackupPaths.resourceZipDir(
          resource,
          SkillTarget.codex,
        );
        final zipAbs = p.join(root.path, zipRel);
        if (!await Directory(zipAbs).exists()) continue;
        final deploy = ConfigBackupPaths.localDeployPath(
          resource,
          SkillTarget.codex,
        );
        if (deploy == null) continue;
        final copied = await _folderCopy.copyContents(
          sourceDir: zipAbs,
          targetDir: deploy,
        );
        restoredFiles += copied.copiedFiles;
      }

      final agentsZip = File(
        p.join(root.path, ConfigBackupPaths.codexAgentsMdZipPath),
      );
      final agentsLocal = McpPaths.codexAgentsMdPath;
      if (await agentsZip.exists() && agentsLocal != null) {
        final dest = File(agentsLocal);
        await dest.parent.create(recursive: true);
        await agentsZip.copy(dest.path);
        restoredFiles += 1;
      }

      final serverCount = servers?.length ?? 0;
      return ConfigBackupImportPayload(
        servers: servers,
        result: ConfigBackupResult(
          ok: true,
          path: zipPath,
          fileCount: restoredFiles,
          serverCount: serverCount,
          message: servers == null
              ? '已恢复 Agent 配置：$restoredFiles 个文件（备份中无 MCP 清单）'
              : '已恢复备份：$serverCount 个 MCP，$restoredFiles 个文件',
        ),
      );
    } catch (error) {
      debugPrint('配置导入失败: $error');
      return ConfigBackupImportPayload(
        result: ConfigBackupResult(ok: false, message: '导入失败：$error'),
      );
    } finally {
      await _safeDeleteDir(staging);
    }
  }

  Future<int> _exportCursorHooks(String zipAbs) async {
    final layout = _cursorHooksLayoutProvider();
    if (layout == null) return 0;
    final copied = await _hooksBundle.exportFromLayout(
      layout: layout,
      bundleDir: zipAbs,
    );
    return copied.copiedFiles;
  }

  Future<int> _importCursorHooks(Directory root) async {
    final zipRel = ConfigBackupPaths.resourceZipDir(
      AgentResourceKind.hook,
      SkillTarget.cursor,
    );
    final zipAbs = p.join(root.path, zipRel);
    if (!await Directory(zipAbs).exists()) return 0;
    final layout = _cursorHooksLayoutProvider();
    var count = 0;
    if (layout != null) {
      final applied = await _hooksBundle.applyToLayout(
        bundleDir: zipAbs,
        layout: layout,
      );
      count += applied.copiedFiles;
    }
    final cache = ConfigBackupPaths.localCachePath(
      AgentResourceKind.hook,
      SkillTarget.cursor,
    );
    if (cache != null) {
      await _folderCopy.copyContents(sourceDir: zipAbs, targetDir: cache);
    }
    return count;
  }

  Future<void> _hashCursorHooks(
    void Function(String value) addText,
    void Function(List<int> bytes) addBytes,
  ) async {
    final layout = _cursorHooksLayoutProvider();
    if (layout == null) return;
    final zipPrefix = ConfigBackupPaths.resourceZipDir(
      AgentResourceKind.hook,
      SkillTarget.cursor,
    );
    final jsonFile = File(layout.hooksJsonPath);
    if (await jsonFile.exists()) {
      addText('$zipPrefix/${CursorHooksBundle.jsonFileName}');
      await for (final bytes in jsonFile.openRead()) {
        addBytes(bytes);
      }
    }
    final hooksDir = Directory(layout.hooksDirectoryPath);
    if (!await hooksDir.exists()) return;
    final files = <File>[];
    await for (final entity in hooksDir.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File || _hasDotPathSegment(entity.path, hooksDir.path)) {
        continue;
      }
      files.add(entity);
    }
    files.sort(
      (a, b) => p
          .relative(a.path, from: hooksDir.path)
          .compareTo(p.relative(b.path, from: hooksDir.path)),
    );
    for (final file in files) {
      final relativePath = p.posix.joinAll(
        p.split(p.relative(file.path, from: hooksDir.path)),
      );
      addText('$zipPrefix/${CursorHooksBundle.scriptsDirName}/$relativePath');
      await for (final bytes in file.openRead()) {
        addBytes(bytes);
      }
    }
  }

  /// 将目录内容打成 zip（条目路径相对 [dir]，不含外层目录名）。
  Future<void> _zipDirectoryFlat(Directory dir, String zipPath) async {
    final archive = Archive();
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final rel = p.posix.joinAll(
        p.split(p.relative(entity.path, from: dir.path)),
      );
      final data = await entity.readAsBytes();
      archive.addFile(ArchiveFile(rel, data.length, data));
    }
    final encoded = ZipEncoder().encode(archive);
    await File(zipPath).writeAsBytes(encoded, flush: true);
  }

  /// 兼容「多包一层目录」的备份 zip。
  Future<Directory> _resolveBackupRoot(Directory extracted) async {
    final direct = File(p.join(extracted.path, ConfigBackupManifest.fileName));
    if (await direct.exists()) return extracted;

    await for (final entity in extracted.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final nested = File(p.join(entity.path, ConfigBackupManifest.fileName));
      if (await nested.exists()) return entity;
    }
    return extracted;
  }

  Future<Directory> _createStagingDir(String kind) async {
    final dir = Directory(
      p.join(
        Directory.systemTemp.path,
        'mcp_hub_backup_${kind}_${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await dir.create(recursive: true);
    return dir;
  }

  Future<void> _safeDeleteDir(Directory dir) async {
    try {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (error) {
      debugPrint('清理备份临时目录失败: $error');
    }
  }
}
