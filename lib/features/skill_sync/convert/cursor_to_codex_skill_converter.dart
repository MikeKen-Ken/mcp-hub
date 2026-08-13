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
    required this.deletedEntries,
    required this.wroteOpenAiYaml,
  });

  final String packageName;
  final String targetDir;
  final int copiedFiles;
  final int deletedEntries;
  final bool wroteOpenAiYaml;
}

/// 批量转换结果（含删除的多余包）。
class CodexSkillConvertAllResult {
  const CodexSkillConvertAllResult({
    required this.items,
    this.removedPackages = 0,
  });

  final List<CodexSkillConvertItem> items;
  final int removedPackages;
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
  ///
  /// 每个包全量镜像（含 `scripts/`、`references/` 等），再写入 `agents/openai.yaml`；
  /// 目标侧已不在 Cursor 中的包与多余文件会删除。
  Future<CodexSkillConvertAllResult> convertAll({
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
    final removedPackages = await folderCopy.removeStaleSkillPackages(
      sourceSkillsDir: cursorSkillsDir,
      targetSkillsDir: codexSkillsDir,
    );
    return CodexSkillConvertAllResult(
      items: items,
      removedPackages: removedPackages,
    );
  }

  /// 转换单个 Skill 包。
  Future<CodexSkillConvertItem> convertOne({
    required String cursorSkillDir,
    required String codexSkillsDir,
  }) async {
    final packageName = skillPackageNameFromPath(cursorSkillDir);
    final targetDir = p.join(codexSkillsDir, packageName);

    final copy = await folderCopy.mirrorContents(
      sourceDir: cursorSkillDir,
      targetDir: targetDir,
      preserveNames: const {'agents'},
    );

    final skillMdPath = p.join(targetDir, 'SKILL.md');
    final doc = await SkillMdDocument.parseFile(skillMdPath);
    // 以 Cursor 为准：每次覆盖 Codex 隐式调用开关，不保留旧 yaml。
    final allowImplicit =
        doc.allowImplicitInvocationFromFrontmatter ?? true;
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
      deletedEntries: copy.deletedEntries,
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

  /// Codex 要求界面短描述 25–64 字。
  static const int shortDescriptionMin = 25;
  static const int shortDescriptionMax = 64;
  static final _blockMarker = RegExp(r'^[>|][+-]?$');

  static String _shortDescription(String raw) {
    final original = raw.trim();
    if (original.isEmpty || _blockMarker.hasMatch(original)) {
      return _fitShortDescription('');
    }
    var cleaned = original
        .replaceFirst(RegExp(r'[。．\.].*用户要求.*$'), '')
        .replaceFirst(RegExp(r'。用户要求.*$'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    var first = cleaned;
    final match = RegExp(r'[。．\.！!？?]').firstMatch(cleaned);
    if (match != null && match.start > 0) {
      first = cleaned.substring(0, match.start).trim();
    }
    return _fitShortDescription(first, fallbacks: [cleaned, original]);
  }

  static String _fitShortDescription(
    String preferred, {
    List<String> fallbacks = const [],
  }) {
    for (final candidate in [preferred, ...fallbacks]) {
      final text = candidate.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text.isEmpty || _blockMarker.hasMatch(text)) continue;
      if (text.length > shortDescriptionMax) {
        return '${text.substring(0, shortDescriptionMax - 1).trimRight()}…';
      }
      if (text.length >= shortDescriptionMin) return text;
    }

    var grown = preferred.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (grown.isEmpty || _blockMarker.hasMatch(grown)) {
      grown = '技能工作流';
    }
    const pad = '。用于相关任务与工作流';
    while (grown.length < shortDescriptionMin) {
      grown += pad;
    }
    if (grown.length > shortDescriptionMax) {
      grown = grown.substring(0, shortDescriptionMax);
    }
    return grown;
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
