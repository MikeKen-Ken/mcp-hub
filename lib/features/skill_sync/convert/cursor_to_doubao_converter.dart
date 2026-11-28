import 'dart:io';

import 'package:path/path.dart' as p;

import '../skill_folder_copy.dart';
import 'managed_skills_manifest.dart';
import 'skill_md_document.dart';
import 'standard_skill_frontmatter.dart';

/// Skill 转换结果。
class DoubaoSkillsConvertResult {
  const DoubaoSkillsConvertResult({
    required this.packages,
    required this.copiedFiles,
    required this.deletedEntries,
    required this.rewrittenSkills,
    this.removedPackages = 0,
    this.errors = const [],
  });

  final int packages;
  final int copiedFiles;
  final int deletedEntries;
  final int rewrittenSkills;
  final int removedPackages;
  final List<String> errors;
}

/// 将 Cursor 的 Skill 写入豆包工作任务的本地技能目录。
///
/// 豆包电脑版没有用户可写的本地 MCP 配置文件（连接器只在客户端界面里
/// 配置），因此只转换 Skill。豆包要求 `SKILL.md` 开头带 YAML 的
/// `name` 与 `description`；缺失或不合规范时只改写 frontmatter。
///
/// 通过 `.mcp-hub-managed.json` 追踪由 Hub 写入的包：从 Cursor 删除或改名
/// 的旧托管包会自动清理，目标端从技能中心安装的 Skill 保持不动；包内按
/// Cursor 全量镜像。
class CursorToDoubaoConverter {
  const CursorToDoubaoConverter({
    this.folderCopy = const SkillFolderCopy(),
    this.frontmatter = const StandardSkillFrontmatter(),
    this.managedManifest = const ManagedSkillsManifest(),
  });

  static const managedScope = 'doubao-skills';

  final SkillFolderCopy folderCopy;
  final StandardSkillFrontmatter frontmatter;
  final ManagedSkillsManifest managedManifest;

  Future<DoubaoSkillsConvertResult> convertSkills({
    required String sourceDir,
    required String targetDir,
  }) async {
    final source = Directory(sourceDir);
    if (!await source.exists()) {
      return const DoubaoSkillsConvertResult(
        packages: 0,
        copiedFiles: 0,
        deletedEntries: 0,
        rewrittenSkills: 0,
      );
    }
    await Directory(targetDir).create(recursive: true);

    var packages = 0;
    var copiedFiles = 0;
    var deletedEntries = 0;
    var rewrittenSkills = 0;
    final errors = <String>[];
    final writtenNames = <String>{};
    final failedNames = <String>{};
    await for (final entity in source.list(followLinks: false)) {
      if (entity is! Directory || p.basename(entity.path).startsWith('.')) {
        continue;
      }
      if (!await File(p.join(entity.path, 'SKILL.md')).exists()) continue;
      final sourceName = p.basename(entity.path);
      String? resolvedName;
      try {
        final doc = await SkillMdDocument.parseFile(
          p.join(entity.path, 'SKILL.md'),
        );
        final name = StandardSkillFrontmatter.skillNameFor(
          sourceName,
          doc.name,
        );
        resolvedName = name;
        final packageDir = p.join(targetDir, name);
        final mirrored = await folderCopy.mirrorContents(
          sourceDir: entity.path,
          targetDir: packageDir,
        );
        if (await frontmatter.ensure(packageDir: packageDir, name: name)) {
          rewrittenSkills += 1;
        }
        writtenNames.add(name);
        packages += 1;
        copiedFiles += mirrored.copiedFiles;
        deletedEntries += mirrored.deletedEntries;
      } catch (error) {
        failedNames.add(sourceName);
        if (resolvedName != null) failedNames.add(resolvedName);
        errors.add('$sourceName: $error');
      }
    }
    final removedPackages = await managedManifest.syncAndPrune(
      targetDir: targetDir,
      scope: managedScope,
      currentManagedNames: writtenNames,
      failedNames: failedNames,
    );
    return DoubaoSkillsConvertResult(
      packages: packages,
      copiedFiles: copiedFiles,
      deletedEntries: deletedEntries,
      rewrittenSkills: rewrittenSkills,
      removedPackages: removedPackages,
      errors: errors,
    );
  }
}
