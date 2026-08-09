import 'dart:io';

import 'package:path/path.dart' as p;

import 'skill_md_document.dart';

/// 单个 Cursor Rule 转成 AGENTS.md 章节的结果。
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

/// 把 Cursor `~/.cursor/rules/**/*.mdc` 批量转换成 Codex `AGENTS.md`。
class CursorToCodexAgentsConverter {
  const CursorToCodexAgentsConverter();

  static const managedHeader = '# 全局工作规则';

  /// 读取 [cursorRulesDir] 下全部 `.mdc`，写入 [agentsMdPath]。
  ///
  /// 会**整文件覆盖**目标 `AGENTS.md`（与现有手写转换产物一致：整份由 Cursor rules 生成）。
  Future<List<CodexAgentsRuleItem>> convertAll({
    required String cursorRulesDir,
    required String agentsMdPath,
  }) async {
    final sourceRoot = Directory(cursorRulesDir);
    if (!await sourceRoot.exists()) {
      throw StateError('Cursor Rule 目录不存在：$cursorRulesDir');
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

    // alwaysApply 规则靠前，其余保持路径排序（files 已排序）。
    final ordered = [
      ...parsed.where((e) => e.item.alwaysApply),
      ...parsed.where((e) => !e.item.alwaysApply),
    ];
    final items = [for (final e in ordered) e.item];
    final orderedSections = [for (final e in ordered) e.section];

    final buffer = StringBuffer()
      ..writeln(managedHeader)
      ..writeln()
      ..writeln(
        '以下规则由 `~/.cursor/rules` 转换而来，适用于 Codex 的所有项目；'
        '项目内更具体的 `AGENTS.md` 或 `AGENTS.override.md` 可补充或覆盖这些规则。',
      )
      ..writeln();

    if (orderedSections.isEmpty) {
      buffer.writeln('（当前 Cursor Rule 目录为空，未写入任何章节。）');
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

  /// 去掉空的首尾行；保留正文原有 MUST 等字面量（与 Cursor 源一致）。
  static String _normalizeRuleBody(String body) {
    final lines = body.replaceAll('\r\n', '\n').split('\n');
    while (lines.isNotEmpty && lines.first.trim().isEmpty) {
      lines.removeAt(0);
    }
    while (lines.isNotEmpty && lines.last.trim().isEmpty) {
      lines.removeLast();
    }
    // 若正文以与 heading 重复的 `# title` 开头则去掉，避免 AGENTS 出现双标题。
    if (lines.isNotEmpty && lines.first.trim().startsWith('# ')) {
      lines.removeAt(0);
      while (lines.isNotEmpty && lines.first.trim().isEmpty) {
        lines.removeAt(0);
      }
    }
    return lines.join('\n').trim();
  }
}
