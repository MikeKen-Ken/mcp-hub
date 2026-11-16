import 'dart:io';

import 'package:path/path.dart' as p;

import 'skill_md_document.dart';

/// 按 Agent Skills 规范校正 `SKILL.md` 的 `name` / `description`。
///
/// Antigravity 要求 `name` 为 kebab-case 且与包目录同名（1–64 字符）、
/// `description` 非空（1–1024 字符）；豆包要求 `SKILL.md` 开头带 YAML 的
/// 名称与描述。两边都不限制额外字段，因此其余 frontmatter 原样保留。
class StandardSkillFrontmatter {
  const StandardSkillFrontmatter();

  static final _kebab = RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$');

  /// 由目录名（必要时回退 frontmatter 里的 name）得到合法 kebab 包名。
  static String skillNameFor(String folderName, String? frontmatterName) {
    final candidate = (frontmatterName ?? '').trim();
    if (_kebab.hasMatch(candidate)) return candidate;
    final kebab = folderName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (_kebab.hasMatch(kebab)) return kebab;
    return 'skill';
  }

  /// 校正包内 `SKILL.md`；只在确实需要时改写，返回是否写入。
  Future<bool> ensure({
    required String packageDir,
    required String name,
    int maxDescriptionLength = 1024,
  }) async {
    final file = File(p.join(packageDir, 'SKILL.md'));
    if (!await file.exists()) return false;
    final raw = await file.readAsString();
    final doc = SkillMdDocument.parse(raw);

    final description = _descriptionFor(doc, name, maxDescriptionLength);
    final nameOk = doc.name == name;
    final descriptionOk =
        doc.description != null &&
        doc.description!.trim().isNotEmpty &&
        doc.description!.length <= maxDescriptionLength;
    if (nameOk && descriptionOk) return false;

    final others = <String, String>{
      for (final entry in doc.frontmatter.entries)
        if (entry.key != 'name' && entry.key != 'description')
          entry.key: entry.value,
    };

    final buffer = StringBuffer()
      ..writeln('---')
      ..writeln('name: $name')
      ..writeln('description: ${quoteYaml(description)}');
    for (final entry in others.entries) {
      buffer.writeln('${entry.key}: ${quoteYaml(entry.value)}');
    }
    buffer.writeln('---');
    final body = doc.body.trim();
    if (body.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(body);
    }
    buffer.writeln();
    await file.writeAsString(buffer.toString());
    return true;
  }

  static String _descriptionFor(
    SkillMdDocument doc,
    String fallback,
    int maxLength,
  ) {
    final description = doc.description ?? doc.title ?? fallback;
    final normalized = description.replaceAll(RegExp(r'\s+'), ' ').trim();
    final safe = normalized.isEmpty ? fallback : normalized;
    if (safe.length <= maxLength) return safe;
    final cut = safe.substring(0, maxLength).trimRight();
    return cut.isEmpty ? fallback : cut;
  }

  /// 与 `DshCordisPatch.quote` 相同的双引号标量，避免冒号、换行破坏 YAML。
  static String quoteYaml(String value) {
    final escaped = value
        .replaceAll(r'\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll('\n', r'\n');
    return '"$escaped"';
  }
}
