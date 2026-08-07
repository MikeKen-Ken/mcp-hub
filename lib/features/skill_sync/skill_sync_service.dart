import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../services/mcp_paths.dart';
import '../../webdav/webdav_config.dart';
import 'skill_folder_copy.dart';
import 'skill_target.dart';
import 'skill_webdav_folder_sync.dart';

enum SkillSyncStatus { idle, syncing, success, error }

/// 一次 Skill 同步的结果摘要。
class SkillSyncResult {
  const SkillSyncResult({
    required this.ok,
    required this.message,
    this.target,
    this.pulledFiles = 0,
    this.pushedFiles = 0,
    this.deployedFiles = 0,
    this.packageCount = 0,
  });

  final bool ok;
  final String message;
  final SkillTarget? target;
  final int pulledFiles;
  final int pushedFiles;
  final int deployedFiles;
  final int packageCount;
}

/// Skill 模块：WebDAV 同步文件夹 → 本机缓存 → 复制到 Cursor/Codex。
class SkillSyncService extends ChangeNotifier {
  SkillSyncService({
    required Future<WebDavConfig> Function() this._loadConfig,
    SkillWebDavFolderSync? folderSync,
    SkillFolderCopy? folderCopy,
  })  : _folderSync = folderSync ?? SkillWebDavFolderSync(),
        _folderCopy = folderCopy ?? const SkillFolderCopy();

  final Future<WebDavConfig> Function() _loadConfig;
  final SkillWebDavFolderSync _folderSync;
  final SkillFolderCopy _folderCopy;

  SkillSyncStatus status = SkillSyncStatus.idle;
  String? lastError;
  String? lastMessage;
  DateTime? lastSyncedAt;
  SkillTarget? lastTarget;

  String? cachePathFor(SkillTarget target) => switch (target) {
        SkillTarget.cursor => McpPaths.cursorSkillsCachePath,
        SkillTarget.codex => McpPaths.codexSkillsCachePath,
      };

  String? deployPathFor(SkillTarget target) => switch (target) {
        SkillTarget.cursor => McpPaths.cursorSkillsPath,
        SkillTarget.codex => McpPaths.codexSkillsPath,
      };

  /// 从 WebDAV 拉取并复制到目标客户端 Skill 目录。
  Future<SkillSyncResult> syncFromWebDav(SkillTarget target) async {
    return _run(target, () async {
      final config = await _loadConfig();
      if (!config.enabled || !config.isConfigured) {
        throw StateError('请先配置并启用 WebDAV');
      }
      final cachePath = cachePathFor(target);
      final deployPath = deployPathFor(target);
      if (cachePath == null || deployPath == null) {
        throw StateError('当前平台不支持 Skill 同步');
      }

      final client = _folderSync.clientFor(config);
      if (client == null) {
        throw StateError('WebDAV 未配置完整');
      }

      final remote = _folderSync.remoteSkillsDir(config, target.wireName);
      final pulled = await _folderSync.pullFolder(
        client: client,
        remoteDir: remote,
        localDir: cachePath,
      );
      final deploy = await _folderCopy.copyContents(
        sourceDir: cachePath,
        targetDir: deployPath,
      );
      final packages = await _folderCopy.countSkillPackages(deployPath);

      return SkillSyncResult(
        ok: true,
        target: target,
        pulledFiles: pulled,
        deployedFiles: deploy.copiedFiles,
        packageCount: packages,
        message: '已同步 ${target.label} Skill：'
            '拉取 $pulled 个文件，部署 ${deploy.copiedFiles} 个文件'
            '（约 $packages 个 Skill 包）→ $deployPath',
      );
    });
  }

  /// 把本机目标目录内容上传到 WebDAV（先复制到缓存再推送）。
  Future<SkillSyncResult> pushToWebDav(SkillTarget target) async {
    return _run(target, () async {
      final config = await _loadConfig();
      if (!config.enabled || !config.isConfigured) {
        throw StateError('请先配置并启用 WebDAV');
      }
      final cachePath = cachePathFor(target);
      final deployPath = deployPathFor(target);
      if (cachePath == null || deployPath == null) {
        throw StateError('当前平台不支持 Skill 同步');
      }

      // 优先以客户端目录为准；若尚无部署目录则直接推缓存。
      final deployDir = Directory(deployPath);
      if (await deployDir.exists()) {
        await _folderCopy.copyContents(
          sourceDir: deployPath,
          targetDir: cachePath,
        );
      } else {
        await Directory(cachePath).create(recursive: true);
      }

      final client = _folderSync.clientFor(config);
      if (client == null) {
        throw StateError('WebDAV 未配置完整');
      }

      final remote = _folderSync.remoteSkillsDir(config, target.wireName);
      final pushed = await _folderSync.pushFolder(
        client: client,
        remoteDir: remote,
        localDir: cachePath,
      );
      final packages = await _folderCopy.countSkillPackages(cachePath);

      return SkillSyncResult(
        ok: true,
        target: target,
        pushedFiles: pushed,
        packageCount: packages,
        message: '已上传 ${target.label} Skill：$pushed 个文件'
            '（约 $packages 个 Skill 包）→ $remote',
      );
    });
  }

  /// 仅把本机缓存复制到客户端目录（不访问 WebDAV）。
  Future<SkillSyncResult> deployFromCache(SkillTarget target) async {
    return _run(target, () async {
      final cachePath = cachePathFor(target);
      final deployPath = deployPathFor(target);
      if (cachePath == null || deployPath == null) {
        throw StateError('当前平台不支持 Skill 同步');
      }
      final deploy = await _folderCopy.copyContents(
        sourceDir: cachePath,
        targetDir: deployPath,
      );
      final packages = await _folderCopy.countSkillPackages(deployPath);
      return SkillSyncResult(
        ok: true,
        target: target,
        deployedFiles: deploy.copiedFiles,
        packageCount: packages,
        message: '已从缓存部署 ${target.label} Skill：'
            '${deploy.copiedFiles} 个文件（约 $packages 个包）→ $deployPath',
      );
    });
  }

  Future<SkillSyncResult> _run(
    SkillTarget target,
    Future<SkillSyncResult> Function() action,
  ) async {
    if (status == SkillSyncStatus.syncing) {
      return const SkillSyncResult(
        ok: false,
        message: 'Skill 同步进行中，请稍候',
      );
    }

    status = SkillSyncStatus.syncing;
    lastTarget = target;
    lastError = null;
    notifyListeners();

    try {
      final result = await action();
      lastMessage = result.message;
      lastSyncedAt = DateTime.now();
      lastError = null;
      status = SkillSyncStatus.success;
      notifyListeners();
      return result;
    } catch (error) {
      lastError = '$error';
      lastMessage = lastError;
      status = SkillSyncStatus.error;
      debugPrint('Skill 同步失败: $error');
      notifyListeners();
      return SkillSyncResult(
        ok: false,
        target: target,
        message: lastError!,
      );
    }
  }
}
