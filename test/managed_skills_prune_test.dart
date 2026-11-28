import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_hub/features/skill_sync/convert/cursor_to_antigravity_converter.dart';
import 'package:mcp_hub/features/skill_sync/convert/cursor_to_deepseek_converter.dart';
import 'package:mcp_hub/features/skill_sync/convert/cursor_to_doubao_converter.dart';
import 'package:mcp_hub/features/skill_sync/convert/cursor_to_workbuddy_converter.dart';
import 'package:mcp_hub/features/skill_sync/convert/managed_skills_manifest.dart';
import 'package:path/path.dart' as p;

void main() {
  group('ManagedSkillsManifest', () {
    late Directory temp;
    const manifest = ManagedSkillsManifest();

    setUp(() => temp = Directory.systemTemp.createTempSync('managed_skills_'));
    tearDown(() => temp.deleteSync(recursive: true));

    Directory dir(String relative) {
      final d = Directory(p.join(temp.path, relative));
      d.createSync(recursive: true);
      return d;
    }

    File file(String relative, [String content = 'x']) {
      final f = File(p.join(temp.path, relative));
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(content);
      return f;
    }

    test('prunes only previously managed skills and preserves others', () async {
      final target = dir('target').path;
      file('target/alpha/SKILL.md', 'a');
      file('target/beta/SKILL.md', 'b');
      file('target/marketplace/SKILL.md', 'm');
      file('target/.system/SKILL.md', 's');

      final firstRemoved = await manifest.syncAndPrune(
        targetDir: target,
        scope: 'test-scope',
        currentManagedNames: {'alpha', 'beta'},
      );
      expect(firstRemoved, 0);

      final secondRemoved = await manifest.syncAndPrune(
        targetDir: target,
        scope: 'test-scope',
        currentManagedNames: {'alpha'},
      );
      expect(secondRemoved, 1);
      expect(Directory(p.join(target, 'alpha')).existsSync(), isTrue);
      expect(Directory(p.join(target, 'beta')).existsSync(), isFalse);
      expect(Directory(p.join(target, 'marketplace')).existsSync(), isTrue);
      expect(Directory(p.join(target, '.system')).existsSync(), isTrue);
    });

    test('keeps failed skills and preserves unrelated scopes', () async {
      final target = dir('target').path;
      file('target/alpha/SKILL.md', 'a');
      file('target/flaky/SKILL.md', 'f');
      file(
        'target/${ManagedSkillsManifest.fileName}',
        jsonEncode({
          'version': 1,
          'scopes': {
            'other-scope': ['keep-me'],
            'test-scope': ['alpha', 'flaky'],
          },
        }),
      );

      final removed = await manifest.syncAndPrune(
        targetDir: target,
        scope: 'test-scope',
        currentManagedNames: {'alpha'},
        failedNames: {'flaky'},
      );
      expect(removed, 0);
      expect(Directory(p.join(target, 'flaky')).existsSync(), isTrue);

      final raw = File(
        p.join(target, ManagedSkillsManifest.fileName),
      ).readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final scopes = decoded['scopes'] as Map<String, dynamic>;
      expect(scopes['other-scope'], ['keep-me']);
      expect(scopes['test-scope'], ['alpha', 'flaky']);
    });

    test('tolerates corrupt manifest JSON without throwing', () async {
      final target = dir('target').path;
      file('target/alpha/SKILL.md', 'a');
      file('target/${ManagedSkillsManifest.fileName}', '{corrupt json');

      final removed = await manifest.syncAndPrune(
        targetDir: target,
        scope: 'test-scope',
        currentManagedNames: {'alpha'},
      );
      expect(removed, 0);
      expect(Directory(p.join(target, 'alpha')).existsSync(), isTrue);
    });
  });

  group('Converters prune deleted Cursor skills while keeping unmanaged ones', () {
    late Directory temp;

    setUp(() => temp = Directory.systemTemp.createTempSync('conv_prune_'));
    tearDown(() => temp.deleteSync(recursive: true));

    File file(String relative, [String content = 'x']) {
      final f = File(p.join(temp.path, relative));
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(content);
      return f;
    }

    Future<void> verifyConverterPrune({
      required String name,
      required Future<int> Function(String sourceDir, String targetDir) run,
    }) async {
      final sourceDir = p.join(temp.path, name, 'cursor');
      final targetDir = p.join(temp.path, name, 'target');

      file(
        '$name/cursor/alpha/SKILL.md',
        '---\nname: alpha\ndescription: Alpha\n---\n\n# Alpha\n',
      );
      file(
        '$name/cursor/beta/SKILL.md',
        '---\nname: beta\ndescription: Beta\n---\n\n# Beta\n',
      );
      file('$name/target/marketplace-skill/SKILL.md', 'built-in');

      expect(await run(sourceDir, targetDir), 0);
      expect(Directory(p.join(targetDir, 'alpha')).existsSync(), isTrue);
      expect(Directory(p.join(targetDir, 'beta')).existsSync(), isTrue);
      expect(
        Directory(p.join(targetDir, 'marketplace-skill')).existsSync(),
        isTrue,
      );

      // Delete beta and rename alpha -> alpha-v2 in Cursor.
      Directory(p.join(sourceDir, 'beta')).deleteSync(recursive: true);
      Directory(p.join(sourceDir, 'alpha')).deleteSync(recursive: true);
      file(
        '$name/cursor/alpha-v2/SKILL.md',
        '---\nname: alpha-v2\ndescription: Alpha V2\n---\n\n# Alpha V2\n',
      );

      expect(await run(sourceDir, targetDir), 2);
      expect(Directory(p.join(targetDir, 'alpha')).existsSync(), isFalse);
      expect(Directory(p.join(targetDir, 'beta')).existsSync(), isFalse);
      expect(Directory(p.join(targetDir, 'alpha-v2')).existsSync(), isTrue);
      expect(
        Directory(p.join(targetDir, 'marketplace-skill')).existsSync(),
        isTrue,
      );

      // Remove last Cursor skill -> managed alpha-v2 removed, marketplace kept.
      Directory(p.join(sourceDir, 'alpha-v2')).deleteSync(recursive: true);
      expect(await run(sourceDir, targetDir), 1);
      expect(Directory(p.join(targetDir, 'alpha-v2')).existsSync(), isFalse);
      expect(
        Directory(p.join(targetDir, 'marketplace-skill')).existsSync(),
        isTrue,
      );
    }

    test('CursorToAntigravityConverter', () async {
      const converter = CursorToAntigravityConverter();
      await verifyConverterPrune(
        name: 'antigravity',
        run: (s, t) async =>
            (await converter.convertSkills(sourceDir: s, targetDir: t))
                .removedPackages,
      );
    });

    test('CursorToDeepSeekConverter', () async {
      const converter = CursorToDeepSeekConverter();
      await verifyConverterPrune(
        name: 'deepseek',
        run: (s, t) async =>
            (await converter.convertSkills(sourceDir: s, targetDir: t))
                .removedPackages,
      );
    });

    test('CursorToWorkBuddyConverter', () async {
      const converter = CursorToWorkBuddyConverter();
      await verifyConverterPrune(
        name: 'workbuddy',
        run: (s, t) async =>
            (await converter.convertSkills(sourceDir: s, targetDir: t))
                .removedPackages,
      );
    });

    test('CursorToDoubaoConverter', () async {
      const converter = CursorToDoubaoConverter();
      await verifyConverterPrune(
        name: 'doubao',
        run: (s, t) async =>
            (await converter.convertSkills(sourceDir: s, targetDir: t))
                .removedPackages,
      );
    });
  });
}
