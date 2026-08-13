import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_hub/features/skill_sync/convert/cursor_to_codex_agents_converter.dart';
import 'package:mcp_hub/features/skill_sync/convert/cursor_to_codex_skill_converter.dart';
import 'package:mcp_hub/features/skill_sync/convert/skill_md_document.dart';
import 'package:path/path.dart' as p;

void main() {
  group('SkillMdDocument', () {
    test('解析 name/description 与一级标题', () {
      const raw = '''
---
name: daily-report
description: 根据提交生成日报。用户要求生成日报时使用。
---

# 生成工作日报

正文
''';
      final doc = SkillMdDocument.parse(raw);
      expect(doc.name, 'daily-report');
      expect(doc.description, contains('根据提交生成日报'));
      expect(doc.title, '生成工作日报');
      expect(doc.body, startsWith('# 生成工作日报'));
      expect(doc.disableModelInvocation, isNull);
      expect(doc.allowImplicitInvocationFromFrontmatter, isNull);
    });

    test('解析 description: >- 折行，且不把正文里的 name: 当成新键', () {
      final doc = SkillMdDocument.parse('''
---
name: kanban-complete-tasks
description: >-
  完成看板最新一张卡：自动区分咨询、实施与返工，提交 Git 后送交人工确认，不推送。
  支持直接输入项目名或 name:<项目名或id>；无参数时使用看板当前打开的项目。
disable-model-invocation: true
---

# 看板：做最新一条
''');
      expect(doc.description, contains('完成看板最新一张卡'));
      expect(doc.description, contains('name:<项目名或id>'));
      expect(doc.description, isNot(equals('>-')));
      expect(doc.disableModelInvocation, isTrue);
      expect(doc.allowImplicitInvocationFromFrontmatter, isFalse);
    });

    test('解析 disable-model-invocation 并推导 Codex 策略', () {
      final disabled = SkillMdDocument.parse('''
---
name: gated
disable-model-invocation: true
---

# 需显式调用
''');
      expect(disabled.disableModelInvocation, isTrue);
      expect(disabled.allowImplicitInvocationFromFrontmatter, isFalse);

      final enabled = SkillMdDocument.parse('''
---
name: open
disable-model-invocation: false
---

# 可隐式调用
''');
      expect(enabled.disableModelInvocation, isFalse);
      expect(enabled.allowImplicitInvocationFromFrontmatter, isTrue);
    });
  });

  group('CursorToCodexSkillConverter', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('skill_convert_');
    });

    tearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    test('批量复制并生成 openai.yaml', () async {
      final cursor = Directory(p.join(temp.path, 'cursor'));
      final codex = Directory(p.join(temp.path, 'codex'));
      final pack = Directory(p.join(cursor.path, 'daily-report'));
      await pack.create(recursive: true);
      await File(p.join(pack.path, 'SKILL.md')).writeAsString('''
---
name: daily-report
description: 根据当天提交生成分层日报并展示预览。用户要求生成或预览今日日报时使用。
---

# 生成工作日报

步骤
''');
      await File(p.join(pack.path, 'notes.txt')).writeAsString('x');

      final converter = const CursorToCodexSkillConverter();
      final converted = await converter.convertAll(
        cursorSkillsDir: cursor.path,
        codexSkillsDir: codex.path,
      );

      expect(converted.items, hasLength(1));
      expect(converted.items.single.packageName, 'daily-report');
      expect(
        await File(p.join(codex.path, 'daily-report', 'SKILL.md')).exists(),
        isTrue,
      );
      expect(
        await File(p.join(codex.path, 'daily-report', 'notes.txt')).exists(),
        isTrue,
      );

      final yaml = await File(
        p.join(codex.path, 'daily-report', 'agents', 'openai.yaml'),
      ).readAsString();
      expect(yaml, contains('display_name: "生成工作日报"'));
      expect(yaml, contains(r'default_prompt: "使用 $daily-report'));
      expect(yaml, contains('allow_implicit_invocation: true'));
      expect(_shortDescriptionOf(yaml), isNot(equals('>-')));
      expect(
        _shortDescriptionOf(yaml).length,
        inInclusiveRange(
          CursorToCodexSkillConverter.shortDescriptionMin,
          CursorToCodexSkillConverter.shortDescriptionMax,
        ),
      );
    });

    test('包内多余文件与多余包会按 Cursor 删除', () async {
      final cursor = Directory(p.join(temp.path, 'cursor-mirror'));
      final codex = Directory(p.join(temp.path, 'codex-mirror'));
      final pack = Directory(p.join(cursor.path, 'daily-report'));
      await Directory(p.join(pack.path, 'scripts')).create(recursive: true);
      await File(p.join(pack.path, 'SKILL.md')).writeAsString('# 日报\n');
      await File(p.join(pack.path, 'scripts', 'report.py')).writeAsString('x');

      final stalePack = Directory(p.join(codex.path, 'old-skill'));
      await stalePack.create(recursive: true);
      await File(p.join(stalePack.path, 'SKILL.md')).writeAsString('# old\n');
      final live = Directory(p.join(codex.path, 'daily-report', 'scripts'));
      await live.create(recursive: true);
      await File(p.join(live.path, 'report.py')).writeAsString('old');
      await File(p.join(live.path, 'gone.py')).writeAsString('stale');

      final converted = await const CursorToCodexSkillConverter().convertAll(
        cursorSkillsDir: cursor.path,
        codexSkillsDir: codex.path,
      );

      expect(converted.removedPackages, 1);
      expect(await Directory(stalePack.path).exists(), isFalse);
      expect(
        await File(
          p.join(codex.path, 'daily-report', 'scripts', 'report.py'),
        ).exists(),
        isTrue,
      );
      expect(
        await File(
          p.join(codex.path, 'daily-report', 'scripts', 'gone.py'),
        ).exists(),
        isFalse,
      );
      expect(
        await File(
          p.join(codex.path, 'daily-report', 'agents', 'openai.yaml'),
        ).exists(),
        isTrue,
      );
    });

    test('首次转换时映射 disable-model-invocation', () async {
      final cursor = Directory(p.join(temp.path, 'cursor-disable'));
      final codex = Directory(p.join(temp.path, 'codex-disable'));
      final pack = Directory(p.join(cursor.path, 'gated-skill'));
      await pack.create(recursive: true);
      await File(p.join(pack.path, 'SKILL.md')).writeAsString('''
---
name: gated-skill
description: 仅显式调用
disable-model-invocation: true
---

# 需显式调用
''');

      await const CursorToCodexSkillConverter().convertAll(
        cursorSkillsDir: cursor.path,
        codexSkillsDir: codex.path,
      );

      final yaml = await File(
        p.join(codex.path, 'gated-skill', 'agents', 'openai.yaml'),
      ).readAsString();
      expect(yaml, contains('allow_implicit_invocation: false'));
    });

    test('以 Cursor 为准覆盖已有 allow_implicit_invocation', () async {
      final cursor = Directory(p.join(temp.path, 'cursor2'));
      final codex = Directory(p.join(temp.path, 'codex2'));
      final pack = Directory(p.join(cursor.path, 'demo'));
      await pack.create(recursive: true);
      await File(p.join(pack.path, 'SKILL.md')).writeAsString('''
---
name: demo
description: 演示技能
disable-model-invocation: true
---

# 演示
''');
      final existing = File(p.join(codex.path, 'demo', 'agents', 'openai.yaml'));
      await existing.parent.create(recursive: true);
      await existing.writeAsString('''
interface:
  display_name: "旧"
policy:
  allow_implicit_invocation: true
''');

      await const CursorToCodexSkillConverter().convertAll(
        cursorSkillsDir: cursor.path,
        codexSkillsDir: codex.path,
      );

      final yaml = await existing.readAsString();
      expect(yaml, contains('allow_implicit_invocation: false'));
      expect(yaml, contains('display_name: "演示"'));
    });

    test('折行 description 生成合法 short_description 且禁止隐式调用', () async {
      final cursor = Directory(p.join(temp.path, 'cursor-fold'));
      final codex = Directory(p.join(temp.path, 'codex-fold'));
      final pack = Directory(p.join(cursor.path, 'kanban-complete-tasks'));
      await pack.create(recursive: true);
      await File(p.join(pack.path, 'SKILL.md')).writeAsString('''
---
name: kanban-complete-tasks
description: >-
  完成看板最新一张卡：自动区分咨询、实施与返工，提交 Git 后送交人工确认，不推送。
  支持直接输入项目名或 name:<项目名或id>；无参数时使用看板当前打开的项目。
disable-model-invocation: true
---

# 看板：做最新一条
''');

      await const CursorToCodexSkillConverter().convertAll(
        cursorSkillsDir: cursor.path,
        codexSkillsDir: codex.path,
      );

      final yaml = await File(
        p.join(codex.path, 'kanban-complete-tasks', 'agents', 'openai.yaml'),
      ).readAsString();
      final short = _shortDescriptionOf(yaml);
      expect(short, isNot(equals('>-')));
      expect(short, contains('完成看板'));
      expect(
        short.length,
        inInclusiveRange(
          CursorToCodexSkillConverter.shortDescriptionMin,
          CursorToCodexSkillConverter.shortDescriptionMax,
        ),
      );
      expect(yaml, contains('allow_implicit_invocation: false'));
      expect(yaml, contains(r'default_prompt: "使用 $kanban-complete-tasks'));
    });
  });

  group('CursorToCodexAgentsConverter', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('agents_convert_');
    });

    tearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    test('批量把 mdc 写入 AGENTS.md', () async {
      final rules = Directory(p.join(temp.path, 'rules'));
      await Directory(p.join(rules.path, 'common')).create(recursive: true);
      await File(p.join(rules.path, 'common', 'language.mdc')).writeAsString('''
---
alwaysApply: true
---
# 语言规则
- MUST 使用简体中文回复。
''');
      await File(p.join(rules.path, 'common', 'paths.mdc')).writeAsString('''
---
description: 路径规则
alwaysApply: true
---
# 本地路径规则
- 使用环境变量。
''');

      final out = p.join(temp.path, 'AGENTS.md');
      final items = await const CursorToCodexAgentsConverter().convertAll(
        cursorRulesDir: rules.path,
        agentsMdPath: out,
      );

      expect(items, hasLength(2));
      final text = await File(out).readAsString();
      expect(text, startsWith('# 全局工作规则'));
      expect(text, contains('## 语言规则'));
      expect(text, contains('## 本地路径规则'));
      expect(text, contains('MUST 使用简体中文回复'));
      expect(text, isNot(contains('alwaysApply')));
    });
  });
}

String _shortDescriptionOf(String yaml) {
  final match = RegExp(r'short_description:\s*"((?:\\.|[^"\\])*)"').firstMatch(yaml);
  expect(match, isNotNull, reason: 'openai.yaml 缺少 short_description');
  return match!.group(1)!.replaceAll(r'\"', '"').replaceAll(r'\\', r'\');
}
