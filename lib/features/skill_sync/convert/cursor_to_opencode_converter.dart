import 'dart:io';

import 'package:path/path.dart' as p;

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

/// 将 Cursor 的 Skill、Rule、Command 写入 OpenCode 的全局目录。
///
/// 只写 Markdown 目标文件，不读取或修改 OpenCode 的 JSON/JSONC 配置，
/// 也不删除目标目录中未由本次转换产生的文件。
class CursorToOpenCodeConverter {
  const CursorToOpenCodeConverter();

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
      skills: skills,
      rules: rules,
      commands: commands,
    );
  }

  Future<int> convertSkills({
    required String sourceDir,
    required String targetDir,
  }) async {
    final source = Directory(sourceDir);
    if (!await source.exists()) return 0;
    var count = 0;
    await for (final entity in source.list(followLinks: false)) {
      if (entity is! Directory || p.basename(entity.path).startsWith('.')) {
        continue;
      }
      final input = File(p.join(entity.path, 'SKILL.md'));
      if (!await input.exists()) continue;
      final name = p.basename(entity.path);
      final output = File(p.join(targetDir, name, 'SKILL.md'));
      await output.parent.create(recursive: true);
      await output.writeAsString(await input.readAsString());
      count++;
    }
    return count;
  }

  Future<int> convertRules({
    required String sourceDir,
    required String targetPath,
  }) async {
    final source = Directory(sourceDir);
    if (!await source.exists()) return 0;
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
    if (sections.isEmpty) return 0;
    final output = File(targetPath);
    await output.parent.create(recursive: true);
    await output.writeAsString('${sections.join('\n\n')}\n');
    return sections.length;
  }

  Future<int> convertCommands({
    required String sourceDir,
    required String targetDir,
  }) async {
    final source = Directory(sourceDir);
    if (!await source.exists()) return 0;
    var count = 0;
    await for (final entity in source.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File || p.basename(entity.path).startsWith('.')) continue;
      final extension = p.extension(entity.path).toLowerCase();
      if (extension != '.md' && extension != '.mdc') continue;
      final name = p.basenameWithoutExtension(entity.path);
      final output = File(p.join(targetDir, '$name.md'));
      await output.parent.create(recursive: true);
      await output.writeAsString(await entity.readAsString());
      count++;
    }
    return count;
  }
}
