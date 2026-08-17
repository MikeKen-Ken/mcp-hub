/// 处理 Codex `config.toml` 中 `[mcp_servers.<id>]` 及其嵌套表。
///
/// Hub 重写父表时必须清掉同 id 的全部嵌套表（含 `.tools.*`），
/// 否则 Codex 会把无 `command`/`url` 的孤儿表判为 invalid transport。
/// 审批类嵌套表在仍托管该服务器时保留，并把表头 id 改成 Hub 规范名。
abstract final class CodexMcpTomlRewriter {
  static final _tableHeader = RegExp(r'^\[([^\]]+)\]\s*$', multiLine: true);

  /// 去掉 [id]（大小写不敏感）下所有 `mcp_servers` 表。
  /// [keepNested] 为 true 时返回非 `.env` 嵌套表，表头改为 [canonicalId]。
  static ({String text, String nested}) stripServerTables(
    String source,
    String id, {
    required bool keepNested,
    required String canonicalId,
  }) {
    final matches = _tableHeader.allMatches(source).toList();
    if (matches.isEmpty) {
      return (text: source, nested: '');
    }

    final kept = StringBuffer();
    final nested = StringBuffer();
    var wrotePreamble = false;

    for (var i = 0; i < matches.length; i++) {
      final match = matches[i];
      if (!wrotePreamble) {
        kept.write(source.substring(0, match.start));
        wrotePreamble = true;
      }
      final end = i + 1 < matches.length ? matches[i + 1].start : source.length;
      final chunk = source.substring(match.start, end);
      final parsed = _parseMcpServersTable(match.group(1)!);
      if (parsed == null || !_sameServerId(parsed.serverId, id)) {
        kept.write(chunk);
        continue;
      }
      if (parsed.suffix == null || _isEnvSuffix(parsed.suffix!)) {
        continue;
      }
      if (keepNested) {
        nested.write(_rewriteNestedHeader(chunk, canonicalId, parsed.suffix!));
      }
    }

    return (
      text: _collapseBlankLines(kept.toString()),
      nested: nested.toString().trimRight(),
    );
  }

  static ({String serverId, String? suffix})? _parseMcpServersTable(
    String tableName,
  ) {
    final parts = tableName.split('.');
    if (parts.length < 2) return null;
    if (parts[0].toLowerCase() != 'mcp_servers') return null;
    final serverId = parts[1];
    if (serverId.isEmpty) return null;
    final suffix = parts.length == 2 ? null : parts.sublist(2).join('.');
    return (serverId: serverId, suffix: suffix);
  }

  static bool _sameServerId(String left, String right) =>
      left.toLowerCase() == right.toLowerCase();

  static bool _isEnvSuffix(String suffix) =>
      suffix == 'env' || suffix.startsWith('env.');

  static String _rewriteNestedHeader(
    String chunk,
    String canonicalId,
    String suffix,
  ) {
    final newline = chunk.indexOf('\n');
    final header = '[mcp_servers.$canonicalId.$suffix]';
    if (newline < 0) return '$header\n';
    return '$header${chunk.substring(newline)}';
  }

  static String _collapseBlankLines(String source) =>
      source.replaceAll(RegExp(r'\n{3,}'), '\n\n');
}
