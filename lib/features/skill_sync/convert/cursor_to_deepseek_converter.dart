import 'dart:io';

import 'package:path/path.dart' as p;

import '../skill_folder_copy.dart';
import 'cursor_rule_markdown.dart';
import 'skill_md_document.dart';

/// Skill 转换结果。
class DeepSeekSkillsConvertResult {
  const DeepSeekSkillsConvertResult({
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

/// 将 Cursor 的 Skill、Rule 写入 DeepSeek Harness 的用户目录。
///
/// Skill 仍是 `SKILL.md` 包。Harness 要求 frontmatter 的 `name` 为 kebab-case
/// 且带 `description`，缺了会被忽略，所以只在不满足时改写 `SKILL.md`。
/// 目标目录里 Cursor 没有的 Skill 会保留。
///
/// Rule 写入 `AGENTS.md` 的标记段。标记以外的文字保持不动。
class CursorToDeepSeekConverter {
  const CursorToDeepSeekConverter({this.folderCopy = const SkillFolderCopy()});

  static const rulesBegin = '<!-- mcp-hub:cursor-rules:begin -->';
  static const rulesEnd = '<!-- mcp-hub:cursor-rules:end -->';

  static final _skillName = RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$');
  static const _legacyKeys = {
    'disableModelInvocation',
    'modelInvocable',
    'userInvocable',
  };

  final SkillFolderCopy folderCopy;

  Future<DeepSeekSkillsConvertResult> convertSkills({
    required String sourceDir,
    required String targetDir,
  }) async {
    final source = Directory(sourceDir);
    if (!await source.exists()) {
      return const DeepSeekSkillsConvertResult(
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
      final name = p.basename(entity.path);
      try {
        final mirrored = await folderCopy.mirrorContents(
          sourceDir: entity.path,
          targetDir: p.join(targetDir, name),
        );
        if (await _ensureSkillFrontmatter(p.join(targetDir, name))) {
          rewrittenSkills += 1;
        }
        packages += 1;
        copiedFiles += mirrored.copiedFiles;
        deletedEntries += mirrored.deletedEntries;
      } catch (error) {
        errors.add('$name: $error');
      }
    }
    return DeepSeekSkillsConvertResult(
      packages: packages,
      copiedFiles: copiedFiles,
      deletedEntries: deletedEntries,
      rewrittenSkills: rewrittenSkills,
      errors: errors,
    );
  }

  /// 把全局 Cursor `.mdc` / `.md` 规则写入 [agentsMdPath] 的标记段，返回写入条数。
  Future<int> convertRules({
    required String sourceDir,
    required String agentsMdPath,
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
        'DeepSeek Harness loads this file as the user-global `AGENTS.md`. '
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

    final file = File(agentsMdPath);
    final existing = await file.exists() ? await file.readAsString() : '';
    await file.parent.create(recursive: true);
    await file.writeAsString(
      CursorRuleMarkdown.mergeMarked(
        existing,
        managed.toString().trimRight(),
        beginMarker: rulesBegin,
        endMarker: rulesEnd,
        targetName: 'AGENTS.md',
      ),
    );
    return sections.length;
  }

  Future<bool> _ensureSkillFrontmatter(String packageDir) async {
    final file = File(p.join(packageDir, 'SKILL.md'));
    final raw = await file.readAsString();
    final doc = SkillMdDocument.parse(raw);
    final folder = p.basename(packageDir);
    final name = skillNameFor(folder, doc.name);
    final description = doc.description ?? doc.title ?? name;
    final legacy = doc.frontmatter.keys.any(_legacyKeys.contains);
    final nameOk = doc.name != null && _skillName.hasMatch(doc.name!);
    final descriptionOk =
        doc.description != null && doc.description!.isNotEmpty;
    if (nameOk && descriptionOk && !legacy) return false;

    final buffer = StringBuffer()..writeln('---');
    buffer.writeln('name: $name');
    buffer.writeln('description: ${DshYaml.quote(description)}');
    final disable = _invocationBool(
      doc.frontmatter,
      canonical: 'disable-model-invocation',
      legacy: 'disableModelInvocation',
      invertedLegacy: 'modelInvocable',
    );
    final userInvocable = _invocationBool(
      doc.frontmatter,
      canonical: 'user-invocable',
      legacy: 'userInvocable',
    );
    if (disable != null) buffer.writeln('disable-model-invocation: $disable');
    if (userInvocable != null) buffer.writeln('user-invocable: $userInvocable');
    const handledKeys = {
      'name',
      'description',
      'disable-model-invocation',
      'user-invocable',
      ..._legacyKeys,
    };
    for (final entry in doc.frontmatter.entries) {
      if (handledKeys.contains(entry.key)) continue;
      final rawEntry = doc.rawEntries[entry.key];
      if (rawEntry != null && rawEntry.isNotEmpty) {
        buffer.writeln(rawEntry);
      } else {
        buffer.writeln('${entry.key}: ${DshYaml.quote(entry.value)}');
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
    await file.writeAsString(buffer.toString());
    return true;
  }

  bool? _invocationBool(
    Map<String, String> frontmatter, {
    required String canonical,
    required String legacy,
    String? invertedLegacy,
  }) {
    final direct = _parseBool(frontmatter[canonical]);
    if (direct != null) return direct;
    final fromLegacy = _parseBool(frontmatter[legacy]);
    if (fromLegacy != null) return fromLegacy;
    if (invertedLegacy == null) return null;
    final inverted = _parseBool(frontmatter[invertedLegacy]);
    if (inverted == null) return null;
    return !inverted;
  }

  bool? _parseBool(String? raw) {
    return switch (raw?.trim().toLowerCase()) {
      'true' || 'yes' || 'on' || '1' => true,
      'false' || 'no' || 'off' || '0' => false,
      _ => null,
    };
  }

  static String skillNameFor(String folderName, String? frontmatterName) {
    if (frontmatterName != null && _skillName.hasMatch(frontmatterName)) {
      return frontmatterName;
    }
    final kebab = folderName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (_skillName.hasMatch(kebab)) return kebab;
    return 'skill';
  }
}

/// 与 [DshCordisPatch.quote] 相同的双引号标量，避免 Skill 描述里的冒号被当成 YAML。
abstract final class DshYaml {
  static String quote(String value) {
    final escaped = value
        .replaceAll(r'\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll('\n', r'\n');
    return '"$escaped"';
  }
}
