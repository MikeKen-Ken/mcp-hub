import 'dart:io';

import 'package:path/path.dart' as p;

import 'skill_md_document.dart';

/// One Cursor rule converted into an AGENTS.md section.
class CodexAgentsRuleItem {
  const CodexAgentsRuleItem({
    required this.relativePath,
    required this.heading,
    required this.alwaysApply,
  });

  final String relativePath;
  final String heading;
  final bool alwaysApply;
}

/// Batch-convert Cursor `~/.cursor/rules/**/*.mdc` into Codex `AGENTS.md`.
class CursorToCodexAgentsConverter {
  const CursorToCodexAgentsConverter();

  static const managedHeader = '# Global working rules';

  static const managedPreamble =
      'These rules were converted from `~/.cursor/rules` and apply to every '
      'Codex project. A project-level `AGENTS.md` or `AGENTS.override.md` may '
      'add to or override them.';

  static const emptyRulesNote =
      '(The Cursor Rule directory is empty; no sections were written.)';

  /// Read every `.mdc` under [cursorRulesDir] and write [agentsMdPath].
  ///
  /// Overwrites the target `AGENTS.md` in full (the whole file is generated
  /// from Cursor rules).
  Future<List<CodexAgentsRuleItem>> convertAll({
    required String cursorRulesDir,
    required String agentsMdPath,
  }) async {
    final sourceRoot = Directory(cursorRulesDir);
    if (!await sourceRoot.exists()) {
      throw StateError('Cursor Rule directory does not exist: $cursorRulesDir');
    }

    final files = <File>[];
    await for (final entity in sourceRoot.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name.startsWith('.')) continue;
      if (!name.toLowerCase().endsWith('.mdc')) continue;
      files.add(entity);
    }

    files.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));

    final parsed = <({CodexAgentsRuleItem item, String section})>[];

    for (final file in files) {
      final relative = p.normalize(p.relative(file.path, from: cursorRulesDir));
      final doc = await SkillMdDocument.parseFile(file.path);
      final alwaysApply =
          (doc.frontmatter['alwaysApply'] ?? '').toLowerCase() == 'true';
      final heading = _headingFor(doc: doc, relativePath: relative);
      final body = _normalizeRuleBody(doc.body);
      if (body.isEmpty) continue;

      final item = CodexAgentsRuleItem(
        relativePath: relative,
        heading: heading,
        alwaysApply: alwaysApply,
      );
      parsed.add((item: item, section: '## $heading\n\n$body'));
    }

    // alwaysApply rules first; remaining items keep path order (files are sorted).
    final ordered = [
      ...parsed.where((e) => e.item.alwaysApply),
      ...parsed.where((e) => !e.item.alwaysApply),
    ];
    final items = [for (final e in ordered) e.item];
    final orderedSections = [for (final e in ordered) e.section];

    final buffer = StringBuffer()
      ..writeln(managedHeader)
      ..writeln()
      ..writeln(managedPreamble)
      ..writeln();

    if (orderedSections.isEmpty) {
      buffer.writeln(emptyRulesNote);
    } else {
      buffer.writeln(orderedSections.join('\n\n'));
      buffer.writeln();
    }

    final out = File(agentsMdPath);
    await out.parent.create(recursive: true);
    await out.writeAsString(buffer.toString());

    return items;
  }

  static String _headingFor({
    required SkillMdDocument doc,
    required String relativePath,
  }) {
    final fromTitle = doc.title;
    if (fromTitle != null && fromTitle.isNotEmpty) return fromTitle;

    final fromDescription = doc.frontmatter['description']?.trim();
    if (fromDescription != null && fromDescription.isNotEmpty) {
      return fromDescription;
    }

    final base = p.basenameWithoutExtension(relativePath);
    return base.replaceAll('-', ' ');
  }

  /// Trim leading/trailing blank lines; keep MUST and other literals as in Cursor.
  static String _normalizeRuleBody(String body) {
    final lines = body.replaceAll('\r\n', '\n').split('\n');
    while (lines.isNotEmpty && lines.first.trim().isEmpty) {
      lines.removeAt(0);
    }
    while (lines.isNotEmpty && lines.last.trim().isEmpty) {
      lines.removeLast();
    }
    // Drop a leading `# title` that duplicates the section heading.
    if (lines.isNotEmpty && lines.first.trim().startsWith('# ')) {
      lines.removeAt(0);
      while (lines.isNotEmpty && lines.first.trim().isEmpty) {
        lines.removeAt(0);
      }
    }
    return lines.join('\n').trim();
  }
}
