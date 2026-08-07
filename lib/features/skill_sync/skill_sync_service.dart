import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../services/mcp_paths.dart';
import '../../webdav/webdav_config.dart';
import 'agent_resource_kind.dart';
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
    required this._loadConfig,
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
  AgentResourceKind? lastResource;

  String? cachePathFor(SkillTarget target) => switch (target) {
        SkillTarget.cursor => McpPaths.cursorSkillsCachePath,
        SkillTarget.codex => McpPaths.codexSkillsCachePath,
      };

  String? deployPathFor(SkillTarget target) => switch (target) {
        SkillTarget.cursor => McpPaths.cursorSkillsPath,
        SkillTarget.codex => McpPaths.codexSkillsPath,
      };

  String? resourceCachePathFor(
    AgentResourceKind resource,
    SkillTarget target,
  ) =>
      McpPaths.resourceCachePath(resource.wireName, target.wireName);

  String? resourceDeployPathFor(
    AgentResourceKind resource,
    SkillTarget target,
  ) =>
      switch ((resource, target)) {
        (AgentResourceKind.skill, SkillTarget.cursor) =>
          McpPaths.cursorSkillsPath,
        (AgentResourceKind.skill, SkillTarget.codex) => McpPaths.codexSkillsPath,
        (AgentResourceKind.command, SkillTarget.cursor) =>
          McpPaths.cursorCommandsPath,
        (AgentResourceKind.command, SkillTarget.codex) =>
          McpPaths.codexCommandsPath,
        (AgentResourceKind.rule, SkillTarget.cursor) => McpPaths.cursorRulesPath,
        (AgentResourceKind.rule, SkillTarget.codex) => McpPaths.codexRulesPath,
      };

  /// 从 WebDAV 拉取并复制到目标客户端 Skill 目录。
  Future<SkillSyncResult> syncFromWebDav(SkillTarget target) async {
    return syncResourceFromWebDav(AgentResourceKind.skill, target);
  }

  Future<SkillSyncResult> syncResourceFromWebDav(
    AgentResourceKind resource,
    SkillTarget target,
  ) async {
    return _run(resource, target, () => _doSyncOne(resource, target));
  }

  /// 从 WebDAV 拉取并部署到该资源支持的全部客户端（一次忙状态）。
  Future<SkillSyncResult> syncResourceToAllTargets(
    AgentResourceKind resource,
  ) async {
    return _run(resource, null, () async {
      final targets = resource.supportedTargets.toList();
      if (targets.isEmpty) {
        throw StateError('${resource.label} 没有可同步的客户端');
      }

      var pulledFiles = 0;
      var deployedFiles = 0;
      var packageCount = 0;
      final parts = <String>[];
      var allOk = true;

      for (final target in targets) {
        try {
          final one = await _doSyncOne(resource, target);
          pulledFiles += one.pulledFiles;
          deployedFiles += one.deployedFiles;
          packageCount += one.packageCount;
          parts.add(one.message);
        } catch (error) {
          allOk = false;
          parts.add('${target.label}：失败（$error）');
          debugPrint('${resource.label} 同步 ${target.label} 失败: $error');
        }
      }

      return SkillSyncResult(
        ok: allOk,
        pulledFiles: pulledFiles,
        deployedFiles: deployedFiles,
        packageCount: packageCount,
        message: parts.join('；'),
      );
    });
  }

  /// 把本机目标目录内容上传到 WebDAV（先复制到缓存再推送）。
  Future<SkillSyncResult> pushToWebDav(SkillTarget target) async {
    return pushResourceToWebDav(AgentResourceKind.skill, target);
  }

  Future<SkillSyncResult> pushResourceToWebDav(
    AgentResourceKind resource,
    SkillTarget target,
  ) async {
    return _run(resource, target, () => _doPushOne(resource, target));
  }

  /// 把该资源支持的全部本机客户端目录上传到 WebDAV（一次忙状态）。
  Future<SkillSyncResult> pushResourceToAllTargets(
    AgentResourceKind resource,
  ) async {
    return _run(resource, null, () async {
      final targets = resource.supportedTargets.toList();
      if (targets.isEmpty) {
        throw StateError('${resource.label} 没有可上传的客户端');
      }

      var pushedFiles = 0;
      var packageCount = 0;
      final parts = <String>[];
      var allOk = true;

      for (final target in targets) {
        try {
          final one = await _doPushOne(resource, target);
          pushedFiles += one.pushedFiles;
          packageCount += one.packageCount;
          parts.add(one.message);
        } catch (error) {
          allOk = false;
          parts.add('${target.label}：失败（$error）');
          debugPrint('${resource.label} 上传 ${target.label} 失败: $error');
        }
      }

      return SkillSyncResult(
        ok: allOk,
        pushedFiles: pushedFiles,
        packageCount: packageCount,
        message: parts.join('；'),
      );
    });
  }

  /// 仅把本机缓存复制到客户端目录（不访问 WebDAV）。
  Future<SkillSyncResult> deployFromCache(SkillTarget target) async {
    return _run(AgentResourceKind.skill, target, () async {
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

  Future<SkillSyncResult> _doSyncOne(
    AgentResourceKind resource,
    SkillTarget target,
  ) async {
    final config = await _loadConfig();
    if (!config.enabled || !config.isConfigured) {
      throw StateError('请先配置并启用 WebDAV');
    }
    final cachePath = resourceCachePathFor(resource, target);
    final deployPath = resourceDeployPathFor(resource, target);
    if (cachePath == null || deployPath == null) {
      throw StateError('${target.label} 不支持 ${resource.label} 同步');
    }

    final client = _folderSync.clientFor(config);
    if (client == null) {
      throw StateError('WebDAV 未配置完整');
    }

    final remote = _folderSync.remoteResourceDir(
      config,
      resource.wireName,
      target.wireName,
    );
    final pulled = await _folderSync.pullFolder(
      client: client,
      remoteDir: remote,
      localDir: cachePath,
    );
    final deploy = await _folderCopy.copyContents(
      sourceDir: cachePath,
      targetDir: deployPath,
    );
    final packages = resource == AgentResourceKind.skill
        ? await _folderCopy.countSkillPackages(deployPath)
        : 0;

    return SkillSyncResult(
      ok: true,
      target: target,
      pulledFiles: pulled,
      deployedFiles: deploy.copiedFiles,
      packageCount: packages,
      message: '已同步 ${target.label} ${resource.label}：'
          '拉取 $pulled 个文件，部署 ${deploy.copiedFiles} 个文件'
          '${resource == AgentResourceKind.skill ? '（约 $packages 个 Skill 包）' : ''}'
          ' → $deployPath',
    );
  }

  Future<SkillSyncResult> _doPushOne(
    AgentResourceKind resource,
    SkillTarget target,
  ) async {
    final config = await _loadConfig();
    if (!config.enabled || !config.isConfigured) {
      throw StateError('请先配置并启用 WebDAV');
    }
    final cachePath = resourceCachePathFor(resource, target);
    final deployPath = resourceDeployPathFor(resource, target);
    if (cachePath == null || deployPath == null) {
      throw StateError('${target.label} 不支持 ${resource.label} 同步');
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

    final remote = _folderSync.remoteResourceDir(
      config,
      resource.wireName,
      target.wireName,
    );
    final pushed = await _folderSync.pushFolder(
      client: client,
      remoteDir: remote,
      localDir: cachePath,
    );
    final packages = resource == AgentResourceKind.skill
        ? await _folderCopy.countSkillPackages(cachePath)
        : 0;

    return SkillSyncResult(
      ok: true,
      target: target,
      pushedFiles: pushed,
      packageCount: packages,
      message: '已上传 ${target.label} ${resource.label}：$pushed 个文件'
          '${resource == AgentResourceKind.skill ? '（约 $packages 个 Skill 包）' : ''}'
          ' → $remote',
    );
  }

  Future<SkillSyncResult> _run(
    AgentResourceKind resource,
    SkillTarget? target,
    Future<SkillSyncResult> Function() action,
  ) async {
    if (status == SkillSyncStatus.syncing) {
      return const SkillSyncResult(
        ok: false,
        message: '配置同步进行中，请稍候',
      );
    }

    status = SkillSyncStatus.syncing;
    lastTarget = target;
    lastResource = resource;
    lastError = null;
    notifyListeners();

    try {
      final result = await action();
      lastMessage = result.message;
      lastSyncedAt = DateTime.now();
      lastError = result.ok ? null : result.message;
      status = result.ok ? SkillSyncStatus.success : SkillSyncStatus.error;
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
