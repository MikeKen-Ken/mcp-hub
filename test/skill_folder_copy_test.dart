import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_hub/features/skill_sync/skill_folder_copy.dart';
import 'package:mcp_hub/features/skill_sync/agent_resource_kind.dart';
import 'package:mcp_hub/features/skill_sync/skill_target.dart';
import 'package:path/path.dart' as p;

void main() {
  group('SkillTarget', () {
    test('tryParse', () {
      expect(SkillTarget.tryParse('cursor'), SkillTarget.cursor);
      expect(SkillTarget.tryParse('CODEX'), SkillTarget.codex);
      expect(SkillTarget.tryParse('open_code'), SkillTarget.openCode);
      expect(SkillTarget.tryParse('all'), isNull);
      expect(SkillTarget.conversionTargets, contains(SkillTarget.openCode));
      expect(SkillTarget.openCode.hasConfirmedConversionFormat, isTrue);
      expect(SkillTarget.openCode.conversionBlockReason, isNull);
    });
  });

  group('AgentResourceKind', () {
    test('uses stable remote folder names', () {
      expect(AgentResourceKind.skill.wireName, 'skills');
      expect(AgentResourceKind.command.wireName, 'commands');
      expect(AgentResourceKind.rule.wireName, 'rules');
    });

    test('WebDAV 仅 Cursor；Codex 靠本机转换', () {
      for (final resource in AgentResourceKind.values) {
        expect(resource.supportsWebDav(SkillTarget.cursor), isTrue);
        expect(resource.supportsWebDav(SkillTarget.codex), isFalse);
        expect(resource.webDavTargets.toList(), [SkillTarget.cursor]);
        expect(resource.supportedTargets.toList(), [SkillTarget.cursor]);
      }
      expect(AgentResourceKind.skill.canConvertToCodex, isTrue);
      expect(AgentResourceKind.rule.canConvertToCodex, isTrue);
      expect(AgentResourceKind.command.canConvertToCodex, isFalse);
      expect(
        AgentResourceKind.command.supportsLocalPath(SkillTarget.codex),
        isFalse,
      );
      expect(
        AgentResourceKind.skill.supportsLocalPath(SkillTarget.codex),
        isTrue,
      );
      expect(
        AgentResourceKind.skill.supportsLocalPath(SkillTarget.openCode),
        isTrue,
      );
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
      await File(p.join(skillDir.path, 'SKILL.md')).writeAsString('# demo\n');
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
      expect(
        await File(p.join(target.path, 'demo-skill', 'SKILL.md')).exists(),
        isTrue,
      );
      expect(await Directory(p.join(target.path, '.system')).exists(), isFalse);
      expect(await copy.countSkillPackages(target.path), 1);
    });

    test('全量镜像会删除目标多余项并保留点开头目录', () async {
      final source = Directory(p.join(temp.path, 'src'));
      final target = Directory(p.join(temp.path, 'dst'));
      await source.create(recursive: true);
      await target.create(recursive: true);

      final keep = Directory(p.join(source.path, 'keep-skill'));
      await keep.create();
      await File(p.join(keep.path, 'SKILL.md')).writeAsString('# keep\n');

      final stale = Directory(p.join(target.path, 'stale-skill'));
      await stale.create();
      await File(p.join(stale.path, 'SKILL.md')).writeAsString('# stale\n');

      final hidden = Directory(p.join(target.path, '.system'));
      await hidden.create();
      await File(p.join(hidden.path, 'secret')).writeAsString('keep');

      final copy = const SkillFolderCopy();
      final result = await copy.mirrorContents(
        sourceDir: source.path,
        targetDir: target.path,
      );

      expect(result.copiedFiles, 1);
      expect(result.deletedEntries, 1);
      expect(
        await Directory(p.join(target.path, 'keep-skill')).exists(),
        isTrue,
      );
      expect(
        await Directory(p.join(target.path, 'stale-skill')).exists(),
        isFalse,
      );
      expect(await Directory(p.join(target.path, '.system')).exists(), isTrue);
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
