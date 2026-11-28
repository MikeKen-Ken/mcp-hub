import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_hub/features/skill_sync/orphan_skills_cleaner.dart';
import 'package:mcp_hub/features/skill_sync/skill_target.dart';
import 'package:path/path.dart' as p;

void main() {
  group('OrphanSkillsCleaner', () {
    late Directory temp;
    const cleaner = OrphanSkillsCleaner();

    setUp(() => temp = Directory.systemTemp.createTempSync('orphan_cleaner_'));
    tearDown(() => temp.deleteSync(recursive: true));

    File file(String relative, [String content = 'x']) {
      final f = File(p.join(temp.path, relative));
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(content);
      return f;
    }

    test('scans extra skills across targets, ignores dot dirs and kebab matches', () async {
      final cursorDir = p.join(temp.path, 'cursor');
      final agyDir = p.join(temp.path, 'agy');
      final dshDir = p.join(temp.path, 'dsh');
      final wbDir = p.join(temp.path, 'wb');
      final codexCacheDir = p.join(temp.path, 'cache', 'codex');

      file('cursor/alpha/SKILL.md', '---\nname: alpha\ndescription: Alpha\n---\n');
      file('cursor/My Skill/SKILL.md', '# My Skill\n');

      // Converted versions that match Cursor should NOT be reported.
      file('agy/alpha/SKILL.md', 'ok');
      file('agy/my-skill/SKILL.md', 'ok');
      file('dsh/alpha/SKILL.md', 'ok');
      file('dsh/My Skill/SKILL.md', 'ok');

      // Dot directories must be ignored.
      file('dsh/.system/SKILL.md', 'system');

      // Real extras across multiple targets.
      file(
        'dsh/old-skill/SKILL.md',
        '---\nname: old-skill\ndescription: Old leftover skill\n---\n',
      );
      file('wb/old-skill/SKILL.md', 'old');
      file('wb/marketplace-skill/SKILL.md', 'keep');

      // Obsolete codex cache.
      file('cache/codex/legacy/SKILL.md', 'legacy');

      final scan = await cleaner.scan(
        cursorSkillsDir: cursorDir,
        targetSkillDirs: {
          SkillTarget.antigravity: agyDir,
          SkillTarget.deepSeekHarness: dshDir,
          SkillTarget.workBuddy: wbDir,
        },
        obsoleteCodexCacheDir: codexCacheDir,
      );

      expect(scan.obsoleteCodexCacheExists, isTrue);
      expect(scan.obsoleteCodexCachePath, codexCacheDir);
      expect(scan.entries.map((e) => e.name).toList(), [
        'marketplace-skill',
        'old-skill',
      ]);

      final old = scan.entries.firstWhere((e) => e.name == 'old-skill');
      expect(old.description, 'Old leftover skill');
      expect(old.locations.map((l) => l.target).toList(), [
        SkillTarget.deepSeekHarness,
        SkillTarget.workBuddy,
      ]);
    });

    test('deleteSelected deletes only checked skills and obsolete codex cache', () async {
      final cursorDir = p.join(temp.path, 'cursor');
      final dshDir = p.join(temp.path, 'dsh');
      final wbDir = p.join(temp.path, 'wb');
      final codexCacheDir = p.join(temp.path, 'cache', 'codex');

      file('cursor/alpha/SKILL.md', 'ok');
      file('dsh/old-skill/SKILL.md', 'old');
      file('wb/old-skill/SKILL.md', 'old');
      file('wb/marketplace-skill/SKILL.md', 'keep');
      file('cache/codex/legacy/SKILL.md', 'legacy');

      final scan = await cleaner.scan(
        cursorSkillsDir: cursorDir,
        targetSkillDirs: {
          SkillTarget.deepSeekHarness: dshDir,
          SkillTarget.workBuddy: wbDir,
        },
        obsoleteCodexCacheDir: codexCacheDir,
      );

      final selected = scan.entries.where((e) => e.name == 'old-skill').toList();
      final result = await cleaner.deleteSelected(
        selectedEntries: selected,
        deleteObsoleteCodexCachePath: scan.obsoleteCodexCachePath,
      );

      expect(result.ok, isTrue);
      expect(result.deletedSkillCount, 1);
      expect(result.deletedDirectoryCount, 2);
      expect(result.deletedObsoleteCodexCache, isTrue);

      expect(Directory(p.join(dshDir, 'old-skill')).existsSync(), isFalse);
      expect(Directory(p.join(wbDir, 'old-skill')).existsSync(), isFalse);
      expect(Directory(p.join(wbDir, 'marketplace-skill')).existsSync(), isTrue);
      expect(Directory(codexCacheDir).existsSync(), isFalse);
    });
  });
}
