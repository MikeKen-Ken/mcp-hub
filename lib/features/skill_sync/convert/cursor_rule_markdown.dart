import 'dart:io';

import 'package:path/path.dart' as p;

import 'skill_md_document.dart';

/// 解析后用于生成全局 `AGENTS.md` / `GEMINI.md` 的单条 Cursor 规则。
class ParsedCursorRule {
  const ParsedCursorRule({
    required this.relativePath,
    required this.heading,
    required this.body,
    required this.alwaysApply,
  });

  final String relativePath;
  final String heading;
  final String body;
  final bool? alwaysApply;
}

/// 统一加载 Cursor `.mdc` / `.md` 规则，供各目标平台全局规则转换器复用。
abstract final class CursorRuleMarkdown {
  static const rulesBegin = '<!-- mcp-hub:cursor-rules:begin -->';
  static const rulesEnd = '<!-- mcp-hub:cursor-rules:end -->';

  /// 读取可全局注入的 Cursor 规则：
  /// - 支持 `.mdc` 与 `.md`，忽略任意 `.` 开头的隐藏路径；
  /// - 跳过显式声明 `alwaysApply: false` 的条件/按需规则；
  /// - 去掉与二级标题重复的首行 `# 标题`，并把 `alwaysApply: true` 排在前面。
  static Future<List<ParsedCursorRule>> loadGlobalRules(String sourceDir) async {
    final source = Directory(sourceDir);
    if (!await source.exists()) return const [];

    final files = <File>[];
    await for (final entity in source.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File || !isRuleFile(entity.path)) continue;
      final relative = p.relative(entity.path, from: source.path);
      if (p.split(relative).any((part) => part.startsWith('.'))) continue;
      files.add(entity);
    }
    files.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));

    final always = <ParsedCursorRule>[];
    final rest = <ParsedCursorRule>[];
    for (final file in files) {
      final relative = p.normalize(p.relative(file.path, from: source.path));
      final doc = await SkillMdDocument.parseFile(file.path);
      if (doc.alwaysApply == false) continue;

      final body = normalizeBody(doc.body);
      if (body.isEmpty) continue;

      final heading = _headingFor(doc: doc, relativePath: relative);
      final rule = ParsedCursorRule(
        relativePath: relative,
        heading: heading,
        body: body,
        alwaysApply: doc.alwaysApply,
      );
      (doc.alwaysApply == true ? always : rest).add(rule);
    }
    return [...always, ...rest];
  }

  static bool isRuleFile(String path) {
    final ext = p.extension(path).toLowerCase();
    return ext == '.mdc' || ext == '.md';
  }

  static String normalizeBody(String body) {
    final lines = body.replaceAll('\r\n', '\n').split('\n');
    while (lines.isNotEmpty && lines.first.trim().isEmpty) {
      lines.removeAt(0);
    }
    while (lines.isNotEmpty && lines.last.trim().isEmpty) {
      lines.removeLast();
    }
    if (lines.isNotEmpty && lines.first.trim().startsWith('# ')) {
      lines.removeAt(0);
      while (lines.isNotEmpty && lines.first.trim().isEmpty) {
        lines.removeAt(0);
      }
    }
    return lines.join('\n').trim();
  }

  static String mergeMarked(
    String existing,
    String managed, {
    String beginMarker = rulesBegin,
    String endMarker = rulesEnd,
    required String targetName,
  }) {
    final begin = existing.indexOf(beginMarker);
    final end = existing.indexOf(endMarker);
    if (begin >= 0 && end > begin) {
      final after = end + endMarker.length;
      return existing.replaceRange(begin, after, managed);
    }
    if (begin >= 0 || end >= 0) {
      throw FormatException(
        '$targetName cursor-rules markers are incomplete; nothing was written',
      );
    }
    if (existing.trim().isEmpty) return '$managed\n';
    return '${existing.trimRight()}\n\n$managed\n';
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

    return p.basenameWithoutExtension(relativePath).replaceAll('-', ' ');
  }
}
