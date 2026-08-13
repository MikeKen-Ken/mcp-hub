import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../common/agent_platforms.dart';
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

/// Agent 资源同步：
/// - 下载：远端 Cursor → 本机缓存（不碰正式目录）
/// - 覆盖：缓存 → 正式 Cursor
/// - 上传：正式 Cursor → 远端（不经缓存）
/// - 转换：正式 Cursor → Codex / OpenCode
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
      'WebDAV 仅下载/上传 Cursor 目录；Codex / Open Code 由本机从 Cursor 转换生成，'
      '请使用「一键转换」或先将缓存「应用到 Cursor」';
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

  /// 一次性把全部 Agent 资源的本机 Cursor 正式目录直接上传到 WebDAV（不经缓存）。
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
    return _run(resource, target, () => _doApplyOne(resource, target));
  }

  /// 把全部资源的 Cursor 缓存全量镜像到正式目录（不自动转换）。
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

  /// 以本机 Cursor 正式目录为源，转换单个资源到全部可转换目标（不碰缓存）。
  Future<SkillSyncResult> convertResourceToAllTargets(
    AgentResourceKind resource,
  ) async {
    return _run(resource, SkillTarget.cursor, () async {
      if (!McpPaths.isDesktopSupported) {
        throw StateError('当前平台不支持目录转换');
      }
      final parts = <String>[];
      var deployedFiles = 0;
      var packageCount = 0;
      var allOk = true;

      if (resource.canConvertToCodex) {
        try {
          final codex = switch (resource) {
            AgentResourceKind.skill => await _convertSkillsFromCursor(),
            AgentResourceKind.rule => await _convertRulesFromCursor(),
            AgentResourceKind.command => const SkillSyncResult(
              ok: false,
              message: 'Command 暂无 Codex 对等目录',
            ),
          };
          deployedFiles += codex.deployedFiles;
          packageCount += codex.packageCount;
          parts.add(codex.message);
          if (!codex.ok) allOk = false;
        } catch (error) {
          allOk = false;
          parts.add('Codex：失败（$error）');
          debugPrint('${resource.label} 转换 Codex 失败: $error');
        }
      }

      if (resource.canConvertTo(SkillTarget.openCode)) {
        try {
          final openCode = await _convertOpenCodeFromCursor(resource);
          deployedFiles += openCode.deployedFiles;
          packageCount += openCode.packageCount;
          parts.add(openCode.message);
          if (!openCode.ok) allOk = false;
        } catch (error) {
          allOk = false;
          parts.add('Open Code：失败（$error）');
          debugPrint('${resource.label} 转换 Open Code 失败: $error');
        }
      }

      if (parts.isEmpty) {
        return SkillSyncResult(ok: false, message: '${resource.label} 暂无可转换目标');
      }
      return SkillSyncResult(
        ok: allOk,
        target: SkillTarget.cursor,
        deployedFiles: deployedFiles,
        packageCount: packageCount,
        message: parts.join('；'),
      );
    });
  }

  /// 一键转换全部可转换资源（Skill + Rule + Command → Codex / Open Code）。
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
        if (!resource.canConvertToCodex &&
            !resource.canConvertTo(SkillTarget.openCode)) {
          continue;
        }
        try {
          // 避免嵌套 _run：直接组合单资源转换逻辑
          final oneParts = <String>[];
          var oneOk = true;
          var oneDeployed = 0;
          var onePackages = 0;
          if (resource.canConvertToCodex) {
            final codex = switch (resource) {
              AgentResourceKind.skill => await _convertSkillsFromCursor(),
              AgentResourceKind.rule => await _convertRulesFromCursor(),
              AgentResourceKind.command => const SkillSyncResult(
                ok: true,
                message: 'Command 跳过 Codex',
              ),
            };
            if (resource != AgentResourceKind.command) {
              oneDeployed += codex.deployedFiles;
              onePackages += codex.packageCount;
              oneParts.add(codex.message);
              if (!codex.ok) oneOk = false;
            }
          }
          if (resource.canConvertTo(SkillTarget.openCode)) {
            final openCode = await _convertOpenCodeFromCursor(resource);
            oneDeployed += openCode.deployedFiles;
            onePackages += openCode.packageCount;
            oneParts.add(openCode.message);
            if (!openCode.ok) oneOk = false;
          }
          deployedFiles += oneDeployed;
          packageCount += onePackages;
          parts.addAll(oneParts);
          if (!oneOk) allOk = false;
        } catch (error) {
          allOk = false;
          parts.add('${resource.label}：失败（$error）');
          debugPrint('转换全部 ${resource.label} 失败: $error');
        }
      }
      return SkillSyncResult(
        ok: allOk,
        target: SkillTarget.cursor,
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

    return switch (resource) {
      AgentResourceKind.skill => await _convertOpenCodeSkills(
        cursorSkillsPath,
        openCodeSkillsPath,
      ),
      AgentResourceKind.rule => await _convertOpenCodeRules(
        cursorRulesPath,
        openCodeRulesPath,
      ),
      AgentResourceKind.command => await _convertOpenCodeCommands(
        cursorCommandsPath,
        openCodeCommandsPath,
      ),
    };
  }

  Future<SkillSyncResult> _convertOpenCodeSkills(
    String source,
    String target,
  ) async {
    final sourceDir = Directory(source);
    if (!await sourceDir.exists()) {
      return SkillSyncResult(
        ok: true,
        target: SkillTarget.openCode,
        message: 'Cursor Skill 目录不存在，跳过转换 → $source',
      );
    }
    final skills = await _openCodeConverter.convertSkills(
      sourceDir: source,
      targetDir: target,
    );
    final removeHint = skills.removedPackages == 0
        ? ''
        : '，并删除多余 ${skills.removedPackages} 个包';
    final extraHint = skills.deletedEntries == 0
        ? ''
        : '，包内删除 ${skills.deletedEntries} 项';
    return SkillSyncResult(
      ok: true,
      target: SkillTarget.openCode,
      deployedFiles: skills.copiedFiles,
      packageCount: skills.packages,
      message: skills.packages == 0
          ? 'Cursor Skill 目录为空，未转换任何包$removeHint → $target'
          : '已从 Cursor 批量转换 ${skills.packages} 个 Skill 到 Open Code'
                '（复制 ${skills.copiedFiles} 个文件$extraHint$removeHint）→ $target',
    );
  }

  Future<SkillSyncResult> _convertOpenCodeRules(
    String source,
    String target,
  ) async {
    final sourceDir = Directory(source);
    if (!await sourceDir.exists()) {
      return SkillSyncResult(
        ok: true,
        target: SkillTarget.openCode,
        message: 'Cursor Rule 目录不存在，跳过转换 → $source',
      );
    }
    final count = await _openCodeConverter.convertRules(
      sourceDir: source,
      targetPath: target,
    );
    return SkillSyncResult(
      ok: true,
      target: SkillTarget.openCode,
      deployedFiles: count,
      packageCount: 0,
      message: count == 0
          ? 'Cursor Rule 目录为空，已生成空的 AGENTS.md → $target'
          : '已从 Cursor 批量转换 $count 条 Rule 到 Open Code AGENTS.md → $target',
    );
  }

  Future<SkillSyncResult> _convertOpenCodeCommands(
    String source,
    String target,
  ) async {
    final sourceDir = Directory(source);
    if (!await sourceDir.exists()) {
      return SkillSyncResult(
        ok: true,
        target: SkillTarget.openCode,
        message: 'Cursor Command 目录不存在，跳过转换 → $source',
      );
    }
    final commands = await _openCodeConverter.convertCommands(
      sourceDir: source,
      targetDir: target,
    );
    final deleteHint = commands.deleted == 0
        ? ''
        : '，并删除多余 ${commands.deleted} 项';
    return SkillSyncResult(
      ok: true,
      target: SkillTarget.openCode,
      deployedFiles: commands.written,
      packageCount: 0,
      message:
          '已从 Cursor 转换 Open Code Command：${commands.written} 个'
          '$deleteHint → $target',
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
    final converted = await _skillConverter.convertAll(
      cursorSkillsDir: source,
      codexSkillsDir: target,
    );
    final copied = converted.items.fold<int>(
      0,
      (sum, e) => sum + e.copiedFiles,
    );
    final deletedInPacks = converted.items.fold<int>(
      0,
      (sum, e) => sum + e.deletedEntries,
    );
    final removed = converted.removedPackages;
    final removeHint = removed == 0 ? '' : '，并删除多余 $removed 个包';
    final extraHint = deletedInPacks == 0 ? '' : '，包内删除 $deletedInPacks 项';
    return SkillSyncResult(
      ok: true,
      target: SkillTarget.codex,
      deployedFiles: copied,
      packageCount: converted.items.length,
      message: converted.items.isEmpty
          ? 'Cursor Skill 目录为空，未转换任何包$removeHint → $target'
          : '已从 Cursor 批量转换 ${converted.items.length} 个 Skill 到 Codex'
                '（复制 $copied 个文件，并写入 agents/openai.yaml'
                '$extraHint$removeHint）→ $target',
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
          ' → $cachePath（未写入正式目录，请使用「应用到 Cursor」）',
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
    return SkillSyncResult(
      ok: true,
      target: target,
      deployedFiles: deploy.copiedFiles,
      packageCount: packages,
      message:
          '已用缓存全量覆盖正式 Cursor ${resource.label}：'
          '写入 ${deploy.copiedFiles} 个文件，删除多余 ${deploy.deletedEntries} 项'
          '${resource == AgentResourceKind.skill ? '（约 $packages 个 Skill 包）' : ''}'
          ' → $deployPath'
          '（未转换 Codex / Open Code，请使用「一键转换」）',
    );
  }

  /// 直接从本机 Cursor 正式目录上传到远端（缓存只用于下载暂存，不参与上传）。
  Future<SkillSyncResult> _doPushOne(
    AgentResourceKind resource,
    SkillTarget target,
  ) async {
    final config = await _loadConfig();
    if (!config.enabled || !config.isConfigured) {
      throw StateError('请先配置并启用 WebDAV');
    }
    final deployPath = resourceDeployPathFor(resource, target);
    if (deployPath == null) {
      throw StateError('${target.label} 不支持 ${resource.label} 上传');
    }
    // 正式目录不存在时创建空目录再上传，使远端与「空的本机 Cursor」一致。
    await Directory(deployPath).create(recursive: true);
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
      localDir: deployPath,
    );
    final packages = resource == AgentResourceKind.skill
        ? await _folderCopy.countSkillPackages(deployPath)
        : 0;
    return SkillSyncResult(
      ok: true,
      target: target,
      pushedFiles: pushed,
      packageCount: packages,
      message:
          '已从 Cursor 正式目录全量上传 ${resource.label}：$pushed 个文件'
          '${resource == AgentResourceKind.skill ? '（约 $packages 个 Skill 包）' : ''}'
          ' → $remote（远端已与本机 Cursor 一致）',
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
