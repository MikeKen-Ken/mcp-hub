import 'dart:io';

import 'package:path/path.dart' as p;

/// 目录复制 / 镜像结果。
class SkillFolderCopyResult {
  const SkillFolderCopyResult({
    required this.copiedFiles,
    required this.copiedDirs,
    required this.sourcePath,
    required this.targetPath,
    this.deletedEntries = 0,
  });

  final int copiedFiles;
  final int copiedDirs;
  final String sourcePath;
  final String targetPath;

  /// 全量镜像时从目标删掉的多余条目数（文件或目录各计 1）。
  final int deletedEntries;
}

/// 把 [sourceDir] 内容合并复制到 [targetDir]（覆盖同名文件，不删除目标多余项）。
///
/// 默认跳过名称以 `.` 开头的条目（如 Codex `.system`）。
class SkillFolderCopy {
  const SkillFolderCopy();

  Future<SkillFolderCopyResult> copyContents({
    required String sourceDir,
    required String targetDir,
    bool skipDotEntries = true,
  }) async {
    final source = Directory(sourceDir);
    if (!await source.exists()) {
      throw StateError('源目录不存在：$sourceDir');
    }

    final target = Directory(targetDir);
    await target.create(recursive: true);

    var files = 0;
    var dirs = 0;

    await for (final entity in source.list(followLinks: false)) {
      final name = p.basename(entity.path);
      if (skipDotEntries && name.startsWith('.')) continue;

      final destPath = p.join(target.path, name);
      if (entity is Directory) {
        dirs += 1;
        final nested = await copyContents(
          sourceDir: entity.path,
          targetDir: destPath,
          skipDotEntries: skipDotEntries,
        );
        files += nested.copiedFiles;
        dirs += nested.copiedDirs;
      } else if (entity is File) {
        await File(destPath).parent.create(recursive: true);
        await entity.copy(destPath);
        files += 1;
      }
    }

    return SkillFolderCopyResult(
      copiedFiles: files,
      copiedDirs: dirs,
      sourcePath: source.path,
      targetPath: target.path,
    );
  }

  /// 把 [sourceDir] 全量镜像到 [targetDir]：覆盖同名，并删除目标中多余项。
  ///
  /// 默认跳过点开头条目（不复制、也不删除目标侧的 `.xxx`）。
  /// [preserveNames] 仅作用于本层：目标侧这些名字即使源中没有也不删除
  ///（例如 Codex Skill 包内的 `agents/`）。
  Future<SkillFolderCopyResult> mirrorContents({
    required String sourceDir,
    required String targetDir,
    bool skipDotEntries = true,
    Set<String> preserveNames = const {},
  }) async {
    final source = Directory(sourceDir);
    if (!await source.exists()) {
      await source.create(recursive: true);
    }

    final copied = await copyContents(
      sourceDir: source.path,
      targetDir: targetDir,
      skipDotEntries: skipDotEntries,
    );
    final deleted = await _deleteExtras(
      sourceDir: source.path,
      targetDir: targetDir,
      skipDotEntries: skipDotEntries,
      preserveNames: preserveNames,
    );
    return SkillFolderCopyResult(
      copiedFiles: copied.copiedFiles,
      copiedDirs: copied.copiedDirs,
      sourcePath: copied.sourcePath,
      targetPath: copied.targetPath,
      deletedEntries: deleted,
    );
  }

  Future<int> _deleteExtras({
    required String sourceDir,
    required String targetDir,
    required bool skipDotEntries,
    Set<String> preserveNames = const {},
  }) async {
    final target = Directory(targetDir);
    if (!await target.exists()) return 0;

    final sourceNames = <String>{};
    final source = Directory(sourceDir);
    if (await source.exists()) {
      await for (final entity in source.list(followLinks: false)) {
        final name = p.basename(entity.path);
        if (skipDotEntries && name.startsWith('.')) continue;
        sourceNames.add(name);
      }
    }

    var deleted = 0;
    await for (final entity in target.list(followLinks: false)) {
      final name = p.basename(entity.path);
      if (skipDotEntries && name.startsWith('.')) continue;
      if (preserveNames.contains(name)) continue;

      if (!sourceNames.contains(name)) {
        await entity.delete(recursive: true);
        deleted += 1;
        continue;
      }

      if (entity is Directory) {
        deleted += await _deleteExtras(
          sourceDir: p.join(sourceDir, name),
          targetDir: entity.path,
          skipDotEntries: skipDotEntries,
        );
      }
    }
    return deleted;
  }

  /// 删除目标侧已不在源中的 Skill 包（以及根下其它非点开头多余项）。
  Future<int> removeStaleSkillPackages({
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
      final name = p.basename(entity.path);
      if (name.startsWith('.')) continue;
      if (keepNames.contains(name)) continue;
      await entity.delete(recursive: true);
      removed += 1;
    }
    return removed;
  }

  /// 统计目录下 Skill 包数量（含 `SKILL.md` 的直接子目录）。
  Future<int> countSkillPackages(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return 0;
    var count = 0;
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final name = p.basename(entity.path);
      if (name.startsWith('.')) continue;
      final skillMd = File(p.join(entity.path, 'SKILL.md'));
      if (await skillMd.exists()) count += 1;
    }
    return count;
  }
}
