import 'dart:io';

import 'package:path/path.dart' as p;

/// 解析 Agent Skill / Rule 的 YAML frontmatter（`---` 包裹）。
///
/// 支持普通 `key: value`，以及 `description: >-` 这类块标量。
class SkillMdDocument {
  const SkillMdDocument({
    required this.frontmatter,
    required this.body,
    required this.raw,
  });

  final Map<String, String> frontmatter;
  final String body;
  final String raw;

  String? get name => _nonEmpty(frontmatter['name']);
  String? get description => _nonEmpty(frontmatter['description']);

  /// Cursor Skill frontmatter：禁止模型隐式调用。
  ///
  /// 对应 Codex `agents/openai.yaml` 的 `allow_implicit_invocation: false`。
  bool? get disableModelInvocation =>
      _parseBool(frontmatter['disable-model-invocation']);

  /// 由 Cursor frontmatter 推导的 Codex 隐式调用策略；无该字段时返回 null。
  bool? get allowImplicitInvocationFromFrontmatter {
    final disable = disableModelInvocation;
    if (disable == null) return null;
    return !disable;
  }

  /// 正文第一个一级标题（不含 `#`）。
  String? get title {
    for (final line in body.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('# ')) {
        final title = trimmed.substring(2).trim();
        if (title.isNotEmpty) return title;
      }
    }
    return null;
  }

  static SkillMdDocument parse(String raw) {
    final normalized = raw.replaceAll('\r\n', '\n');
    if (!normalized.startsWith('---')) {
      return SkillMdDocument(
        frontmatter: const {},
        body: normalized.trim(),
        raw: raw,
      );
    }

    final end = normalized.indexOf('\n---', 3);
    if (end < 0) {
      return SkillMdDocument(
        frontmatter: const {},
        body: normalized.trim(),
        raw: raw,
      );
    }

    final fmBlock = normalized.substring(3, end).trim();
    var body = normalized.substring(end + 4);
    if (body.startsWith('\n')) body = body.substring(1);

    return SkillMdDocument(
      frontmatter: _parseFrontmatter(fmBlock),
      body: body.trim(),
      raw: raw,
    );
  }

  static final _blockScalar = RegExp(r'^([>|])([+-]?)$');

  /// 解析 frontmatter：支持普通 `key: value` 与 `>` / `|` 块标量（含 `>-`）。
  static Map<String, String> _parseFrontmatter(String fmBlock) {
    final lines = fmBlock.split('\n');
    final result = <String, String>{};
    var i = 0;
    while (i < lines.length) {
      final rawLine = lines[i];
      final trimmedRight = rawLine.trimRight();
      final trimmed = trimmedRight.trimLeft();
      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        i++;
        continue;
      }
      if (rawLine.startsWith(' ') || rawLine.startsWith('\t')) {
        i++;
        continue;
      }
      final colon = trimmedRight.indexOf(':');
      if (colon <= 0) {
        i++;
        continue;
      }
      final key = trimmedRight.substring(0, colon).trim();
      if (key.isEmpty) {
        i++;
        continue;
      }
      final rest = trimmedRight.substring(colon + 1).trim();
      final block = _blockScalar.firstMatch(rest);
      if (block != null) {
        i++;
        final parsed = _readBlockScalar(
          lines: lines,
          start: i,
          folded: block.group(1) == '>',
        );
        result[key] = parsed.text;
        i = parsed.nextIndex;
        continue;
      }
      result[key] = _unquote(rest);
      i++;
    }
    return result;
  }

  static ({String text, int nextIndex}) _readBlockScalar({
    required List<String> lines,
    required int start,
    required bool folded,
  }) {
    var i = start;
    final collected = <String>[];
    while (i < lines.length) {
      final line = lines[i];
      if (line.trim().isEmpty) {
        collected.add(line);
        i++;
        continue;
      }
      if (line.startsWith(' ') || line.startsWith('\t')) {
        collected.add(line);
        i++;
        continue;
      }
      break;
    }

    while (collected.isNotEmpty && collected.last.trim().isEmpty) {
      collected.removeLast();
    }

    var indent = 0;
    for (final line in collected) {
      if (line.trim().isEmpty) continue;
      final ws = line.length - line.trimLeft().length;
      if (indent == 0 || ws < indent) indent = ws;
    }

    final contents = [
      for (final line in collected)
        if (line.trim().isEmpty)
          ''
        else if (line.length >= indent)
          line.substring(indent)
        else
          line.trimLeft(),
    ];

    if (contents.isEmpty) {
      return (text: '', nextIndex: i);
    }

    if (!folded) {
      return (text: contents.join('\n').trim(), nextIndex: i);
    }

    final buffer = StringBuffer();
    var started = false;
    var pendingBreak = false;
    for (final part in contents) {
      if (part.isEmpty) {
        pendingBreak = true;
        continue;
      }
      if (!started) {
        buffer.write(part);
        started = true;
      } else if (pendingBreak) {
        buffer
          ..write('\n\n')
          ..write(part);
        pendingBreak = false;
      } else {
        buffer
          ..write(' ')
          ..write(part);
      }
    }
    return (text: buffer.toString().trim(), nextIndex: i);
  }

  static String _unquote(String value) {
    if ((value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'"))) {
      return value.substring(1, value.length - 1);
    }
    return value;
  }

  static Future<SkillMdDocument> parseFile(String path) async {
    final raw = await File(path).readAsString();
    return parse(raw);
  }

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  static bool? _parseBool(String? value) {
    final trimmed = value?.trim().toLowerCase();
    if (trimmed == null || trimmed.isEmpty) return null;
    return switch (trimmed) {
      'true' || 'yes' || '1' => true,
      'false' || 'no' || '0' => false,
      _ => null,
    };
  }
}

/// 从路径推断 Skill 包名（目录名）。
String skillPackageNameFromPath(String skillDir) => p.basename(skillDir);
