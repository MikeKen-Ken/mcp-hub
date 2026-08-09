import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../services/mcp_paths.dart';
import '../../webdav/webdav_config.dart';
import 'agent_resource_kind.dart';
import 'convert/cursor_to_codex_agents_converter.dart';
import 'convert/cursor_to_codex_skill_converter.dart';
import 'convert/cursor_to_opencode_converter.dart';
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

/// Agent 资源：WebDAV 仅下载 Cursor → 本机缓存；
/// 「更新/覆盖」再把缓存全量镜像到正式目录，并可转换 Codex。
class SkillSyncService extends ChangeNotifier {
  SkillSyncService({
    required Future<WebDavConfig> Function() loadConfig,
    SkillWebDavFolderSync? folderSync,
    SkillFolderCopy? folderCopy,
    CursorToCodexSkillConverter? skillConverter,
    CursorToCodexAgentsConverter? agentsConverter,
    CursorToOpenCodeConverter? openCodeConverter,
  }) : _loadConfig = loadConfig,
       _folderSync = folderSync ?? SkillWebDavFolderSync(),
       _folderCopy = folderCopy ?? const SkillFolderCopy(),
       _skillConverter = skillConverter ?? const CursorToCodexSkillConverter(),
       _agentsConverter =
           agentsConverter ?? const CursorToCodexAgentsConverter(),
       _openCodeConverter =
           openCodeConverter ?? const CursorToOpenCodeConverter();
  final Future<WebDavConfig> Function() _loadConfig;
  final SkillWebDavFolderSync _folderSync;
  final SkillFolderCopy _folderCopy;
  final CursorToCodexSkillConverter _skillConverter;
  final CursorToCodexAgentsConverter _agentsConverter;
  final CursorToOpenCodeConverter _openCodeConverter;

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
  };

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
    return _run(resource, target, () => _doSyncOne(resource, target));
  }

  /// 从 WebDAV 下载 Cursor 到本机缓存（不覆盖正式目录）。
  Future<SkillSyncResult> syncResourceToAllTargets(
    AgentResourceKind resource,
  ) async {
    return _run(resource, null, () async {
      final targets = resource.webDavTargets.toList();
      if (targets.isEmpty) {
        throw StateError('${resource.label} 没有可下载的客户端');
      }
      var pulledFiles = 0;
      var packageCount = 0;
      final parts = <String>[];
      var allOk = true;
      for (final target in targets) {
        try {
          final one = await _doSyncOne(resource, target);
          pulledFiles += one.pulledFiles;
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
        packageCount: packageCount,
        message: parts.join('；'),
      );
    });
  }

  /// 把本机目标目录全量镜像上传到 WebDAV（先镜像到缓存再推送）。
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

  /// 一次性从 WebDAV 下载全部 Agent 资源到本机缓存（仅 Cursor，不覆盖正式目录）。
  Future<SkillSyncResult> syncAllResourcesFromWebDav() async {
    return _run(null, null, () async {
      var pulledFiles = 0;
      var packageCount = 0;
      final parts = <String>[];
      var allOk = true;
      for (final resource in AgentResourceKind.values) {
        for (final target in resource.webDavTargets) {
          try {
            final one = await _doSyncOne(resource, target);
            pulledFiles += one.pulledFiles;
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
        packageCount: packageCount,
        message: parts.isEmpty ? '没有可下载的资源' : parts.join('；'),
      );
    });
  }

  /// 一次性把全部 Agent 资源的本机 Cursor 目录全量镜像上传到 WebDAV。
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

  /// 仅把本机 Skill 缓存全量镜像到客户端正式目录（不访问 WebDAV）。
  Future<SkillSyncResult> deployFromCache(SkillTarget target) async {
    return applyResourceFromCache(AgentResourceKind.skill, target: target);
  }

  /// 把缓存全量镜像到正式目录；Cursor 侧完成后可自动转换 Codex。
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
    return _run(resource, target, () => _doApplyOne(resource, target));
  }

  /// 把全部资源的 Cursor 缓存全量镜像到正式目录，并可转换 Codex。
  Future<SkillSyncResult> applyAllResourcesFromCache() async {
    return _run(null, null, () async {
      var deployedFiles = 0;
      var packageCount = 0;
      final parts = <String>[];
      var allOk = true;
      for (final resource in AgentResourceKind.values) {
        for (final target in resource.webDavTargets) {
          try {
            final one = await _doApplyOne(resource, target);
            deployedFiles += one.deployedFiles;
            packageCount += one.packageCount;
            parts.add(one.message);
            if (!one.ok) allOk = false;
          } catch (error) {
            allOk = false;
            parts.add('${resource.label}/${target.label}：失败（$error）');
            debugPrint('整体覆盖 ${resource.label} ${target.label} 失败: $error');
          }
        }
      }
      return SkillSyncResult(
        ok: allOk,
        deployedFiles: deployedFiles,
        packageCount: packageCount,
        message: parts.isEmpty ? '没有可覆盖的资源' : parts.join('；'),
      );
    });
  }

  /// 以本机 Cursor 目录为源，批量转换成 Codex 可接受的格式。
  ///
  /// 不依赖 WebDAV。Skill → skills + openai.yaml；Rule → `AGENTS.md`。
  /// Command 暂无 Codex 对等目录。
  Future<SkillSyncResult> convertFromCursor(
    AgentResourceKind resource, {
    SkillTarget target = SkillTarget.codex,
  }) async {
    return _run(resource, target, () async {
      if (!McpPaths.isDesktopSupported) {
        throw StateError('当前平台不支持目录转换');
      }
      if (target == SkillTarget.openCode) {
        return _convertOpenCodeFromCursor(resource);
      }
      if (!target.hasConfirmedConversionFormat) {
        return _unsupportedTarget(target);
      }
      return switch (resource) {
        AgentResourceKind.skill => _convertSkillsFromCursor(),
        AgentResourceKind.rule => _convertRulesFromCursor(),
        AgentResourceKind.command => SkillSyncResult(
          ok: false,
          target: target,
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
      final openCodeSkillsPath = McpPaths.openCodeSkillsPath;
      final openCodeRulesPath = McpPaths.openCodeRulesPath;
      final openCodeCommandsPath = McpPaths.openCodeCommandsPath;
      if (openCodeSkillsPath == null ||
          openCodeRulesPath == null ||
          openCodeCommandsPath == null) {
        throw StateError('当前平台不支持 OpenCode 转换');
      }
      final cursorSkillsPath = McpPaths.cursorSkillsPath;
      final cursorRulesPath = McpPaths.cursorRulesPath;
      final cursorCommandsPath = McpPaths.cursorCommandsPath;
      if (cursorSkillsPath == null ||
          cursorRulesPath == null ||
          cursorCommandsPath == null) {
        throw StateError('当前平台不支持 Cursor 转换');
      }
      final openCode = await _openCodeConverter.convertAll(
        cursorSkillsDir: cursorSkillsPath,
        cursorRulesDir: cursorRulesPath,
        cursorCommandsDir: cursorCommandsPath,
        openCodeSkillsDir: openCodeSkillsPath,
        openCodeAgentsMdPath: openCodeRulesPath,
        openCodeCommandsDir: openCodeCommandsPath,
      );
      deployedFiles += openCode.total;
      parts.add(
        '已转换 Open Code：Skill ${openCode.skills} 个、Rule ${openCode.rules} 条、'
        'Command ${openCode.commands} 个',
      );
      return SkillSyncResult(
        ok: allOk,
        target: SkillTarget.codex,
        deployedFiles: deployedFiles,
        packageCount: packageCount,
        message: parts.isEmpty ? '没有可转换的资源' : parts.join('；'),
      );
    });
  }

  SkillSyncResult _unsupportedTarget(SkillTarget target) => SkillSyncResult(
    ok: false,
    target: target,
    message: '${target.label} 暂无可用转换器，未写入任何文件',
  );

  Future<SkillSyncResult> _convertOpenCodeFromCursor(
    AgentResourceKind resource,
  ) async {
    final openCodeSkillsPath = McpPaths.openCodeSkillsPath;
    final openCodeRulesPath = McpPaths.openCodeRulesPath;
    final openCodeCommandsPath = McpPaths.openCodeCommandsPath;
    if (openCodeSkillsPath == null ||
        openCodeRulesPath == null ||
        openCodeCommandsPath == null) {
      throw StateError('当前平台不支持 OpenCode 转换');
    }
    final cursorSkillsPath = McpPaths.cursorSkillsPath;
    final cursorRulesPath = McpPaths.cursorRulesPath;
    final cursorCommandsPath = McpPaths.cursorCommandsPath;
    if (cursorSkillsPath == null ||
        cursorRulesPath == null ||
        cursorCommandsPath == null) {
      throw StateError('当前平台不支持 Cursor 转换');
    }
    final result = await _openCodeConverter.convertAll(
      cursorSkillsDir: cursorSkillsPath,
      cursorRulesDir: cursorRulesPath,
      cursorCommandsDir: cursorCommandsPath,
      openCodeSkillsDir: openCodeSkillsPath,
      openCodeAgentsMdPath: openCodeRulesPath,
      openCodeCommandsDir: openCodeCommandsPath,
    );
    final count = switch (resource) {
      AgentResourceKind.skill => result.skills,
      AgentResourceKind.rule => result.rules,
      AgentResourceKind.command => result.commands,
    };
    return SkillSyncResult(
      ok: true,
      target: SkillTarget.openCode,
      deployedFiles: count,
      packageCount: result.skills,
      message:
          '已转换 Open Code ${resource.label}：$count 个 → '
          '${McpPaths.openCodeConfigDirectory}',
    );
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
    final removed = await _removeStaleSkillPackages(
      sourceSkillsDir: source,
      targetSkillsDir: target,
    );
    final copied = items.fold<int>(0, (sum, e) => sum + e.copiedFiles);
    final removeHint = removed == 0 ? '' : '，并删除多余 $removed 个包';
    return SkillSyncResult(
      ok: true,
      target: SkillTarget.codex,
      deployedFiles: copied,
      packageCount: items.length,
      message: items.isEmpty
          ? 'Cursor Skill 目录为空，未转换任何包$removeHint → $target'
          : '已从 Cursor 批量转换 ${items.length} 个 Skill 到 Codex'
                '（复制 $copied 个文件，并写入 agents/openai.yaml$removeHint）→ $target',
    );
  }

  /// 删除目标侧已不在源目录中的 Skill 包（跳过点开头目录）。
  Future<int> _removeStaleSkillPackages({
    required String sourceSkillsDir,
    required String targetSkillsDir,
  }) async {
    final targetRoot = Directory(targetSkillsDir);
    if (!await targetRoot.exists()) return 0;

    final keepNames = <String>{};
    final sourceRoot = Directory(sourceSkillsDir);
    if (await sourceRoot.exists()) {
      await for (final entity in sourceRoot.list(followLinks: false)) {
        if (entity is! Directory) continue;
        final name = p.basename(entity.path);
        if (name.startsWith('.')) continue;
        final skillMd = File(p.join(entity.path, 'SKILL.md'));
        if (await skillMd.exists()) keepNames.add(name);
      }
    }

    var removed = 0;
    await for (final entity in targetRoot.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final name = p.basename(entity.path);
      if (name.startsWith('.')) continue;
      final skillMd = File(p.join(entity.path, 'SKILL.md'));
      if (!await skillMd.exists()) continue;
      if (keepNames.contains(name)) continue;
      await entity.delete(recursive: true);
      removed += 1;
      debugPrint('已删除 Codex 多余 Skill 包：$name');
    }
    return removed;
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

  /// 覆盖正式目录后，对本机执行可转换资源的 Cursor→Codex。
  Future<SkillSyncResult> _maybeConvertAfterCursorApply(
    AgentResourceKind resource,
    SkillSyncResult applyResult,
  ) async {
    if (!resource.canConvertToCodex) return applyResult;
    try {
      final convert = switch (resource) {
        AgentResourceKind.skill => await _convertSkillsFromCursor(),
        AgentResourceKind.rule => await _convertRulesFromCursor(),
        AgentResourceKind.command => applyResult,
      };
      if (identical(convert, applyResult)) return applyResult;
      return SkillSyncResult(
        ok: applyResult.ok && convert.ok,
        target: SkillTarget.cursor,
        pulledFiles: applyResult.pulledFiles,
        deployedFiles: applyResult.deployedFiles + convert.deployedFiles,
        packageCount: applyResult.packageCount + convert.packageCount,
        message: '${applyResult.message}；${convert.message}',
      );
    } catch (error) {
      debugPrint('${resource.label} 覆盖后转换 Codex 失败: $error');
      return SkillSyncResult(
        ok: false,
        target: SkillTarget.cursor,
        pulledFiles: applyResult.pulledFiles,
        deployedFiles: applyResult.deployedFiles,
        packageCount: applyResult.packageCount,
        message: '${applyResult.message}；Cursor→Codex 转换失败：$error',
      );
    }
  }

  /// 仅下载到缓存目录：与远端全量一致，不触碰正式配置。
  Future<SkillSyncResult> _doSyncOne(
    AgentResourceKind resource,
    SkillTarget target,
  ) async {
    final config = await _loadConfig();
    if (!config.enabled || !config.isConfigured) {
      throw StateError('请先配置并启用 WebDAV');
    }
    final cachePath = resourceCachePathFor(resource, target);
    if (cachePath == null) {
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
    final packages = resource == AgentResourceKind.skill
        ? await _folderCopy.countSkillPackages(cachePath)
        : 0;
    return SkillSyncResult(
      ok: true,
      target: target,
      pulledFiles: pulled,
      packageCount: packages,
      message:
          '已下载 Cursor ${resource.label} 到缓存：'
          '$pulled 个文件'
          '${resource == AgentResourceKind.skill ? '（约 $packages 个 Skill 包）' : ''}'
          ' → $cachePath（未覆盖正式目录，请使用「更新/覆盖」）',
    );
  }

  /// 把缓存全量镜像到正式目录（本地多余也会删除）。
  Future<SkillSyncResult> _doApplyOne(
    AgentResourceKind resource,
    SkillTarget target,
  ) async {
    if (!McpPaths.isDesktopSupported) {
      throw StateError('当前平台不支持目录覆盖');
    }
    final cachePath = resourceCachePathFor(resource, target);
    final deployPath = resourceDeployPathFor(resource, target);
    if (cachePath == null || deployPath == null) {
      throw StateError('${target.label} 不支持 ${resource.label} 覆盖');
    }
    await Directory(cachePath).create(recursive: true);
    final deploy = await _folderCopy.mirrorContents(
      sourceDir: cachePath,
      targetDir: deployPath,
    );
    final packages = resource == AgentResourceKind.skill
        ? await _folderCopy.countSkillPackages(deployPath)
        : 0;
    final applyResult = SkillSyncResult(
      ok: true,
      target: target,
      deployedFiles: deploy.copiedFiles,
      packageCount: packages,
      message:
          '已用缓存全量覆盖正式 Cursor ${resource.label}：'
          '写入 ${deploy.copiedFiles} 个文件，删除多余 ${deploy.deletedEntries} 项'
          '${resource == AgentResourceKind.skill ? '（约 $packages 个 Skill 包）' : ''}'
          ' → $deployPath',
    );
    if (target == SkillTarget.cursor) {
      return _maybeConvertAfterCursorApply(resource, applyResult);
    }
    return applyResult;
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
    // 以正式目录为准全量镜像到缓存；若尚无正式目录则确保缓存存在后推送。
    final deployDir = Directory(deployPath);
    if (await deployDir.exists()) {
      await _folderCopy.mirrorContents(
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
    // 仅上传到 .../cursor/；全量镜像，远端多余项也会删除。
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
      message:
          '已全量上传 Cursor ${resource.label}：$pushed 个文件'
          '${resource == AgentResourceKind.skill ? '（约 $packages 个 Skill 包）' : ''}'
          ' → $remote（远端已与本机一致）',
    );
  }

  Future<SkillSyncResult> _run(
    AgentResourceKind? resource,
    SkillTarget? target,
    Future<SkillSyncResult> Function() action,
  ) async {
    if (status == SkillSyncStatus.syncing) {
      return const SkillSyncResult(ok: false, message: '配置下载/上传进行中，请稍候');
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
      return SkillSyncResult(ok: false, target: target, message: lastError!);
    }
  }
}
