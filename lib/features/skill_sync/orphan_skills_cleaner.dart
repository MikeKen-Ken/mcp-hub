import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../common/agent_platforms.dart';
import '../../services/mcp_paths.dart';
import '../../services/mcp_repo_service.dart';
import 'agent_resource_kind.dart';
import 'convert/managed_skills_manifest.dart';
import 'convert/skill_md_document.dart';
import 'convert/standard_skill_frontmatter.dart';
import 'skill_target.dart';

/// 某个多余 Skill 在单个目标端的位置信息。
class OrphanSkillLocation {
  const OrphanSkillLocation({
    required this.target,
    required this.path,
    this.isManagedByHub = false,
  });

  final SkillTarget target;
  final String path;
  final bool isManagedByHub;
}

/// 聚合后的单个多余 Skill 项（可能同时存在于多个目标端）。
class OrphanSkillEntry {
  const OrphanSkillEntry({
    required this.name,
    required this.locations,
    this.description,
  });

  final String name;
  final List<OrphanSkillLocation> locations;
  final String? description;

  bool get anyManagedByHub => locations.any((loc) => loc.isManagedByHub);
}

/// 扫描各目标端相对于 Cursor 主源的多余 Skill 结果。
class OrphanSkillScanResult {
  const OrphanSkillScanResult({
    required this.entries,
    required this.obsoleteCodexCacheExists,
    this.obsoleteCodexCachePath,
  });

  final List<OrphanSkillEntry> entries;
  final bool obsoleteCodexCacheExists;
  final String? obsoleteCodexCachePath;

  bool get isEmpty => entries.isEmpty && !obsoleteCodexCacheExists;
}

/// 执行勾选清理后的汇总结果。
class OrphanSkillDeleteResult {
  const OrphanSkillDeleteResult({
    required this.deletedSkillCount,
    required this.deletedDirectoryCount,
    required this.deletedObsoleteCodexCache,
    this.errors = const [],
  });

  final int deletedSkillCount;
  final int deletedDirectoryCount;
  final bool deletedObsoleteCodexCache;
  final List<String> errors;

  bool get ok => errors.isEmpty;
}

/// 扫描并清理各目标端中“已不在 Cursor 主源”的多余 Skill 目录（以及废弃 Codex 缓存）。
///
/// 绝不扫描 `.` 开头的系统目录（如 Codex `.system`）或 `.mcp-hub-managed.json`；
/// 只在用户确认勾选后删除指定目录，避免误删客户端自带或市场安装的 Skill。
class OrphanSkillsCleaner {
  const OrphanSkillsCleaner();

  static const _targetOrder = <SkillTarget>[
    SkillTarget.codex,
    SkillTarget.openCode,
    SkillTarget.deepSeekHarness,
    SkillTarget.workBuddy,
    SkillTarget.workBuddyAi,
    SkillTarget.antigravity,
    SkillTarget.doubao,
  ];

