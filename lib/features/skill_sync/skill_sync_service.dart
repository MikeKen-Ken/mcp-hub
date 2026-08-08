import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../services/mcp_paths.dart';
import '../../webdav/webdav_config.dart';
import 'agent_resource_kind.dart';
import 'convert/cursor_to_codex_agents_converter.dart';
import 'convert/cursor_to_codex_skill_converter.dart';
import 'skill_folder_copy.dart';
import 'skill_target.dart';
import 'skill_webdav_folder_sync.dart';

enum SkillSyncStatus { idle, syncing, success, error }

/// 一次 Skill 下载/上传的结果摘要。
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

/// Agent 资源：WebDAV 仅下载 Cursor → 本机缓存 → 部署；
/// 下载成功后对本机执行 Cursor→Codex 转换（Skill / Rule）。
class SkillSyncService extends ChangeNotifier {
  SkillSyncService({
    required Future<WebDavConfig> Function() loadConfig,
    SkillWebDavFolderSync? folderSync,
    SkillFolderCopy? folderCopy,
    CursorToCodexSkillConverter? skillConverter,
    CursorToCodexAgentsConverter? agentsConverter,
  })  : _loadConfig = loadConfig,
        _folderSync = folderSync ?? SkillWebDavFolderSync(),
        _folderCopy = folderCopy ?? const SkillFolderCopy(),
        _skillConverter =
            skillConverter ?? const CursorToCodexSkillConverter(),
        _agentsConverter =
            agentsConverter ?? const CursorToCodexAgentsConverter();
  final Future<WebDavConfig> Function() _loadConfig;
  final SkillWebDavFolderSync _folderSync;
  final SkillFolderCopy _folderCopy;
  final CursorToCodexSkillConverter _skillConverter;
  final CursorToCodexAgentsConverter _agentsConverter;

  SkillSyncStatus status = SkillSyncStatus.idle;
  String? lastError;
  String? lastMessage;
  DateTime? lastSyncedAt;
  SkillTarget? lastTarget;
  AgentResourceKind? lastResource;
  static const _codexNotOnWebDavMessage =
      'WebDAV 仅下载/上传 Cursor 目录；Codex 由本机从 Cursor 转换生成，'
      '请使用「一键转换」或先下载 Cursor（下载后会自动转换）';
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
  /// 从 WebDAV 下载并复制到目标客户端 Skill 目录。
  Future<SkillSyncResult> syncFromWebDav(SkillTarget target) async {
    return syncResourceFromWebDav(AgentResourceKind.skill, target);
  }

  Future<SkillSyncResult> syncResourceFromWebDav(
    AgentResourceKind resource,
    SkillTarget target,
  ) async {
    if (!resource.supportsWebDav(target)) {
      return SkillSyncResult(
        ok: false,
        target: target,
        message: _codexNotOnWebDavMessage,
      );
    }
    return _run(resource, target, () => _doSyncOne(resource, target));
  }

