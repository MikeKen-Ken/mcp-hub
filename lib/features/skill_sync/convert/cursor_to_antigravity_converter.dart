import 'dart:io';

import 'package:path/path.dart' as p;

import '../skill_folder_copy.dart';
import 'skill_md_document.dart';
import 'standard_skill_frontmatter.dart';

/// Skill 转换结果。
class AntigravitySkillsConvertResult {
  const AntigravitySkillsConvertResult({
    required this.packages,
    required this.copiedFiles,
    required this.deletedEntries,
    required this.rewrittenSkills,
    this.errors = const [],
  });

  final int packages;
  final int copiedFiles;
  final int deletedEntries;
  final int rewrittenSkills;
  final List<String> errors;
}

/// 将 Cursor 的 Skill、Rule 写入 Antigravity 的全局目录。
///
/// - Skill → `~/.gemini/config/skills/<name>/`：整包镜像后把 `SKILL.md`
///   frontmatter 校正为 kebab-case 名称（与目录一致）和必填 description。
///   该目录也可能存放用户自己安装的 Skill，因此不删除 Cursor 中不存在的包。
/// - Rule → `~/.gemini/GEMINI.md`：去掉 Cursor frontmatter 后写入标记段，
///   标记以外的内容保持不变。
class CursorToAntigravityConverter {
  const CursorToAntigravityConverter({
    this.folderCopy = const SkillFolderCopy(),
    this.frontmatter = const StandardSkillFrontmatter(),
  });

  static const rulesBegin = '<!-- mcp-hub:cursor-rules:begin -->';
  static const rulesEnd = '<!-- mcp-hub:cursor-rules:end -->';

  final SkillFolderCopy folderCopy;
  final StandardSkillFrontmatter frontmatter;

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
    await for (final entity in source.list(followLinks: false)) {
      if (entity is! Directory || p.basename(entity.path).startsWith('.')) {
        continue;
      }
      if (!await File(p.join(entity.path, 'SKILL.md')).exists()) continue;
      final sourceName = p.basename(entity.path);
      try {
        final doc = await SkillMdDocument.parseFile(
          p.join(entity.path, 'SKILL.md'),
        );
        final name = StandardSkillFrontmatter.skillNameFor(
          sourceName,
          doc.name,
        );
        final packageDir = p.join(targetDir, name);
        final mirrored = await folderCopy.mirrorContents(
          sourceDir: entity.path,
          targetDir: packageDir,
        );
        if (await frontmatter.ensure(packageDir: packageDir, name: name)) {
          rewrittenSkills += 1;
        }
        packages += 1;
        copiedFiles += mirrored.copiedFiles;
        deletedEntries += mirrored.deletedEntries;
      } catch (error) {
        errors.add('$sourceName: $error');
      }
    }
    return AntigravitySkillsConvertResult(
      packages: packages,
      copiedFiles: copiedFiles,
      deletedEntries: deletedEntries,
      rewrittenSkills: rewrittenSkills,
      errors: errors,
    );
  }

  /// 把 Cursor `.mdc` / `.md` 规则写入 [geminiMdPath] 的标记段，返回写入条数。
  Future<int> convertRules({
    required String sourceDir,
    required String geminiMdPath,
  }) async {
    final source = Directory(sourceDir);
    final sections = <String>[];
    if (await source.exists()) {
      final files = <File>[];
      await for (final entity in source.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File || !_isRuleFile(entity.path)) continue;
        final relative = p.relative(entity.path, from: source.path);
        if (p.split(relative).any((part) => part.startsWith('.'))) continue;
        files.add(entity);
      }
      files.sort(
        (a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()),
      );
      for (final file in files) {
        final relative = p.normalize(p.relative(file.path, from: source.path));
        final doc = await SkillMdDocument.parseFile(file.path);
        final body = doc.body.trim();
        if (body.isEmpty) continue;
        final heading =
            doc.title ??
            _nonEmpty(doc.frontmatter['description']) ??
            p.basenameWithoutExtension(relative);
        sections.add('## $heading\n\n$body');
      }
    }

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
      _mergeMarked(existing, managed.toString().trimRight()),
    );
    return sections.length;
  }

  bool _isRuleFile(String path) {
    final extension = p.extension(path).toLowerCase();
    return extension == '.mdc' || extension == '.md';
  }

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  static String _mergeMarked(String existing, String managed) {
    final begin = existing.indexOf(rulesBegin);
    final end = existing.indexOf(rulesEnd);
    if (begin >= 0 && end > begin) {
      final after = end + rulesEnd.length;
      return existing.replaceRange(begin, after, managed);
    }
    if (begin >= 0 || end >= 0) {
      throw const FormatException(
        'GEMINI.md cursor-rules markers are incomplete; nothing was written',
      );
    }
    if (existing.trim().isEmpty) return '$managed\n';
    return '${existing.trimRight()}\n\n$managed\n';
  }
}
