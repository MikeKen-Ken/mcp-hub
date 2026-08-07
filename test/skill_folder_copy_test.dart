import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_hub/features/skill_sync/skill_folder_copy.dart';
import 'package:mcp_hub/features/skill_sync/skill_target.dart';
import 'package:path/path.dart' as p;

void main() {
  group('SkillTarget', () {
    test('tryParse', () {
      expect(SkillTarget.tryParse('cursor'), SkillTarget.cursor);
      expect(SkillTarget.tryParse('CODEX'), SkillTarget.codex);
      expect(SkillTarget.tryParse('all'), isNull);
    });
  });

  group('SkillFolderCopy', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('skill_folder_copy_');
    });

    tearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    test('复制内容并跳过点开头目录', () async {
      final source = Directory(p.join(temp.path, 'src'));
      final target = Directory(p.join(temp.path, 'dst'));
      await source.create(recursive: true);

      final skillDir = Directory(p.join(source.path, 'demo-skill'));
      await skillDir.create();
      await File(p.join(skillDir.path, 'SKILL.md'))
          .writeAsString('# demo\n');
      await File(p.join(skillDir.path, 'notes.txt')).writeAsString('x');

      final hidden = Directory(p.join(source.path, '.system'));
      await hidden.create();
      await File(p.join(hidden.path, 'secret')).writeAsString('no');

      final copy = const SkillFolderCopy();
      final result = await copy.copyContents(
        sourceDir: source.path,
        targetDir: target.path,
      );

      expect(result.copiedFiles, 2);
      expect(await File(p.join(target.path, 'demo-skill', 'SKILL.md')).exists(),
          isTrue);
      expect(await Directory(p.join(target.path, '.system')).exists(), isFalse);
      expect(await copy.countSkillPackages(target.path), 1);
    });

    test('源目录不存在时抛错', () async {
      final copy = const SkillFolderCopy();
      expect(
        () => copy.copyContents(
          sourceDir: p.join(temp.path, 'missing'),
          targetDir: p.join(temp.path, 'out'),
        ),
        throwsStateError,
      );
    });
  });
}
