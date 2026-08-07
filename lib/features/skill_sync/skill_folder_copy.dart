import 'dart:io';

import 'package:path/path.dart' as p;

/// 目录复制结果。
class SkillFolderCopyResult {
  const SkillFolderCopyResult({
    required this.copiedFiles,
    required this.copiedDirs,
    required this.sourcePath,
    required this.targetPath,
  });

  final int copiedFiles;
  final int copiedDirs;
  final String sourcePath;
  final String targetPath;
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
