import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../common/agent_platforms.dart';
import '../../common/package_time.dart';
import '../../common/sync_progress.dart';
import '../../common/writable_temp.dart';
import '../../services/mcp_paths.dart';
import '../../webdav/package_version_store.dart';
import '../../webdav/webdav_config.dart';
import 'agent_resource_kind.dart';
import 'convert/cursor_to_codex_agents_converter.dart';
import 'convert/cursor_to_codex_hooks_converter.dart';
import 'convert/cursor_to_codex_skill_converter.dart';
import 'convert/cursor_to_opencode_converter.dart';
import 'cursor_hooks_bundle.dart';
import 'resource_conversion.dart';
import 'skill_folder_copy.dart';
import 'skill_sync_result.dart';
import 'skill_target.dart';
import 'skill_webdav_folder_sync.dart';

export 'skill_sync_result.dart';

/// Agent 资源同步：
/// - 下载：远端固定名 zip 解压覆盖到本机缓存（不碰正式目录）
/// - 合并：远端 zip 解压后合并复制到缓存（覆盖同名，不删本地多余项）
/// - 覆盖：缓存 → 正式 Cursor
/// - 上传：正式 Cursor 打成固定名 zip 覆盖远端
/// - 转换：正式 Cursor → Codex / OpenCode
class SkillSyncService extends ChangeNotifier {
  SkillSyncService({
    required Future<WebDavConfig> Function() loadConfig,
    SkillWebDavFolderSync? folderSync,
    SkillFolderCopy? folderCopy,
    CursorToCodexSkillConverter? skillConverter,
    CursorToCodexAgentsConverter? agentsConverter,
    CursorToOpenCodeConverter? openCodeConverter,
    CursorToCodexHooksConverter? hooksConverter,
    CursorHooksBundle? hooksBundle,
    PackageVersionStore? versionStore,
  }) : _loadConfig = loadConfig,
       _folderSync = folderSync ?? SkillWebDavFolderSync(),
       _folderCopy = folderCopy ?? const SkillFolderCopy(),
       _hooksBundle = hooksBundle ?? const CursorHooksBundle(),
       _conversion = ResourceConversion(
         skillConverter: skillConverter ?? const CursorToCodexSkillConverter(),
         agentsConverter:
             agentsConverter ?? const CursorToCodexAgentsConverter(),
         openCodeConverter:
             openCodeConverter ?? const CursorToOpenCodeConverter(),
         hooksConverter: hooksConverter ?? const CursorToCodexHooksConverter(),
       ),
       _versionStore = versionStore ?? PackageVersionStore();
  final Future<WebDavConfig> Function() _loadConfig;
  final SkillWebDavFolderSync _folderSync;
  final SkillFolderCopy _folderCopy;
  final CursorHooksBundle _hooksBundle;
  final ResourceConversion _conversion;
  final PackageVersionStore _versionStore;

