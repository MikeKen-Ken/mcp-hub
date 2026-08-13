import 'dart:io';

import 'package:path/path.dart' as p;

import '../skill_folder_copy.dart';
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
  });

  final int packages;
  final int copiedFiles;
  final int deletedEntries;
  final int removedPackages;
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
/// Rule 去掉 `.mdc` frontmatter 写入 `AGENTS.md`；Command 写成 `.md`。
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
    await for (final entity in source.list(followLinks: false)) {
      if (entity is! Directory || p.basename(entity.path).startsWith('.')) {
        continue;
      }
      final skillMd = File(p.join(entity.path, 'SKILL.md'));
      if (!await skillMd.exists()) continue;
      final name = p.basename(entity.path);
      final packageDir = p.join(targetDir, name);
      final mirrored = await folderCopy.mirrorContents(
        sourceDir: entity.path,
        targetDir: packageDir,
      );
      await _rewriteOpenCodeSkillMd(packageDir);
      packages += 1;
      copiedFiles += mirrored.copiedFiles;
      deletedEntries += mirrored.deletedEntries;
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
    final files = <File>[];
    await for (final entity in source.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File && p.extension(entity.path).toLowerCase() == '.mdc') {
        files.add(entity);
      }
    }
    files.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
    final sections = <String>[];
    for (final file in files) {
      final doc = await SkillMdDocument.parseFile(file.path);
      final body = doc.body.trim();
      if (body.isEmpty) continue;
      sections.add(body);
    }
    if (sections.isEmpty) {
      await output.writeAsString('');
      return 0;
    }
    await output.writeAsString('${sections.join('\n\n')}\n');
    return sections.length;
  }

  /// 写入转换后的 Command，并删除目标侧多余的 `.md` / `.mdc`。
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
      if (entity is! File || p.basename(entity.path).startsWith('.')) continue;
      final extension = p.extension(entity.path).toLowerCase();
      if (extension != '.md' && extension != '.mdc') continue;
      final name = p.basenameWithoutExtension(entity.path);
      final outputName = '$name.md';
      final output = File(p.join(targetDir, outputName));
      await output.parent.create(recursive: true);
      await output.writeAsString(await entity.readAsString());
      written.add(outputName);
      count++;
    }
    final deleted = await _deleteExtraCommandFiles(
      targetDir: targetDir,
      keepNames: written,
    );
    return OpenCodeCommandsConvertResult(written: count, deleted: deleted);
  }

  Future<int> _deleteExtraCommandFiles({
    required String targetDir,
    required Set<String> keepNames,
  }) async {
    final target = Directory(targetDir);
    if (!await target.exists()) return 0;
    var deleted = 0;
    await for (final entity in target.list(followLinks: false)) {
      final name = p.basename(entity.path);
      if (name.startsWith('.')) continue;
      if (keepNames.contains(name)) continue;
      if (entity is File) {
        final ext = p.extension(name).toLowerCase();
        if (ext != '.md' && ext != '.mdc') continue;
      }
      await entity.delete(recursive: true);
      deleted += 1;
    }
    return deleted;
  }
}
