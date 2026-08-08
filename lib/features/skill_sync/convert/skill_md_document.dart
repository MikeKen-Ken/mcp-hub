import 'dart:io';

import 'package:path/path.dart' as p;

/// 解析 Agent Skill / Rule 常用的简易 YAML frontmatter（`---` 包裹的 `key: value`）。
class SkillMdDocument {
  const SkillMdDocument({
    required this.frontmatter,
    required this.body,
    required this.raw,
  });

  final Map<String, String> frontmatter;
  final String body;
  final String raw;

  String? get name => _nonEmpty(frontmatter['name']);
  String? get description => _nonEmpty(frontmatter['description']);

  /// 正文第一个一级标题（不含 `#`）。
  String? get title {
    for (final line in body.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('# ')) {
        final title = trimmed.substring(2).trim();
        if (title.isNotEmpty) return title;
      }
    }
    return null;
  }

  static SkillMdDocument parse(String raw) {
    final normalized = raw.replaceAll('\r\n', '\n');
    if (!normalized.startsWith('---')) {
      return SkillMdDocument(
        frontmatter: const {},
        body: normalized.trim(),
        raw: raw,
      );
    }

    final end = normalized.indexOf('\n---', 3);
    if (end < 0) {
      return SkillMdDocument(
        frontmatter: const {},
        body: normalized.trim(),
        raw: raw,
      );
    }

    final fmBlock = normalized.substring(3, end).trim();
    var body = normalized.substring(end + 4);
    if (body.startsWith('\n')) body = body.substring(1);

    final frontmatter = <String, String>{};
    for (final line in fmBlock.split('\n')) {
      final trimmed = line.trimRight();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final colon = trimmed.indexOf(':');
      if (colon <= 0) continue;
      final key = trimmed.substring(0, colon).trim();
      var value = trimmed.substring(colon + 1).trim();
      if ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'"))) {
        value = value.substring(1, value.length - 1);
      }
      if (key.isNotEmpty) frontmatter[key] = value;
    }

    return SkillMdDocument(
      frontmatter: frontmatter,
      body: body.trim(),
      raw: raw,
    );
  }

  static Future<SkillMdDocument> parseFile(String path) async {
    final raw = await File(path).readAsString();
    return parse(raw);
  }

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }
}

/// 从路径推断 Skill 包名（目录名）。
String skillPackageNameFromPath(String skillDir) => p.basename(skillDir);
