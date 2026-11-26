import 'dart:io';

import 'package:path/path.dart' as p;

import '../skill_folder_copy.dart';
import 'cursor_rule_markdown.dart';
import 'opencode_skill_md.dart';
import 'skill_md_document.dart';

/// Cursor 资源转换到 OpenCode 全局 Markdown 目录的结果。
class OpenCodeConvertResult {
  const OpenCodeConvertResult({
    required this.skills,
    required this.rules,
    required this.commands,
  });

  final int skills;
  final int rules;
  final int commands;

  int get total => skills + rules + commands;
}

/// Skill 包镜像转换结果。
class OpenCodeSkillsConvertResult {
  const OpenCodeSkillsConvertResult({
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

/// Command 文件转换结果。
class OpenCodeCommandsConvertResult {
  const OpenCodeCommandsConvertResult({
    required this.written,
    this.deleted = 0,
  });

  final int written;
  final int deleted;
}

/// 将 Cursor 的 Skill、Rule、Command 写入 OpenCode 的全局目录。
///
/// 不读取或修改 OpenCode 的 JSON/JSONC 配置。
/// Skill 先整包镜像，再把 `SKILL.md` 转成 OpenCode frontmatter；
/// Rule 过滤 `alwaysApply: false` 后去掉 frontmatter 写入 `AGENTS.md`；
/// Command 保留子目录命名空间并补齐 OpenCode frontmatter 写成 `.md`。
class CursorToOpenCodeConverter {
  const CursorToOpenCodeConverter({
    this.folderCopy = const SkillFolderCopy(),
    this.skillMd = const OpenCodeSkillMd(),
  });

  final SkillFolderCopy folderCopy;
  final OpenCodeSkillMd skillMd;

  Future<OpenCodeConvertResult> convertAll({
    required String cursorSkillsDir,
    required String cursorRulesDir,
    required String cursorCommandsDir,
    required String openCodeSkillsDir,
    required String openCodeAgentsMdPath,
    required String openCodeCommandsDir,
  }) async {
    final skills = await convertSkills(
      sourceDir: cursorSkillsDir,
      targetDir: openCodeSkillsDir,
    );
    final rules = await convertRules(
      sourceDir: cursorRulesDir,
      targetPath: openCodeAgentsMdPath,
    );
    final commands = await convertCommands(
      sourceDir: cursorCommandsDir,
      targetDir: openCodeCommandsDir,
    );
    return OpenCodeConvertResult(
      skills: skills.packages,
      rules: rules,
      commands: commands.written,
    );
  }

  /// 整包镜像 Skill，再改写 `SKILL.md` 为 OpenCode 格式，并删除目标多余包。
  Future<OpenCodeSkillsConvertResult> convertSkills({
    required String sourceDir,
    required String targetDir,
  }) async {
    final source = Directory(sourceDir);
    if (!await source.exists()) {
      return const OpenCodeSkillsConvertResult(
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
    await for (final entity in source.list(followLinks: false)) {
      if (entity is! Directory || p.basename(entity.path).startsWith('.')) {
        continue;
      }
      final skillMd = File(p.join(entity.path, 'SKILL.md'));
      if (!await skillMd.exists()) continue;
      final name = p.basename(entity.path);
      final packageDir = p.join(targetDir, name);
      try {
        final mirrored = await folderCopy.mirrorContents(
          sourceDir: entity.path,
          targetDir: packageDir,
        );
        await _rewriteOpenCodeSkillMd(packageDir);
        packages += 1;
        copiedFiles += mirrored.copiedFiles;
        deletedEntries += mirrored.deletedEntries;
      } catch (error) {
        errors.add('$name: $error');
      }
    }

    final removedPackages = await folderCopy.removeStaleSkillPackages(
      sourceSkillsDir: sourceDir,
      targetSkillsDir: targetDir,
    );
    return OpenCodeSkillsConvertResult(
      packages: packages,
      copiedFiles: copiedFiles,
      deletedEntries: deletedEntries,
      removedPackages: removedPackages,
      errors: errors,
    );
  }

  Future<void> _rewriteOpenCodeSkillMd(String packageDir) async {
    final skillMdFile = File(p.join(packageDir, 'SKILL.md'));
    if (!await skillMdFile.exists()) return;
    final doc = await SkillMdDocument.parseFile(skillMdFile.path);
    await skillMdFile.writeAsString(skillMd.convert(doc));
  }

  Future<int> convertRules({
    required String sourceDir,
    required String targetPath,
  }) async {
    final source = Directory(sourceDir);
    final output = File(targetPath);
    await output.parent.create(recursive: true);
    if (!await source.exists()) {
      return 0;
    }

    final rules = await CursorRuleMarkdown.loadGlobalRules(sourceDir);
    final sections = [
      for (final r in rules) '## ${r.heading}\n\n${r.body}',
    ];

    final existing = await output.exists() ? await output.readAsString() : '';
    final hasMarkers =
        existing.contains(CursorRuleMarkdown.rulesBegin) ||
        existing.contains(CursorRuleMarkdown.rulesEnd);

    if (hasMarkers) {
      final managed = StringBuffer()
        ..writeln(CursorRuleMarkdown.rulesBegin)
        ..writeln('# Rules converted from Cursor')
        ..writeln()
        ..writeln(
          'OpenCode loads this file as the global `AGENTS.md`. '
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
      managed.writeln(CursorRuleMarkdown.rulesEnd);
      await output.writeAsString(
        CursorRuleMarkdown.mergeMarked(
          existing,
          managed.toString().trimRight(),
          targetName: 'AGENTS.md',
        ),
      );
      return sections.length;
    }

    if (sections.isEmpty) {
      await output.writeAsString('');
      return 0;
    }
    await output.writeAsString('${sections.join('\n\n')}\n');
    return sections.length;
  }

  /// 写入转换后的 Command（保留子目录与 OpenCode frontmatter），并清理多余项。
  Future<OpenCodeCommandsConvertResult> convertCommands({
    required String sourceDir,
    required String targetDir,
  }) async {
    final source = Directory(sourceDir);
    if (!await source.exists()) {
      return const OpenCodeCommandsConvertResult(written: 0);
    }
    await Directory(targetDir).create(recursive: true);
    var count = 0;
    final written = <String>{};
    await for (final entity in source.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final rel = p.relative(entity.path, from: source.path);
      if (p.split(rel).any((part) => part.startsWith('.'))) continue;
      final extension = p.extension(entity.path).toLowerCase();
      if (extension != '.md' && extension != '.mdc') continue;

      final relWithoutExt = extension == '.mdc'
          ? '${rel.substring(0, rel.length - 4)}.md'
          : rel;
      final normalizedRel = p.normalize(relWithoutExt);
      final output = File(p.join(targetDir, normalizedRel));
      await output.parent.create(recursive: true);

      final doc = await SkillMdDocument.parseFile(entity.path);
      await output.writeAsString(_formatOpenCodeCommand(doc, normalizedRel));
      written.add(normalizedRel);
      count++;
    }
    final deleted = await _deleteExtraCommandFiles(
      targetDir: targetDir,
      keepRelativePaths: written,
    );
    return OpenCodeCommandsConvertResult(written: count, deleted: deleted);
  }

  String _formatOpenCodeCommand(SkillMdDocument doc, String relativePath) {
    final fallbackName = p.basenameWithoutExtension(relativePath);
    final rawDescription =
        doc.description ??
        doc.title ??
        _firstNonEmptyLine(doc.body) ??
        fallbackName;
    final description = rawDescription.replaceAll(RegExp(r'\s+'), ' ').trim();

    final buffer = StringBuffer()
      ..writeln('---')
      ..writeln('description: ${_quoteYaml(description)}');
    for (final key in const ['agent', 'model', 'subtask']) {
      final value = doc.frontmatter[key]?.trim();
      if (value != null && value.isNotEmpty) {
        final rawEntry = doc.rawEntries[key];
        if (rawEntry != null && rawEntry.isNotEmpty) {
          buffer.writeln(rawEntry);
        } else {
          buffer.writeln('$key: $value');
        }
      }
    }
    buffer.writeln('---');
    final body = doc.body.trim();
    if (body.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(body);
    }
    buffer.writeln();
    return buffer.toString();
  }

  static String? _firstNonEmptyLine(String body) {
    for (final line in body.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      return trimmed.length > 120 ? '${trimmed.substring(0, 119)}…' : trimmed;
    }
    return null;
  }

  static String _quoteYaml(String value) {
    final escaped = value
        .replaceAll(r'\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll('\n', r'\n');
    return '"$escaped"';
  }

  Future<int> _deleteExtraCommandFiles({
    required String targetDir,
    required Set<String> keepRelativePaths,
  }) async {
    final target = Directory(targetDir);
    if (!await target.exists()) return 0;
    var deleted = 0;
    await for (final entity in target.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final rel = p.normalize(p.relative(entity.path, from: target.path));
      if (p.split(rel).any((part) => part.startsWith('.'))) continue;
      final ext = p.extension(rel).toLowerCase();
      if (ext != '.md' && ext != '.mdc') continue;
      if (keepRelativePaths.contains(rel)) continue;
      await entity.delete();
      deleted += 1;
    }
    await _pruneEmptyDirectories(target);
    return deleted;
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
}