  SkillSyncStatus status = SkillSyncStatus.idle;
  String? lastError;
  String? lastMessage;
  DateTime? lastSyncedAt;
  final Map<AgentResourceKind, DateTime> packageUploadedAt = {};
  SkillTarget? lastTarget;
  AgentResourceKind? lastResource;
  SyncProgress? progress;
  String? bulkFailure;
  final Map<AgentResourceKind, String> resourceFailures = {};
  DateTime? _progressStamp;
  static const _codexNotOnWebDavMessage =
      'WebDAV only downloads/uploads Cursor directories; Codex / OpenCode files are generated locally from Cursor. '
      'Use “One-click conversion”, or first “Apply to Cursor” from the cache.';
  String? cachePathFor(SkillTarget target) => switch (target) {
    SkillTarget.cursor => McpPaths.cursorSkillsCachePath,
    SkillTarget.codex => McpPaths.codexSkillsCachePath,
    SkillTarget.openCode => McpPaths.openCodeSkillsPath,
  };
  String? deployPathFor(SkillTarget target) => switch (target) {
    SkillTarget.cursor => McpPaths.cursorSkillsPath,
    SkillTarget.codex => McpPaths.codexSkillsPath,
    SkillTarget.openCode => McpPaths.openCodeSkillsPath,
  };
  String? resourceCachePathFor(
    AgentResourceKind resource,
    SkillTarget target,
  ) => McpPaths.resourceCachePath(resource.wireName, target.wireName);
  String? resourceDeployPathFor(
    AgentResourceKind resource,
    SkillTarget target,
  ) => switch ((resource, target)) {
    (AgentResourceKind.skill, SkillTarget.cursor) => McpPaths.cursorSkillsPath,
    (AgentResourceKind.skill, SkillTarget.codex) => McpPaths.codexSkillsPath,
    (AgentResourceKind.command, SkillTarget.cursor) =>
      McpPaths.cursorCommandsPath,
    (AgentResourceKind.command, SkillTarget.codex) =>
      McpPaths.codexCommandsPath,
    (AgentResourceKind.rule, SkillTarget.cursor) => McpPaths.cursorRulesPath,
    (AgentResourceKind.rule, SkillTarget.codex) => McpPaths.codexRulesPath,
    (AgentResourceKind.skill, SkillTarget.openCode) =>
      McpPaths.openCodeSkillsPath,
    (AgentResourceKind.rule, SkillTarget.openCode) =>
      McpPaths.openCodeConfigDirectory,
    (AgentResourceKind.command, SkillTarget.openCode) =>
      McpPaths.openCodeCommandsPath,
    (AgentResourceKind.hook, SkillTarget.cursor) => McpPaths.cursorHooksPath,
    (AgentResourceKind.hook, SkillTarget.codex) => McpPaths.codexHooksPath,
    (AgentResourceKind.hook, SkillTarget.openCode) => null,
  };

  DateTime? uploadedAtFor(AgentResourceKind resource) =>
      packageUploadedAt[resource];

  void hydratePackageUploadedAt(Map<String, DateTime> times) {
    packageUploadedAt.clear();
    for (final kind in AgentResourceKind.values) {
      final time = times[kind.wireName];
      if (time != null) packageUploadedAt[kind] = time;
    }
  }

  Future<DateTime?> peekRemoteUploadedAt(AgentResourceKind resource) async {
    final config = await _loadConfig();
    if (!config.enabled || !config.isConfigured) return null;
    final client = _folderSync.clientFor(config);
    if (client == null) return null;
    return _folderSync.peekRemoteUploadedAt(
      client: client,
      config: config,
      resourceWireName: resource.wireName,
    );
  }

