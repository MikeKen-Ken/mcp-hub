import 'dart:io';

import 'package:path/path.dart' as p;

import '../skill_folder_copy.dart';
import 'skill_md_document.dart';

/// 单个 Skill 包 Cursor → Codex 的转换结果。
class CodexSkillConvertItem {
  const CodexSkillConvertItem({
    required this.packageName,
    required this.targetDir,
    required this.copiedFiles,
    required this.wroteOpenAiYaml,
  });

  final String packageName;
  final String targetDir;
  final int copiedFiles;
  final bool wroteOpenAiYaml;
}

/// 批量把 Cursor Skill 目录转换成 Codex 可接受的包格式并复制过去。
///
/// Cursor / Codex 都使用含 `SKILL.md` 的子目录；Codex 额外需要
/// `agents/openai.yaml`（界面名、短描述、默认提示、是否允许隐式调用）。
class CursorToCodexSkillConverter {
  const CursorToCodexSkillConverter({
    this.folderCopy = const SkillFolderCopy(),
  });

  final SkillFolderCopy folderCopy;

  /// 批量转换 [cursorSkillsDir] 下全部 Skill 包到 [codexSkillsDir]。
  Future<List<CodexSkillConvertItem>> convertAll({
    required String cursorSkillsDir,
    required String codexSkillsDir,
  }) async {
    final sourceRoot = Directory(cursorSkillsDir);
    if (!await sourceRoot.exists()) {
      throw StateError('Cursor Skill 目录不存在：$cursorSkillsDir');
    }

    await Directory(codexSkillsDir).create(recursive: true);

    final items = <CodexSkillConvertItem>[];
    await for (final entity in sourceRoot.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final name = p.basename(entity.path);
      if (name.startsWith('.')) continue;

      final skillMd = File(p.join(entity.path, 'SKILL.md'));
      if (!await skillMd.exists()) continue;

      items.add(
        await convertOne(
          cursorSkillDir: entity.path,
          codexSkillsDir: codexSkillsDir,
        ),
      );
    }

    items.sort((a, b) => a.packageName.compareTo(b.packageName));
    return items;
  }

  /// 转换单个 Skill 包。
  Future<CodexSkillConvertItem> convertOne({
    required String cursorSkillDir,
    required String codexSkillsDir,
  }) async {
    final packageName = skillPackageNameFromPath(cursorSkillDir);
    final targetDir = p.join(codexSkillsDir, packageName);

    final copy = await folderCopy.copyContents(
      sourceDir: cursorSkillDir,
      targetDir: targetDir,
    );

    final skillMdPath = p.join(targetDir, 'SKILL.md');
    final doc = await SkillMdDocument.parseFile(skillMdPath);
    // 已有 Codex 策略优先；否则用 Cursor `disable-model-invocation` 推导。
    final allowImplicit = await _readExistingAllowImplicit(targetDir) ??
        doc.allowImplicitInvocationFromFrontmatter;
    final yaml = buildOpenAiYaml(
      packageName: packageName,
      document: doc,
      allowImplicitInvocation: allowImplicit,
    );

    final yamlPath = p.join(targetDir, 'agents', 'openai.yaml');
    await File(yamlPath).parent.create(recursive: true);
    await File(yamlPath).writeAsString(yaml);

    return CodexSkillConvertItem(
      packageName: packageName,
      targetDir: targetDir,
      copiedFiles: copy.copiedFiles,
      wroteOpenAiYaml: true,
    );
  }

  /// 生成 Codex `agents/openai.yaml` 内容。
  static String buildOpenAiYaml({
    required String packageName,
    required SkillMdDocument document,
    bool? allowImplicitInvocation,
  }) {
    final displayName =
        document.title ?? document.name ?? packageName;
    final shortDescription = _shortDescription(
      document.description ?? document.title ?? packageName,
    );
    final defaultPrompt = _defaultPrompt(
      packageName: packageName,
      displayName: displayName,
      description: document.description,
    );
    final allow = allowImplicitInvocation ?? true;

    final buffer = StringBuffer()
      ..writeln('interface:')
      ..writeln('  display_name: ${_yamlQuote(displayName)}')
      ..writeln('  short_description: ${_yamlQuote(shortDescription)}')
      ..writeln('  default_prompt: ${_yamlQuote(defaultPrompt)}')
      ..writeln()
      ..writeln('policy:')
      ..writeln('  allow_implicit_invocation: $allow')
      ..writeln();
    return buffer.toString();
  }

  static Future<bool?> _readExistingAllowImplicit(String targetDir) async {
    final yamlFile = File(p.join(targetDir, 'agents', 'openai.yaml'));
    if (!await yamlFile.exists()) return null;
    final text = await yamlFile.readAsString();
    final match = RegExp(
      r'allow_implicit_invocation\s*:\s*(true|false)',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) return null;
    return match.group(1)!.toLowerCase() == 'true';
  }

  static String _shortDescription(String raw) {
    var text = raw.trim();
    // 去掉「用户要求…时使用」这类触发说明，保留能力摘要。
    text = text.replaceFirst(RegExp(r'[。．\.].*用户要求.*$'), '');
    text = text.replaceFirst(RegExp(r'。用户要求.*$'), '');
    final sentenceEnd = RegExp(r'[。．\.！!？?]');
    final match = sentenceEnd.firstMatch(text);
    if (match != null && match.start > 0) {
      text = text.substring(0, match.start);
    }
    text = text.trim();
    if (text.length > 48) {
      text = '${text.substring(0, 48).trimRight()}…';
    }
    return text.isEmpty ? raw.trim() : text;
  }

  static String _defaultPrompt({
    required String packageName,
    required String displayName,
    String? description,
  }) {
    final hint = displayName.trim().isNotEmpty
        ? displayName.trim()
        : (description?.trim().isNotEmpty == true
            ? _shortDescription(description!)
            : packageName);
    return '使用 \$$packageName 完成「$hint」。';
  }

  static String _yamlQuote(String value) {
    final escaped = value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    return '"$escaped"';
  }
}
