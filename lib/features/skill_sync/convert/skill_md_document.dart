import 'dart:io';

import 'package:path/path.dart' as p;

/// 解析 Agent Skill / Rule 的 YAML frontmatter（`---` 包裹）。
///
/// 支持普通 `key: value`、`>` / `|` 块标量，并保留原始顶层键块 [rawEntries]。
class SkillMdDocument {
  const SkillMdDocument({
    required this.frontmatter,
    required this.body,
    required this.raw,
    this.rawEntries = const {},
  });

  final Map<String, String> frontmatter;
  final String body;
  final String raw;
  final Map<String, String> rawEntries;

  String? get name => _nonEmpty(frontmatter['name']);
  String? get description => _nonEmpty(frontmatter['description']);

  bool? get alwaysApply => _parseBool(frontmatter['alwaysApply']);
  String? get globs => _nonEmpty(frontmatter['globs']);

  /// Cursor Skill frontmatter：禁止模型隐式调用。
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

  static final _openDelimiter = RegExp(r'^---[ \t]*\n');
  static final _emptyCloseDelimiter = RegExp(r'^---[ \t]*(?:\n|$)');
  static final _closeDelimiter = RegExp(r'\n---[ \t]*(?:\n|$)');

  static SkillMdDocument parse(String raw) {
    var normalized = raw.replaceAll('\r\n', '\n');
    if (normalized.startsWith('\uFEFF')) {
      normalized = normalized.substring(1);
    }
    final openMatch = _openDelimiter.firstMatch(normalized);
    if (openMatch == null) {
      return SkillMdDocument(
        frontmatter: const {},
        body: normalized.trim(),
        raw: raw,
      );
    }

    final afterOpen = normalized.substring(openMatch.end);
    final String fmBlock;
    final String body;
    final emptyClose = _emptyCloseDelimiter.firstMatch(afterOpen);
    if (emptyClose != null) {
      fmBlock = '';
      body = afterOpen.substring(emptyClose.end);
    } else {
      final closeMatch = _closeDelimiter.firstMatch(afterOpen);
      if (closeMatch == null) {
        return SkillMdDocument(
          frontmatter: const {},
          body: normalized.trim(),
          raw: raw,
        );
      }
      fmBlock = afterOpen.substring(0, closeMatch.start).trim();
      body = afterOpen.substring(closeMatch.end);
    }

    final parsed = _parseFrontmatter(fmBlock);
    return SkillMdDocument(
      frontmatter: parsed.values,
      body: body.trim(),
      raw: raw,
      rawEntries: parsed.rawEntries,
    );
  }

  static final _blockScalar = RegExp(r'^([>|])([+-]?)$');
  static final _doubleEscape = RegExp(r'\\(["\\nrt])');

  /// 解析 frontmatter：支持普通 `key: value`、块标量，以及嵌套缩进块保留。
  static ({Map<String, String> values, Map<String, String> rawEntries})
  _parseFrontmatter(String fmBlock) {
    if (fmBlock.isEmpty) {
      return (values: const {}, rawEntries: const {});
    }
    final lines = fmBlock.split('\n');
    final values = <String, String>{};
    final rawEntries = <String, String>{};
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
      final startIdx = i;
      final rest = trimmedRight.substring(colon + 1).trim();
      final block = _blockScalar.firstMatch(rest);
      if (block != null) {
        i++;
        final parsed = _readBlockScalar(
          lines: lines,
          start: i,
          folded: block.group(1) == '>',
        );
        values[key] = parsed.text;
        rawEntries[key] = _joinTrimmedLines(lines, startIdx, parsed.nextIndex);
        i = parsed.nextIndex;
        continue;
      }
      values[key] = _unquote(rest);
      i++;
      var endIdx = i;
      while (i < lines.length) {
        final next = lines[i];
        if (next.trim().isEmpty) {
          i++;
          continue;
        }
        if (next.startsWith(' ') || next.startsWith('\t')) {
          i++;
          endIdx = i;
          continue;
        }
        break;
      }
      rawEntries[key] = _joinTrimmedLines(lines, startIdx, endIdx);
      i = endIdx;
    }
    return (values: values, rawEntries: rawEntries);
  }

  static String _joinTrimmedLines(List<String> lines, int start, int end) {
    var last = end;
    while (last > start && lines[last - 1].trim().isEmpty) {
      last--;
    }
    return lines.sublist(start, last).map((l) => l.trimRight()).join('\n');
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
    if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
      final inner = value.substring(1, value.length - 1);
      return inner.replaceAllMapped(_doubleEscape, (m) {
        return switch (m[1]) {
          '"' => '"',
          r'\' => r'\',
          'n' => '\n',
          'r' => '\r',
          't' => '\t',
          _ => m[0]!,
        };
      });
    }
    if (value.length >= 2 && value.startsWith("'") && value.endsWith("'")) {
      return value.substring(1, value.length - 1).replaceAll("''", "'");
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
      'true' || 'yes' || 'on' || '1' => true,
      'false' || 'no' || 'off' || '0' => false,
      _ => null,
    };
  }
}

/// 从路径推断 Skill 包名（目录名）。
String skillPackageNameFromPath(String skillDir) => p.basename(skillDir);