  /// 从 WebDAV 下载 Cursor 并部署；可转换资源会接着生成本机 Codex。
  Future<SkillSyncResult> syncResourceToAllTargets(
    AgentResourceKind resource,
  ) async {
    return _run(resource, null, () async {
      final targets = resource.webDavTargets.toList();
      if (targets.isEmpty) {
        throw StateError('${resource.label} 没有可下载的客户端');
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
          if (!one.ok) allOk = false;
        } catch (error) {
          allOk = false;
          parts.add('${target.label}：失败（$error）');
          debugPrint('${resource.label} 下载 ${target.label} 失败: $error');
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
    if (!resource.supportsWebDav(target)) {
      return SkillSyncResult(
        ok: false,
        target: target,
        message: _codexNotOnWebDavMessage,
      );
    }
    return _run(resource, target, () => _doPushOne(resource, target));
  }

  /// 把该资源的本机 Cursor 目录上传到 WebDAV（一次忙状态）。
  Future<SkillSyncResult> pushResourceToAllTargets(
    AgentResourceKind resource,
  ) async {
    return _run(resource, null, () async {
      final targets = resource.webDavTargets.toList();
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
          if (!one.ok) allOk = false;
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

  /// 一次性从 WebDAV 下载全部 Agent 资源（仅 Cursor），并自动转换到 Codex。
  Future<SkillSyncResult> syncAllResourcesFromWebDav() async {
    return _run(null, null, () async {
      var pulledFiles = 0;
      var deployedFiles = 0;
      var packageCount = 0;
      final parts = <String>[];
      var allOk = true;
      for (final resource in AgentResourceKind.values) {
        for (final target in resource.webDavTargets) {
          try {
            final one = await _doSyncOne(resource, target);
            pulledFiles += one.pulledFiles;
            deployedFiles += one.deployedFiles;
            packageCount += one.packageCount;
            parts.add(one.message);
            if (!one.ok) allOk = false;
          } catch (error) {
            allOk = false;
            parts.add('${resource.label}/${target.label}：失败（$error）');
            debugPrint('整体下载 ${resource.label} ${target.label} 失败: $error');
          }
        }
      }
      return SkillSyncResult(
        ok: allOk,
        pulledFiles: pulledFiles,
        deployedFiles: deployedFiles,
        packageCount: packageCount,
        message: parts.isEmpty ? '没有可下载的资源' : parts.join('；'),
      );
    });
  }

  /// 一次性把全部 Agent 资源的本机 Cursor 目录上传到 WebDAV。
  Future<SkillSyncResult> pushAllResourcesToWebDav() async {
    return _run(null, null, () async {
      var pushedFiles = 0;
      var packageCount = 0;
      final parts = <String>[];
      var allOk = true;
      for (final resource in AgentResourceKind.values) {
        for (final target in resource.webDavTargets) {
          try {
            final one = await _doPushOne(resource, target);
            pushedFiles += one.pushedFiles;
            packageCount += one.packageCount;
            parts.add(one.message);
            if (!one.ok) allOk = false;
          } catch (error) {
            allOk = false;
            parts.add('${resource.label}/${target.label}：失败（$error）');
            debugPrint('整体上传 ${resource.label} ${target.label} 失败: $error');
          }
        }
      }
      return SkillSyncResult(
        ok: allOk,
        pushedFiles: pushedFiles,
        packageCount: packageCount,
        message: parts.isEmpty ? '没有可上传的资源' : parts.join('；'),
      );
    });
  }

  /// 仅把本机缓存复制到客户端目录（不访问 WebDAV）。
  Future<SkillSyncResult> deployFromCache(SkillTarget target) async {
    return _run(AgentResourceKind.skill, target, () async {
      final cachePath = cachePathFor(target);
      final deployPath = deployPathFor(target);
      if (cachePath == null || deployPath == null) {
        throw StateError('当前平台不支持 Skill 下载/上传');
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

  /// 以本机 Cursor 目录为源，批量转换成 Codex 可接受的格式。
  ///
  /// 不依赖 WebDAV。Skill → skills + openai.yaml；Rule → `AGENTS.md`。
  /// Command 暂无 Codex 对等目录。
  Future<SkillSyncResult> convertFromCursor(AgentResourceKind resource) async {
    return _run(resource, SkillTarget.cursor, () async {
      if (!McpPaths.isDesktopSupported) {
        throw StateError('当前平台不支持目录转换');
      }
      return switch (resource) {
        AgentResourceKind.skill => _convertSkillsFromCursor(),
        AgentResourceKind.rule => _convertRulesFromCursor(),
        AgentResourceKind.command => const SkillSyncResult(
            ok: false,
            target: SkillTarget.cursor,
            message: 'Command 暂无 Codex 对等目录，无法一键转换',
          ),
      };
    });
  }

  /// 一键转换全部可转换资源（Skill + Rule）。
  Future<SkillSyncResult> convertAllFromCursor() async {
    return _run(null, SkillTarget.cursor, () async {
      if (!McpPaths.isDesktopSupported) {
        throw StateError('当前平台不支持目录转换');
      }
      var deployedFiles = 0;
      var packageCount = 0;
      final parts = <String>[];
      var allOk = true;
      for (final resource in AgentResourceKind.values) {
        if (!resource.canConvertToCodex) continue;
        try {
          final one = switch (resource) {
            AgentResourceKind.skill => await _convertSkillsFromCursor(),
            AgentResourceKind.rule => await _convertRulesFromCursor(),
            AgentResourceKind.command => const SkillSyncResult(
                ok: false,
                message: 'Command 暂无 Codex 对等目录',
              ),
          };
          deployedFiles += one.deployedFiles;
          packageCount += one.packageCount;
          parts.add(one.message);
          if (!one.ok) allOk = false;
        } catch (error) {
          allOk = false;
          parts.add('${resource.label}：失败（$error）');
          debugPrint('转换全部 ${resource.label} 失败: $error');
        }
      }
      return SkillSyncResult(
        ok: allOk,
        target: SkillTarget.codex,
        deployedFiles: deployedFiles,
        packageCount: packageCount,
        message: parts.isEmpty ? '没有可转换的资源' : parts.join('；'),
      );
    });
  }

  Future<SkillSyncResult> _convertSkillsFromCursor() async {
    final source = McpPaths.cursorSkillsPath;
    final target = McpPaths.codexSkillsPath;
    if (source == null || target == null) {
      throw StateError('当前平台不支持 Skill 转换');
    }
    final sourceDir = Directory(source);
    if (!await sourceDir.exists()) {
      return SkillSyncResult(
        ok: true,
        target: SkillTarget.codex,
        message: 'Cursor Skill 目录不存在，跳过转换 → $source',
      );
    }
    final items = await _skillConverter.convertAll(
      cursorSkillsDir: source,
      codexSkillsDir: target,
    );
    final copied = items.fold<int>(0, (sum, e) => sum + e.copiedFiles);
    return SkillSyncResult(
      ok: true,
      target: SkillTarget.codex,
      deployedFiles: copied,
      packageCount: items.length,
      message: items.isEmpty
          ? 'Cursor Skill 目录为空，未转换任何包 → $target'
          : '已从 Cursor 批量转换 ${items.length} 个 Skill 到 Codex'
              '（复制 $copied 个文件，并写入 agents/openai.yaml）→ $target',
    );
  }

  Future<SkillSyncResult> _convertRulesFromCursor() async {
    final source = McpPaths.cursorRulesPath;
    final target = McpPaths.codexAgentsMdPath;
    if (source == null || target == null) {
      throw StateError('当前平台不支持 Rule 转换');
    }
    final sourceDir = Directory(source);
    if (!await sourceDir.exists()) {
      return SkillSyncResult(
        ok: true,
        target: SkillTarget.codex,
        message: 'Cursor Rule 目录不存在，跳过转换 → $source',
      );
    }
    final items = await _agentsConverter.convertAll(
      cursorRulesDir: source,
      agentsMdPath: target,
    );
    return SkillSyncResult(
      ok: true,
      target: SkillTarget.codex,
      deployedFiles: items.length,
      packageCount: items.length,
      message: items.isEmpty
          ? 'Cursor Rule 目录为空，已生成空的 AGENTS.md → $target'
          : '已从 Cursor 批量转换 ${items.length} 条 Rule 到 Codex AGENTS.md → $target',
    );
  }

  /// 下载 Cursor 成功后，对本机执行可转换资源的 Cursor→Codex。
  Future<SkillSyncResult> _maybeConvertAfterCursorSync(
    AgentResourceKind resource,
    SkillSyncResult syncResult,
  ) async {
    if (!resource.canConvertToCodex) return syncResult;
    try {
      final convert = switch (resource) {
        AgentResourceKind.skill => await _convertSkillsFromCursor(),
        AgentResourceKind.rule => await _convertRulesFromCursor(),
        AgentResourceKind.command => syncResult,
      };
      if (identical(convert, syncResult)) return syncResult;
      return SkillSyncResult(
        ok: syncResult.ok && convert.ok,
        target: SkillTarget.cursor,
        pulledFiles: syncResult.pulledFiles,
        deployedFiles: syncResult.deployedFiles + convert.deployedFiles,
        packageCount: syncResult.packageCount + convert.packageCount,
        message: '${syncResult.message}；${convert.message}',
      );
    } catch (error) {
      debugPrint('${resource.label} 下载后转换 Codex 失败: $error');
      return SkillSyncResult(
        ok: false,
        target: SkillTarget.cursor,
        pulledFiles: syncResult.pulledFiles,
        deployedFiles: syncResult.deployedFiles,
        packageCount: syncResult.packageCount,
        message: '${syncResult.message}；Cursor→Codex 转换失败：$error',
      );
    }
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
      throw StateError('${target.label} 不支持 ${resource.label} 下载');
    }
    final client = _folderSync.clientFor(config);
    if (client == null) {
      throw StateError('WebDAV 未配置完整');
    }
    // 远端仅 Cursor；旧的 .../codex/ 目录不再下载。
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
    final syncResult = SkillSyncResult(
      ok: true,
      target: target,
      pulledFiles: pulled,
      deployedFiles: deploy.copiedFiles,
      packageCount: packages,
      message: '已下载 Cursor ${resource.label}：'
          '下载 $pulled 个文件，部署 ${deploy.copiedFiles} 个文件'
          '${resource == AgentResourceKind.skill ? '（约 $packages 个 Skill 包）' : ''}'
          ' → $deployPath',
    );
    if (target == SkillTarget.cursor) {
      return _maybeConvertAfterCursorSync(resource, syncResult);
    }
    return syncResult;
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
      throw StateError('${target.label} 不支持 ${resource.label} 上传');
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
    // 仅上传到 .../cursor/；不再写入远端 .../codex/。
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
      message: '已上传 Cursor ${resource.label}：$pushed 个文件'
          '${resource == AgentResourceKind.skill ? '（约 $packages 个 Skill 包）' : ''}'
          ' → $remote',
    );
  }

  Future<SkillSyncResult> _run(
    AgentResourceKind? resource,
    SkillTarget? target,
    Future<SkillSyncResult> Function() action,
  ) async {
    if (status == SkillSyncStatus.syncing) {
      return const SkillSyncResult(
        ok: false,
        message: '配置下载/上传进行中，请稍候',
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
      debugPrint('Skill 下载/上传失败: $error');
      notifyListeners();
      return SkillSyncResult(
        ok: false,
        target: target,
        message: lastError!,
      );
    }
  }
}
