import 'dart:io';

import 'package:path/path.dart' as p;

import '../skill_folder_copy.dart';
import 'managed_skills_manifest.dart';

/// Skill 转换结果。
class WorkBuddySkillsConvertResult {
  const WorkBuddySkillsConvertResult({
    required this.packages,
    required this.copiedFiles,
    required this.deletedEntries,
    this.removedPackages = 0,
    this.errors = const [],
  });

  final int packages;
  final int copiedFiles;
  final int deletedEntries;
  final int removedPackages;
  final List<String> errors;
}

/// 将 Cursor 的 Skill、Rule 写入 WorkBuddy / WorkBuddy AI 的用户级目录。
///
/// WorkBuddy 沿用标准 `SKILL.md` 包布局，因此 Skill 只做整包复制。
/// 通过 `.mcp-hub-managed.json` 追踪由 Hub 写入的 Skill：从 Cursor 删除或
/// 改名的旧托管包会自动清理，同时保留 WorkBuddy 内置与市场安装的 Skill。
/// Rule 写入专属子目录 [managedRulesFolder]，只在该子目录内做镜像，不触碰
/// 用户自己写在 `rules/` 下的文件。
class CursorToWorkBuddyConverter {
  const CursorToWorkBuddyConverter({
    this.folderCopy = const SkillFolderCopy(),
    this.managedManifest = const ManagedSkillsManifest(),
  });

  /// `rules/` 下由 Hub 独占管理的子目录名。
  static const managedRulesFolder = 'cursor-sync';
  static const managedScope = 'workbuddy-skills';

  final SkillFolderCopy folderCopy;
  final ManagedSkillsManifest managedManifest;

  Future<WorkBuddySkillsConvertResult> convertSkills({
    required String sourceDir,
    required String targetDir,
  }) async {
    final source = Directory(sourceDir);
    if (!await source.exists()) {
      return const WorkBuddySkillsConvertResult(
        packages: 0,
        copiedFiles: 0,
        deletedEntries: 0,
      );
    }
    await Directory(targetDir).create(recursive: true);

    var packages = 0;
    var copiedFiles = 0;
    var deletedEntries = 0;
    final errors = <String>[];
    final writtenNames = <String>{};
    final failedNames = <String>{};
    await for (final entity in source.list(followLinks: false)) {
      if (entity is! Directory || p.basename(entity.path).startsWith('.')) {
        continue;
      }
      if (!await File(p.join(entity.path, 'SKILL.md')).exists()) continue;
      final name = p.basename(entity.path);
      try {
        final mirrored = await folderCopy.mirrorContents(
          sourceDir: entity.path,
          targetDir: p.join(targetDir, name),
        );
        writtenNames.add(name);
        packages += 1;
        copiedFiles += mirrored.copiedFiles;
        deletedEntries += mirrored.deletedEntries;
      } catch (error) {
        failedNames.add(name);
        errors.add('$name: $error');
      }
    }
    final removedPackages = await managedManifest.syncAndPrune(
      targetDir: targetDir,
      scope: managedScope,
      currentManagedNames: writtenNames,
      failedNames: failedNames,
    );
    return WorkBuddySkillsConvertResult(
      packages: packages,
      copiedFiles: copiedFiles,
      deletedEntries: deletedEntries,
      removedPackages: removedPackages,
      errors: errors,
    );
  }

  /// 复制 Cursor `.mdc` / `.md` 规则到 `<rulesDir>/cursor-sync/`，返回写入数量。
  Future<int> convertRules({
    required String sourceDir,
    required String rulesDir,
  }) async {
    final source = Directory(sourceDir);
    final managed = Directory(p.join(rulesDir, managedRulesFolder));
    if (!await source.exists()) return 0;
    await managed.create(recursive: true);

    final written = <String>{};
    await for (final entity in source.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File || !_isRuleFile(entity.path)) continue;
      final relative = p.relative(entity.path, from: source.path);
      if (p.split(relative).any((part) => part.startsWith('.'))) continue;
      final output = File(p.join(managed.path, relative));
      await output.parent.create(recursive: true);
      await entity.copy(output.path);
      written.add(p.normalize(output.path));
    }

    await for (final entity in managed.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File &&
          _isRuleFile(entity.path) &&
          !written.contains(p.normalize(entity.path))) {
        await entity.delete();
      }
    }
    await _pruneEmptyDirectories(managed);
    return written.length;
  }

  Future<void> _pruneEmptyDirectories(Directory root) async {
    final dirs = <Directory>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is Directory) dirs.add(entity);
    }
    dirs.sort((a, b) => b.path.length.compareTo(a.path.length));
    for (final dir in dirs) {
      if (!await dir.exists()) continue;
      if (await dir.list(followLinks: false).isEmpty) {
        await dir.delete();
      }
    }
  }

  bool _isRuleFile(String path) {
    final extension = p.extension(path).toLowerCase();
    return extension == '.mdc' || extension == '.md';
  }
}
