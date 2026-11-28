import 'dart:io';

import 'package:path/path.dart' as p;

import '../skill_folder_copy.dart';
import 'cursor_rule_markdown.dart';
import 'managed_skills_manifest.dart';
import 'skill_md_document.dart';
import 'standard_skill_frontmatter.dart';

/// Skill 转换结果。
class AntigravitySkillsConvertResult {
  const AntigravitySkillsConvertResult({
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

/// 将 Cursor 的 Skill、Rule 写入 Antigravity 的全局目录。
///
/// - Skill → `~/.gemini/config/skills/<name>/`：整包镜像后把 `SKILL.md`
///   frontmatter 校正为 kebab-case 名称（与目录一致）和必填 description。
///   通过 `.mcp-hub-managed.json` 追踪由 Hub 写入的包：从 Cursor 删除或改名
///   的旧托管包会自动清理，目标端用户自行安装的 Skill 保持不动。
/// - Rule → `~/.gemini/GEMINI.md`：去掉 Cursor frontmatter 后写入标记段，
///   标记以外的内容保持不变。
class CursorToAntigravityConverter {
  const CursorToAntigravityConverter({
    this.folderCopy = const SkillFolderCopy(),
    this.frontmatter = const StandardSkillFrontmatter(),
    this.managedManifest = const ManagedSkillsManifest(),
  });

  static const rulesBegin = '<!-- mcp-hub:cursor-rules:begin -->';
  static const rulesEnd = '<!-- mcp-hub:cursor-rules:end -->';
  static const managedScope = 'antigravity-skills';

  final SkillFolderCopy folderCopy;
  final StandardSkillFrontmatter frontmatter;
  final ManagedSkillsManifest managedManifest;

  Future<AntigravitySkillsConvertResult> convertSkills({
    required String sourceDir,
    required String targetDir,
  }) async {
    final source = Directory(sourceDir);
    if (!await source.exists()) {
      return const AntigravitySkillsConvertResult(
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
    return AntigravitySkillsConvertResult(
      packages: packages,
      copiedFiles: copiedFiles,
      deletedEntries: deletedEntries,
      rewrittenSkills: rewrittenSkills,
      removedPackages: removedPackages,
      errors: errors,
    );
  }

  /// 把全局 Cursor `.mdc` / `.md` 规则写入 [geminiMdPath] 的标记段，返回写入条数。
  Future<int> convertRules({
    required String sourceDir,
    required String geminiMdPath,
  }) async {
    final rules = await CursorRuleMarkdown.loadGlobalRules(sourceDir);
    final sections = [
      for (final r in rules) '## ${r.heading}\n\n${r.body}',
    ];

    final managed = StringBuffer()
      ..writeln(rulesBegin)
      ..writeln('# Rules converted from Cursor')
      ..writeln()
      ..writeln(
        'Antigravity applies `~/.gemini/GEMINI.md` globally to every workspace. '
        'These sections were converted from `~/.cursor/rules`.',
      )
      ..writeln();
    if (sections.isEmpty) {
      managed.writeln(
        '(The Cursor Rule directory is empty; no sections were written.)',
      );
    } else {
      managed.writeln(sections.join('\n\n'));
    }
    managed.writeln(rulesEnd);

    final file = File(geminiMdPath);
    final existing = await file.exists() ? await file.readAsString() : '';
    await file.parent.create(recursive: true);
    await file.writeAsString(
      CursorRuleMarkdown.mergeMarked(
        existing,
        managed.toString().trimRight(),
        beginMarker: rulesBegin,
        endMarker: rulesEnd,
        targetName: 'GEMINI.md',
      ),
    );
    return sections.length;
  }
}