  /// 从 WebDAV 下载 Cursor Skill 到本机缓存（不覆盖正式目录）。
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
    return _run(
      resource,
      target,
      () => _doSyncOne(resource, target),
      activity: 'Download',
    );
  }

  /// 从 WebDAV 下载 Cursor 到本机缓存（压缩包解压后覆盖缓存）。
  Future<SkillSyncResult> syncResourceToAllTargets(
    AgentResourceKind resource,
  ) async {
    return _forEachWebDavTarget(
      resource: resource,
      activity: 'Download',
      emptyMessage: 'No client can download ${resource.label}',
      each: _doSyncOne,
    );
  }

  /// 从 WebDAV 合并 Cursor 资源到本机缓存（压缩包解压后合并复制）。
  Future<SkillSyncResult> mergeResourceFromWebDav(
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
    return _run(
      resource,
      target,
      () => _doMergeOne(resource, target),
      activity: 'Merge',
    );
  }

  Future<SkillSyncResult> mergeResourceToAllTargets(
    AgentResourceKind resource,
  ) async {
    return _forEachWebDavTarget(
      resource: resource,
      activity: 'Merge',
      emptyMessage: 'No client can merge ${resource.label}',
      each: _doMergeOne,
    );
  }

  /// 把本机 Cursor 正式目录全量镜像上传到 WebDAV（不经缓存）。
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
    return _run(
      resource,
      target,
      () => _doPushOne(resource, target),
      activity: 'Upload',
    );
  }

  /// 把该资源的本机 Cursor 目录打成固定名 zip 覆盖上传。
  Future<SkillSyncResult> pushResourceToAllTargets(
    AgentResourceKind resource,
  ) async {
    return _forEachWebDavTarget(
      resource: resource,
      activity: 'Upload',
      emptyMessage: 'No client can upload ${resource.label}',
      each: _doPushOne,
    );
  }

  /// 一次性从 WebDAV 下载全部 Agent 资源到本机缓存（压缩包覆盖缓存）。
  Future<SkillSyncResult> syncAllResourcesFromWebDav() async {
    return _forEachWebDavTarget(
      resource: null,
      activity: 'Download',
      emptyMessage: 'No resources can be downloaded',
      each: _doSyncOne,
    );
  }

  /// 一次性从 WebDAV 合并全部 Agent 资源到本机缓存。
  Future<SkillSyncResult> mergeAllResourcesFromWebDav() async {
    return _forEachWebDavTarget(
      resource: null,
      activity: 'Merge',
      emptyMessage: 'No resources can be merged',
      each: _doMergeOne,
    );
  }

  /// 一次性把全部 Agent 资源打成固定名 zip 覆盖上传（不经缓存）。
  Future<SkillSyncResult> pushAllResourcesToWebDav() async {
    return _forEachWebDavTarget(
      resource: null,
      activity: 'Upload',
      emptyMessage: 'No resources can be uploaded',
      each: _doPushOne,
    );
  }

  /// 仅把本机 Skill 缓存全量镜像到客户端正式目录（不访问 WebDAV）。
  Future<SkillSyncResult> deployFromCache(SkillTarget target) async {
    return applyResourceFromCache(AgentResourceKind.skill, target: target);
  }

  /// 把缓存全量镜像到正式 Cursor（不自动转换；请用「一键转换」）。
  Future<SkillSyncResult> applyResourceFromCache(
    AgentResourceKind resource, {
    SkillTarget target = SkillTarget.cursor,
  }) async {
    if (!resource.supportsWebDav(target) && target != SkillTarget.cursor) {
      return SkillSyncResult(
        ok: false,
        target: target,
        message: _codexNotOnWebDavMessage,
      );
    }
    return _run(
      resource,
      target,
      () => _doApplyOne(resource, target),
      activity: 'Apply',
    );
  }

  /// 把全部资源的 Cursor 缓存全量镜像到正式目录（不自动转换）。
  Future<SkillSyncResult> applyAllResourcesFromCache() async {
    return _forEachWebDavTarget(
      resource: null,
      activity: 'Apply',
      emptyMessage: 'No resources can be applied',
      each: _doApplyOne,
    );
  }

  /// 以本机 Cursor 目录为源，转换单个资源到指定目标。
  ///
  /// 不依赖 WebDAV，也不读取缓存。Skill 整包镜像后再按目标格式转换
  ///（Codex：`agents/openai.yaml`；OpenCode：`SKILL.md` frontmatter）；
  /// Rule → `AGENTS.md`。Command 暂无 Codex 对等目录。
  Future<SkillSyncResult> convertFromCursor(
    AgentResourceKind resource, {
    SkillTarget target = SkillTarget.codex,
  }) async {
    return _run(resource, target, () async {
      if (!McpPaths.isDesktopSupported) {
        throw StateError(
          'Directory conversion is not supported on this platform',
        );
      }
      if (target == SkillTarget.openCode) {
        return _conversion.convertOpenCode(resource);
      }
      if (!target.hasConfirmedConversionFormat) {
        return _unsupportedTarget(target);
      }
      return _conversion.convertCodex(resource);
    }, activity: 'Convert');
  }

  /// 以本机 Cursor 正式目录为源，转换单个资源到全部可转换目标（不碰缓存）。
  Future<SkillSyncResult> convertResourceToAllTargets(
    AgentResourceKind resource,
  ) async {
    return _run(resource, SkillTarget.cursor, () async {
      if (!McpPaths.isDesktopSupported) {
        throw StateError(
          'Directory conversion is not supported on this platform',
        );
      }
      return _convertResourceToTargets(resource);
    }, activity: 'Convert');
  }

  Future<SkillSyncResult> _convertResourceToTargets(
    AgentResourceKind resource,
  ) async {
    final parts = <String>[];
    var deployedFiles = 0;
    var packageCount = 0;
    var allOk = true;

    if (resource.canConvertToCodex) {
      try {
        final codex = await _conversion.convertCodex(resource);
        deployedFiles += codex.deployedFiles;
        packageCount += codex.packageCount;
        parts.add(codex.message);
        if (!codex.ok) allOk = false;
      } catch (error) {
        allOk = false;
        parts.add('Codex: failed ($error)');
        debugPrint('${resource.label} 转换 Codex 失败: $error');
      }
    }

    if (resource.canConvertTo(SkillTarget.openCode)) {
      try {
        final openCode = await _conversion.convertOpenCode(resource);
        deployedFiles += openCode.deployedFiles;
        packageCount += openCode.packageCount;
        parts.add(openCode.message);
        if (!openCode.ok) allOk = false;
      } catch (error) {
        allOk = false;
        parts.add('OpenCode: failed ($error)');
        debugPrint('${resource.label} 转换 Open Code 失败: $error');
      }
    }

    if (parts.isEmpty) {
      return SkillSyncResult(
        ok: false,
        target: SkillTarget.cursor,
        message: 'No conversion target is available for ${resource.label}',
      );
    }
    return SkillSyncResult(
      ok: allOk,
      target: SkillTarget.cursor,
      deployedFiles: deployedFiles,
      packageCount: packageCount,
      message: parts.join('；'),
    );
  }

  /// 一键转换全部可转换资源（Skill / Rule / Command / Hook → Codex / Open Code）。
  Future<SkillSyncResult> convertAllFromCursor() async {
    return _run(null, SkillTarget.cursor, () async {
      if (!McpPaths.isDesktopSupported) {
        throw StateError(
          'Directory conversion is not supported on this platform',
        );
      }
      var deployedFiles = 0;
      var packageCount = 0;
      final parts = <String>[];
      var allOk = true;
      for (final resource in AgentResourceKind.values) {
        if (!resource.canConvertToCodex &&
            !resource.canConvertTo(SkillTarget.openCode)) {
          continue;
        }
        try {
          final one = await _convertResourceToTargets(resource);
          deployedFiles += one.deployedFiles;
          packageCount += one.packageCount;
          parts.add(one.message);
          if (!one.ok) allOk = false;
        } catch (error) {
          allOk = false;
          parts.add('${resource.label}: failed ($error)');
          debugPrint('转换全部 ${resource.label} 失败: $error');
        }
      }
      return SkillSyncResult(
        ok: allOk,
        target: SkillTarget.cursor,
        deployedFiles: deployedFiles,
        packageCount: packageCount,
        message: parts.isEmpty
            ? 'No resources can be converted'
            : parts.join('; '),
      );
    }, activity: 'Convert');
  }

  SkillSyncResult _unsupportedTarget(SkillTarget target) => SkillSyncResult(
    ok: false,
    target: target,
    message:
        'No converter is available for ${target.label}; no files were written',
  );

  /// 仅下载到缓存目录：用远端压缩包覆盖缓存，不触碰正式配置。
  Future<SkillSyncResult> _doSyncOne(
    AgentResourceKind resource,
    SkillTarget target,
  ) async {
    final config = await _loadConfig();
    if (!config.enabled || !config.isConfigured) {
      throw StateError('Configure and enable WebDAV first');
    }
    final cachePath = resourceCachePathFor(resource, target);
    if (cachePath == null) {
      throw StateError('${target.label} 不支持 ${resource.label} 下载');
    }
    final client = _folderSync.clientFor(config);
    if (client == null) {
      throw StateError('WebDAV is not fully configured');
    }
    final pulled = await _folderSync.pullFolder(
      client: client,
      config: config,
      resourceWireName: resource.wireName,
      targetWireName: target.wireName,
      localDir: cachePath,
      onProgress: (done, total) =>
          _reportProgress('Downloading ${resource.label}', done, total),
    );
    await _rememberPackageUploadedAt(resource, pulled.uploadedAt);
    final packages = resource == AgentResourceKind.skill
        ? await _folderCopy.countSkillPackages(cachePath)
        : 0;
    final versionHint = pulled.uploadedAt == null
        ? ''
        : ' (remote version ${formatPackageTime(pulled.uploadedAt)})';
    return SkillSyncResult(
      ok: true,
      target: target,
      pulledFiles: pulled.fileCount,
      packageCount: packages,
      message:
          'Downloaded the Cursor ${resource.label} archive to the cache: '
          '${pulled.fileCount} files'
          '${resource == AgentResourceKind.skill ? ' (about $packages Skill packages)' : ''}'
          '$versionHint'
          ' → $cachePath (official directory unchanged; use “Apply to Cursor”)',
    );
  }

  /// 下载压缩包后合并到缓存（覆盖同名，不删除缓存中多余项）。
  Future<SkillSyncResult> _doMergeOne(
    AgentResourceKind resource,
    SkillTarget target,
  ) async {
    final config = await _loadConfig();
    if (!config.enabled || !config.isConfigured) {
      throw StateError('Configure and enable WebDAV first');
    }
    final cachePath = resourceCachePathFor(resource, target);
    if (cachePath == null) {
      throw StateError('${target.label} 不支持 ${resource.label} 合并');
    }
    final client = _folderSync.clientFor(config);
    if (client == null) {
      throw StateError('WebDAV 未配置完整');
    }
    final merged = await _folderSync.mergeFolder(
      client: client,
      config: config,
      resourceWireName: resource.wireName,
      targetWireName: target.wireName,
      localDir: cachePath,
      onProgress: (done, total) =>
          _reportProgress('Merging ${resource.label}', done, total),
    );
    await _rememberPackageUploadedAt(resource, merged.uploadedAt);
    final packages = resource == AgentResourceKind.skill
        ? await _folderCopy.countSkillPackages(cachePath)
        : 0;
    final versionHint = merged.uploadedAt == null
        ? ''
        : ' (remote version ${formatPackageTime(merged.uploadedAt)})';
    return SkillSyncResult(
      ok: true,
      target: target,
      pulledFiles: merged.fileCount,
      packageCount: packages,
      message:
          'Merged Cursor ${resource.label} into the cache: '
          '${merged.fileCount} files written'
          '${resource == AgentResourceKind.skill ? ' (about $packages Skill packages)' : ''}'
          '$versionHint'
          ' → $cachePath (extra cache items were kept; official directory unchanged)',
    );
  }

  /// 把缓存全量镜像到正式目录（本地多余也会删除）。
  Future<SkillSyncResult> _doApplyOne(
    AgentResourceKind resource,
    SkillTarget target,
  ) async {
    if (!McpPaths.isDesktopSupported) {
      throw StateError(
        'Directory application is not supported on this platform',
      );
    }
    final cachePath = resourceCachePathFor(resource, target);
    if (cachePath == null) {
      throw StateError('${target.label} 不支持 ${resource.label} 覆盖');
    }
    await Directory(cachePath).create(recursive: true);

    if (resource == AgentResourceKind.hook) {
      final layout = CursorHooksLayout.cursorUser();
      if (layout == null) {
        throw StateError('Hook application is not supported on this platform');
      }
      final deploy = await _hooksBundle.applyToLayout(
        bundleDir: cachePath,
        layout: layout,
      );
      return SkillSyncResult(
        ok: true,
        target: target,
        deployedFiles: deploy.copiedFiles,
        message:
            'Applied cached Cursor Hook files (hooks.json and hooks/): '
            '${deploy.copiedFiles} files written, ${deploy.deletedEntries} extra items removed'
            ' → ${layout.hooksJsonPath}'
            ' (Codex not converted; use “One-click conversion”)',
      );
    }

    final deployPath = resourceDeployPathFor(resource, target);
    if (deployPath == null) {
      throw StateError('${target.label} 不支持 ${resource.label} 覆盖');
    }
    final deploy = await _folderCopy.mirrorContents(
      sourceDir: cachePath,
      targetDir: deployPath,
    );
    final packages = resource == AgentResourceKind.skill
        ? await _folderCopy.countSkillPackages(deployPath)
        : 0;
    return SkillSyncResult(
      ok: true,
      target: target,
      deployedFiles: deploy.copiedFiles,
      packageCount: packages,
      message:
          'Applied the cached Cursor ${resource.label}: '
          '${deploy.copiedFiles} files written, ${deploy.deletedEntries} extra items removed'
          '${resource == AgentResourceKind.skill ? ' (about $packages Skill packages)' : ''}'
          ' → $deployPath'
          ' (Codex / OpenCode not converted; use “One-click conversion”)',
    );
  }

  /// 直接从本机 Cursor 正式目录上传到远端（缓存只用于下载暂存，不参与上传）。
  Future<SkillSyncResult> _doPushOne(
    AgentResourceKind resource,
    SkillTarget target,
  ) async {
    final config = await _loadConfig();
    if (!config.enabled || !config.isConfigured) {
      throw StateError('Configure and enable WebDAV first');
    }
    Directory? staging;
    late final String localDir;
    if (resource == AgentResourceKind.hook) {
      final layout = CursorHooksLayout.cursorUser();
      if (layout == null) {
        throw StateError('Hook upload is not supported on this platform');
      }
      staging = await WritableTemp.createDir('mcp_hub_hooks_push');
      await _hooksBundle.exportFromLayout(
        layout: layout,
        bundleDir: staging.path,
      );
      localDir = staging.path;
    } else {
      final deployPath = resourceDeployPathFor(resource, target);
      if (deployPath == null) {
        throw StateError('${target.label} 不支持 ${resource.label} 上传');
      }
      // 正式目录不存在时创建空目录再上传，使远端与「空的本机 Cursor」一致。
      await Directory(deployPath).create(recursive: true);
      localDir = deployPath;
    }
    try {
      final client = _folderSync.clientFor(config);
      if (client == null) {
        throw StateError('WebDAV 未配置完整');
      }
      final remoteZip = _folderSync.remoteResourceZip(
        config,
        resource.wireName,
      );
      final pushed = await _folderSync.pushFolder(
        client: client,
        config: config,
        resourceWireName: resource.wireName,
        localDir: localDir,
        onProgress: (done, total) =>
            _reportProgress('Uploading ${resource.label}', done, total),
      );
      final uploadedAt = DateTime.now().toUtc();
      await _rememberPackageUploadedAt(resource, uploadedAt);
      final packages = resource == AgentResourceKind.skill
          ? await _folderCopy.countSkillPackages(localDir)
          : 0;
      return SkillSyncResult(
        ok: true,
        target: target,
        pushedFiles: pushed,
        packageCount: packages,
        message:
            'Packaged and uploaded ${resource.label} from the official Cursor directory: $pushed files'
            '${resource == AgentResourceKind.skill ? ' (about $packages Skill packages)' : ''}'
            ' (version ${formatPackageTime(uploadedAt)})'
            ' → $remoteZip (same-name archive replaced)',
      );
    } finally {
      if (staging != null) {
        try {
          if (await staging.exists()) await staging.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  Future<SkillSyncResult> _forEachWebDavTarget({
    required AgentResourceKind? resource,
    required String activity,
    required String emptyMessage,
    required Future<SkillSyncResult> Function(
      AgentResourceKind resource,
      SkillTarget target,
    )
    each,
  }) async {
    return _run(resource, null, () async {
      final kinds = resource == null ? AgentResourceKind.values : [resource];
      var pulledFiles = 0;
      var pushedFiles = 0;
      var deployedFiles = 0;
      var packageCount = 0;
      final parts = <String>[];
      var allOk = true;
      var any = false;
      for (final kind in kinds) {
        for (final target in kind.webDavTargets) {
          any = true;
          try {
            final one = await each(kind, target);
            pulledFiles += one.pulledFiles;
            pushedFiles += one.pushedFiles;
            deployedFiles += one.deployedFiles;
            packageCount += one.packageCount;
            parts.add(one.message);
            if (!one.ok) allOk = false;
            _rememberResourceOutcome(kind, one.ok, one.message);
          } catch (error) {
            allOk = false;
            parts.add('${kind.label}/${target.label}: failed ($error)');
            debugPrint('$activity ${kind.label} ${target.label} 失败: $error');
            _rememberResourceOutcome(kind, false, '$error');
          }
        }
      }
      return SkillSyncResult(
        ok: allOk,
        pulledFiles: pulledFiles,
        pushedFiles: pushedFiles,
        deployedFiles: deployedFiles,
        packageCount: packageCount,
        message: !any || parts.isEmpty ? emptyMessage : parts.join('；'),
      );
    }, activity: activity);
  }

  Future<SkillSyncResult> _run(
    AgentResourceKind? resource,
    SkillTarget? target,
    Future<SkillSyncResult> Function() action, {
    String activity = 'Sync',
  }) async {
    if (status == SkillSyncStatus.syncing) {
      return const SkillSyncResult(
        ok: false,
        message: 'A configuration transfer is already in progress; please wait',
      );
    }
    status = SkillSyncStatus.syncing;
    lastTarget = target;
    lastResource = resource;
    lastError = null;
    progress = SyncProgress(
      label: '$activity ${resource?.label ?? 'all resources'}',
    );
    notifyListeners();
    try {
      final result = await action();
      lastMessage = result.message;
      lastSyncedAt = DateTime.now();
      lastError = result.ok ? null : result.message;
      status = result.ok ? SkillSyncStatus.success : SkillSyncStatus.error;
      _rememberOutcome(resource, result.ok, result.message);
      progress = null;
      notifyListeners();
      return result;
    } catch (error) {
      lastError = '$error';
      lastMessage = lastError;
      status = SkillSyncStatus.error;
      _rememberOutcome(resource, false, lastError!);
      progress = null;
      debugPrint('Skill 下载/上传失败: $error');
      notifyListeners();
      return SkillSyncResult(ok: false, target: target, message: lastError!);
    }
  }

  String? failureFor(AgentResourceKind? resource) {
    if (resource == null) return bulkFailure;
    return resourceFailures[resource];
  }

  void _rememberOutcome(AgentResourceKind? resource, bool ok, String message) {
    if (resource == null) {
      bulkFailure = ok ? null : message;
      return;
    }
    _rememberResourceOutcome(resource, ok, message);
  }

  void _rememberResourceOutcome(
    AgentResourceKind resource,
    bool ok,
    String message,
  ) {
    if (ok) {
      resourceFailures.remove(resource);
    } else {
      resourceFailures[resource] = message;
    }
  }

  Future<void> _rememberPackageUploadedAt(
    AgentResourceKind resource,
    DateTime? time,
  ) async {
    if (time == null) return;
    packageUploadedAt[resource] = time;
    await _versionStore.save(resource.wireName, time);
  }

  void _reportProgress(String label, int done, int total) {
    progress = SyncProgress(label: label, current: done, total: total);
    final now = DateTime.now();
    if (done == 0 ||
        done == total ||
        _progressStamp == null ||
        now.difference(_progressStamp!) >= const Duration(milliseconds: 100)) {
      _progressStamp = now;
      notifyListeners();
    }
  }
}
