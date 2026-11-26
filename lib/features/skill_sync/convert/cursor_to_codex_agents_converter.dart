import 'dart:io';

import 'cursor_rule_markdown.dart';

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

/// Batch-convert Cursor `~/.cursor/rules/**/*.{mdc,md}` into Codex `AGENTS.md`.
class CursorToCodexAgentsConverter {
  const CursorToCodexAgentsConverter();

  static const managedHeader = '# Global working rules';

  static const managedPreamble =
      'These rules were converted from `~/.cursor/rules` and apply to every '
      'Codex project. A project-level `AGENTS.md` or `AGENTS.override.md` may '
      'add to or override them.';

  static const emptyRulesNote =
      '(The Cursor Rule directory is empty; no sections were written.)';

  /// Read global `.mdc`/`.md` rules under [cursorRulesDir] and write [agentsMdPath].
  ///
  /// Rules with `alwaysApply: false` are excluded. If [agentsMdPath] already
  /// uses `mcp-hub:cursor-rules` markers, only that marked block is replaced.
  Future<List<CodexAgentsRuleItem>> convertAll({
    required String cursorRulesDir,
    required String agentsMdPath,
  }) async {
    final sourceRoot = Directory(cursorRulesDir);
    if (!await sourceRoot.exists()) {
      throw StateError('Cursor Rule directory does not exist: $cursorRulesDir');
    }

    final rules = await CursorRuleMarkdown.loadGlobalRules(cursorRulesDir);
    final items = [
      for (final r in rules)
        CodexAgentsRuleItem(
          relativePath: r.relativePath,
          heading: r.heading,
          alwaysApply: r.alwaysApply ?? false,
        ),
    ];
    final sections = [
      for (final r in rules) '## ${r.heading}\n\n${r.body}',
    ];

    final out = File(agentsMdPath);
    final existing = await out.exists() ? await out.readAsString() : '';
    final hasMarkers =
        existing.contains(CursorRuleMarkdown.rulesBegin) ||
        existing.contains(CursorRuleMarkdown.rulesEnd);

    await out.parent.create(recursive: true);
    if (hasMarkers) {
      final managed = StringBuffer()
        ..writeln(CursorRuleMarkdown.rulesBegin)
        ..writeln(managedHeader)
        ..writeln()
        ..writeln(managedPreamble)
        ..writeln();
      if (sections.isEmpty) {
        managed.writeln(emptyRulesNote);
      } else {
        managed.writeln(sections.join('\n\n'));
      }
      managed.writeln(CursorRuleMarkdown.rulesEnd);
      await out.writeAsString(
        CursorRuleMarkdown.mergeMarked(
          existing,
          managed.toString().trimRight(),
          targetName: 'AGENTS.md',
        ),
      );
      return items;
    }

    final buffer = StringBuffer()
      ..writeln(managedHeader)
      ..writeln()
      ..writeln(managedPreamble)
      ..writeln();
    if (sections.isEmpty) {
      buffer.writeln(emptyRulesNote);
    } else {
      buffer.writeln(sections.join('\n\n'));
      buffer.writeln();
    }
    await out.writeAsString(buffer.toString());
    return items;
  }
}