  /// 扫描所有受支持的客户端目录，返回不在 Cursor 中的多余 Skill 与旧版 Codex 缓存状态。
  Future<OrphanSkillScanResult> scan({
    String? cursorSkillsDir,
    Map<SkillTarget, String>? targetSkillDirs,
    String? obsoleteCodexCacheDir,
  }) async {
    final sourceDir = cursorSkillsDir ?? McpPaths.cursorSkillsPath;
    final sourceNames = await _collectCursorSkillNames(sourceDir);

    final targets = targetSkillDirs ?? _defaultTargetDirs();
    final grouped = <String, _MutableOrphanGroup>{};

    for (final target in _targetOrder) {
      final dirPath = targets[target];
      if (dirPath == null || dirPath.trim().isEmpty) continue;
      final dir = Directory(dirPath);
      if (!await dir.exists()) continue;

      final acceptedNames = _usesKebabFolderNames(target)
          ? sourceNames.kebabOrRaw
          : sourceNames.raw;
      final managedNames = await _readManagedNames(dirPath);

      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! Directory) continue;
        final name = p.basename(entity.path);
        if (name.startsWith('.')) continue;
        if (acceptedNames.contains(name)) continue;

        final group = grouped.putIfAbsent(
          name,
          () => _MutableOrphanGroup(name: name),
        );
        group.locations.add(
          OrphanSkillLocation(
            target: target,
            path: entity.path,
            isManagedByHub: managedNames.contains(name),
          ),
        );
        group.description ??= await _readSkillDescription(entity.path);
      }
    }

    final entries = grouped.values
        .map(
          (g) => OrphanSkillEntry(
            name: g.name,
            locations: List.unmodifiable(g.locations),
            description: g.description,
          ),
        )
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final cacheDir = obsoleteCodexCacheDir ?? McpPaths.codexSkillsCachePath;
    final cacheExists =
        cacheDir != null &&
        cacheDir.trim().isNotEmpty &&
        await Directory(cacheDir).exists();

    return OrphanSkillScanResult(
      entries: entries,
      obsoleteCodexCacheExists: cacheExists,
      obsoleteCodexCachePath: cacheExists ? cacheDir : null,
    );
  }

  /// 删除用户勾选的 [selectedEntries] 所在目标端目录，并按需清理废弃的 Codex 缓存。
  Future<OrphanSkillDeleteResult> deleteSelected({
    required List<OrphanSkillEntry> selectedEntries,
    String? deleteObsoleteCodexCachePath,
  }) async {
    var deletedSkills = 0;
    var deletedDirs = 0;
    var deletedCache = false;
    final errors = <String>[];

    for (final entry in selectedEntries) {
      var anyDeletedForSkill = false;
      for (final loc in entry.locations) {
        final dir = Directory(loc.path);
        if (!await dir.exists()) continue;
        try {
          await McpRepoService.deleteDirectoryResilient(dir);
          deletedDirs += 1;
          anyDeletedForSkill = true;
        } catch (error) {
          errors.add('${entry.name} (${AgentPlatforms.labelOf(loc.target)}): $error');
        }
      }
      if (anyDeletedForSkill) {
        deletedSkills += 1;
      }
    }

    if (deleteObsoleteCodexCachePath != null &&
        deleteObsoleteCodexCachePath.trim().isNotEmpty) {
      final cacheDir = Directory(deleteObsoleteCodexCachePath);
      if (await cacheDir.exists()) {
        try {
          await McpRepoService.deleteDirectoryResilient(cacheDir);
          deletedCache = true;
        } catch (error) {
          errors.add('codex cache: $error');
        }
      }
    }

    return OrphanSkillDeleteResult(
      deletedSkillCount: deletedSkills,
      deletedDirectoryCount: deletedDirs,
      deletedObsoleteCodexCache: deletedCache,
      errors: errors,
    );
  }

  static Map<SkillTarget, String> _defaultTargetDirs() {
    final map = <SkillTarget, String>{};
    for (final target in _targetOrder) {
      final path = switch (target) {
        SkillTarget.codex => McpPaths.codexSkillsPath,
        SkillTarget.openCode => McpPaths.openCodeSkillsPath,
        _ => AgentResourceKind.skill.canConvertTo(target)
            ? _localPathFor(target)
            : null,
      };
      if (path != null && path.trim().isNotEmpty) {
        map[target] = path;
      }
    }
    return map;
  }

  static String? _localPathFor(SkillTarget target) => switch (target) {
    SkillTarget.workBuddy => McpPaths.workBuddySkillsPath,
    SkillTarget.workBuddyAi => McpPaths.workBuddyAiSkillsPath,
    SkillTarget.deepSeekHarness => McpPaths.deepSeekSkillsPath,
    SkillTarget.antigravity => McpPaths.antigravitySkillsPath,
    SkillTarget.doubao => McpPaths.doubaoSkillsPath,
    _ => null,
  };

  static bool _usesKebabFolderNames(SkillTarget target) =>
      target == SkillTarget.antigravity || target == SkillTarget.doubao;

  Future<_CursorSkillNameSet> _collectCursorSkillNames(
    String? sourceDir,
  ) async {
    final raw = <String>{};
    final kebab = <String>{};
    if (sourceDir == null || sourceDir.trim().isEmpty) {
      return _CursorSkillNameSet(raw: raw, kebabOrRaw: kebab);
    }
    final dir = Directory(sourceDir);
    if (!await dir.exists()) {
      return _CursorSkillNameSet(raw: raw, kebabOrRaw: kebab);
    }

    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final folderName = p.basename(entity.path);
      if (folderName.startsWith('.')) continue;
      final skillMd = File(p.join(entity.path, 'SKILL.md'));
      if (!await skillMd.exists()) continue;

      raw.add(folderName);
      kebab.add(folderName);
      try {
        final doc = await SkillMdDocument.parseFile(skillMd.path);
        kebab.add(
          StandardSkillFrontmatter.skillNameFor(folderName, doc.name),
        );
      } catch (_) {}
    }
    return _CursorSkillNameSet(raw: raw, kebabOrRaw: kebab);
  }

  Future<Set<String>> _readManagedNames(String targetDir) async {
    final file = File(p.join(targetDir, ManagedSkillsManifest.fileName));
    if (!await file.exists()) return const {};
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return const {};
      final scopes = decoded['scopes'];
      if (scopes is! Map<String, dynamic>) return const {};
      final result = <String>{};
      for (final value in scopes.values) {
        if (value is List) {
          result.addAll(value.whereType<String>());
        }
      }
      return result;
    } catch (_) {
      return const {};
    }
  }

  Future<String?> _readSkillDescription(String skillDir) async {
    final skillMd = File(p.join(skillDir, 'SKILL.md'));
    if (!await skillMd.exists()) return null;
    try {
      final doc = await SkillMdDocument.parseFile(skillMd.path);
      final desc = doc.description?.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (desc == null || desc.isEmpty) return null;
      return desc;
    } catch (_) {
      return null;
    }
  }
}

class _CursorSkillNameSet {
  const _CursorSkillNameSet({required this.raw, required this.kebabOrRaw});

  final Set<String> raw;
  final Set<String> kebabOrRaw;
}

class _MutableOrphanGroup {
  _MutableOrphanGroup({required this.name});

  final String name;
  final List<OrphanSkillLocation> locations = [];
  String? description;
}
