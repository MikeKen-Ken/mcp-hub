import 'skill_md_document.dart';

/// 把 Cursor `SKILL.md` 转成 OpenCode 识别的 frontmatter。
///
/// OpenCode 只认 `name` / `description` / `license` / `compatibility` / `metadata`。
/// Cursor 的 `disable-model-invocation` 映射为
/// `metadata.opencode/autoinvoke`（`true` → `"false"`，禁止隐式调用）。
class OpenCodeSkillMd {
  const OpenCodeSkillMd();

  static const _cursorOnlyKeys = {
    'disable-model-invocation',
  };

  String convert(SkillMdDocument document) {
    if (!_hasOpenCodeFrontmatter(document)) {
      final raw = document.raw;
      return raw.endsWith('\n') ? raw : '$raw\n';
    }

    final buffer = StringBuffer()..writeln('---');
    _writeScalar(buffer, 'name', document.name);
    _writeDescription(buffer, document.description);
    _writeScalar(buffer, 'license', document.frontmatter['license']);
    _writeScalar(
      buffer,
      'compatibility',
      document.frontmatter['compatibility'],
    );
    _writeAutoinvokeMetadata(buffer, document);
    buffer.writeln('---');
    final body = document.body.trim();
    if (body.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(body);
    }
    buffer.writeln();
    return buffer.toString();
  }

  bool _hasOpenCodeFrontmatter(SkillMdDocument document) {
    return document.name != null ||
        document.description != null ||
        document.disableModelInvocation != null ||
        (document.frontmatter['license']?.trim().isNotEmpty ?? false) ||
        (document.frontmatter['compatibility']?.trim().isNotEmpty ?? false);
  }

  void _writeAutoinvokeMetadata(StringBuffer buffer, SkillMdDocument document) {
    final disable = document.disableModelInvocation;
    if (disable == null) return;
    buffer
      ..writeln('metadata:')
      ..writeln('  opencode/autoinvoke: "${!disable}"');
  }

  void _writeDescription(StringBuffer buffer, String? raw) {
    final text = raw?.trim();
    if (text == null || text.isEmpty) return;
    if (text.contains('\n') || text.length > 72) {
      buffer.writeln('description: >-');
      for (final line in _foldedLines(text)) {
        buffer.writeln('  $line');
      }
      return;
    }
    _writeScalar(buffer, 'description', text);
  }

  void _writeScalar(StringBuffer buffer, String key, String? raw) {
    final text = raw?.trim();
    if (text == null || text.isEmpty) return;
    if (_cursorOnlyKeys.contains(key)) return;
    buffer.writeln('$key: ${_quote(text)}');
  }

  List<String> _foldedLines(String text) {
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final lines = <String>[];
    var current = StringBuffer();
    for (final word in words) {
      if (current.isEmpty) {
        current.write(word);
        continue;
      }
      if (current.length + 1 + word.length > 72) {
        lines.add(current.toString());
        current = StringBuffer(word);
      } else {
        current
          ..write(' ')
          ..write(word);
      }
    }
    if (current.isNotEmpty) lines.add(current.toString());
    return lines.isEmpty ? [text] : lines;
  }

  String _quote(String value) {
    final needsQuote =
        value.contains(':') ||
        value.contains('#') ||
        value.contains('"') ||
        value.contains("'") ||
        value.startsWith('{') ||
        value.startsWith('[') ||
        value == 'true' ||
        value == 'false' ||
        value == 'null';
    if (!needsQuote) return value;
    final escaped = value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    return '"$escaped"';
  }
}
