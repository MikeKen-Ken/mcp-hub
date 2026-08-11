import 'dart:convert';

import '../models/mcp_server_entry.dart';
import '../models/mcp_transport.dart';

/// 单个 MCP 在客户端配置中的字段差异。
class McpClientFieldDiff {
  const McpClientFieldDiff({
    required this.serverId,
    required this.field,
    this.expected,
    this.actual,
  });

  final String serverId;
  final String field;
  final String? expected;
  final String? actual;

  /// 例如 `filesystem.command`
  String get label => '$serverId.$field';
}

/// 单个服务器相对客户端配置的诊断结果。
class McpServerConfigDiagnosis {
  const McpServerConfigDiagnosis({
    required this.serverId,
    required this.missing,
    this.diffs = const [],
  });

  final String serverId;
  final bool missing;
  final List<McpClientFieldDiff> diffs;

  bool get isAligned => !missing && diffs.isEmpty;
}

/// Pure upsert helpers for Cursor `mcp.json` and Codex `config.toml`.
///
/// Ported from the kanban project and generalized for multiple servers
/// (stdio + http), without overwriting unrelated MCP entries.
abstract final class McpClientConfig {
  /// Merge [servers] into Cursor JSON. Only [McpServerEntry.enabled] entries
  /// are written; disabled Hub-managed keys listed in [managedIds] are removed.
  static String upsertCursorJson(
    String? existing, {
    required List<McpServerEntry> servers,
    Set<String> managedIds = const {},
  }) {
    Map<String, dynamic> root;
    if (existing == null || existing.trim().isEmpty) {
      root = {};
    } else {
      final decoded = jsonDecode(existing);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Cursor mcp.json 根节点必须是对象');
      }
      root = Map<String, dynamic>.from(decoded);
    }

    final existingServers = root['mcpServers'];
    final map = existingServers is Map
        ? Map<String, dynamic>.from(
            existingServers.map(
              (key, value) => MapEntry(key.toString(), value),
            ),
          )
        : <String, dynamic>{};

    for (final id in managedIds) {
      map.remove(id);
    }

    for (final server in servers.where((s) => s.enabled)) {
      map[server.id] = _cursorEntry(server);
    }

    root['mcpServers'] = map;
    return const JsonEncoder.withIndent('  ').convert(root);
  }

  static Map<String, dynamic> _cursorEntry(McpServerEntry server) {
    return switch (server.transport) {
      McpTransport.http => {
          'url': server.url ?? '',
          'type': 'http',
        },
      McpTransport.stdio => {
          'command': server.command ?? '',
          if (server.args.isNotEmpty) 'args': server.args,
          if (server.env.isNotEmpty) 'env': server.env,
          if (server.cwd != null && server.cwd!.isNotEmpty) 'cwd': server.cwd,
        },
    };
  }

  /// Merge enabled servers into Codex TOML; remove disabled managed tables.
  static String upsertCodexToml(
    String? existing, {
    required List<McpServerEntry> servers,
    Set<String> managedIds = const {},
  }) {
    var text = existing ?? '';
    for (final id in managedIds) {
      text = _removeTomlTable(text, 'mcp_servers.$id');
    }
    text = _ensureCodexRmcpClient(text);

    final blocks = <String>[];
    for (final server in servers.where((s) => s.enabled)) {
      blocks.add(_codexBlock(server));
    }
    if (blocks.isEmpty) {
      final trimmed = text.trimRight();
      return trimmed.isEmpty ? '' : '$trimmed\n';
    }

    final trimmed = text.trimRight();
    final appended = blocks.join('\n\n');
    if (trimmed.isEmpty) return '$appended\n';
    return '$trimmed\n\n$appended\n';
  }

  static String _codexBlock(McpServerEntry server) {
    final buffer = StringBuffer('[mcp_servers.${server.id}]\n');
    switch (server.transport) {
      case McpTransport.http:
        buffer.writeln('url = "${server.url ?? ''}"');
      case McpTransport.stdio:
        buffer.writeln('command = "${_escapeToml(server.command ?? '')}"');
        if (server.args.isNotEmpty) {
          final args = server.args.map((a) => '"${_escapeToml(a)}"').join(', ');
          buffer.writeln('args = [$args]');
        }
        if (server.cwd != null && server.cwd!.isNotEmpty) {
          buffer.writeln('cwd = "${_escapeToml(server.cwd!)}"');
        }
        if (server.env.isNotEmpty) {
          buffer.writeln();
          buffer.writeln('[mcp_servers.${server.id}.env]');
          for (final entry in server.env.entries) {
            buffer.writeln(
              '${entry.key} = "${_escapeToml(entry.value)}"',
            );
          }
        }
    }
    return buffer.toString().trimRight();
  }

  static String _escapeToml(String value) =>
      value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

  static String _unescapeToml(String value) =>
      value.replaceAll(r'\"', '"').replaceAll(r'\\', r'\');

  /// 诊断 Cursor 配置中单个服务器是否与 Hub 期望一致。
  static McpServerConfigDiagnosis diagnoseCursorServer(
    String? existing, {
    required McpServerEntry server,
  }) {
    if (existing == null || existing.trim().isEmpty) {
      return McpServerConfigDiagnosis(serverId: server.id, missing: true);
    }
    try {
      final decoded = jsonDecode(existing);
      if (decoded is! Map) {
        return McpServerConfigDiagnosis(serverId: server.id, missing: true);
      }
      final servers = decoded['mcpServers'];
      if (servers is! Map) {
        return McpServerConfigDiagnosis(serverId: server.id, missing: true);
      }
      final entry = servers[server.id];
      if (entry is! Map) {
        return McpServerConfigDiagnosis(serverId: server.id, missing: true);
      }
      final map = entry.map((k, v) => MapEntry(k.toString(), v));
      return McpServerConfigDiagnosis(
        serverId: server.id,
        missing: false,
        diffs: _cursorFieldDiffs(server, map),
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      return McpServerConfigDiagnosis(serverId: server.id, missing: true);
    }
  }

  static List<McpClientFieldDiff> _cursorFieldDiffs(
    McpServerEntry server,
    Map<String, dynamic> entry,
  ) {
    final diffs = <McpClientFieldDiff>[];
    switch (server.transport) {
      case McpTransport.http:
        final expectedUrl = server.url ?? '';
        final actualUrl = entry['url']?.toString();
        if (actualUrl != expectedUrl) {
          diffs.add(
            McpClientFieldDiff(
              serverId: server.id,
              field: 'url',
              expected: expectedUrl,
              actual: actualUrl,
            ),
          );
        }
        final type = entry['type'];
        if (type != null && type.toString() != 'http') {
          diffs.add(
            McpClientFieldDiff(
              serverId: server.id,
              field: 'type',
              expected: 'http',
              actual: type.toString(),
            ),
          );
        }
      case McpTransport.stdio:
        final expectedCommand = server.command ?? '';
        final actualCommand = entry['command']?.toString();
        if (actualCommand != expectedCommand) {
          diffs.add(
            McpClientFieldDiff(
              serverId: server.id,
              field: 'command',
              expected: expectedCommand,
              actual: actualCommand,
            ),
          );
        }
        final actualArgs = _asStringList(entry['args']);
        if (!_listEquals(actualArgs, server.args)) {
          diffs.add(
            McpClientFieldDiff(
              serverId: server.id,
              field: 'args',
              expected: _formatList(server.args),
              actual: actualArgs == null ? null : _formatList(actualArgs),
            ),
          );
        }
        final actualEnv = _asStringMap(entry['env']);
        if (!_mapEquals(actualEnv, server.env)) {
          diffs.add(
            McpClientFieldDiff(
              serverId: server.id,
              field: 'env',
              expected: _formatMap(server.env),
              actual: actualEnv == null ? null : _formatMap(actualEnv),
            ),
          );
        }
        final expectedCwd =
            (server.cwd != null && server.cwd!.isNotEmpty) ? server.cwd : null;
        final actualCwdRaw = entry['cwd']?.toString();
        final actualCwd =
            (actualCwdRaw != null && actualCwdRaw.isNotEmpty) ? actualCwdRaw : null;
        if (actualCwd != expectedCwd) {
          diffs.add(
            McpClientFieldDiff(
              serverId: server.id,
              field: 'cwd',
              expected: expectedCwd,
              actual: actualCwd,
            ),
          );
        }
    }
    return diffs;
  }

  /// 诊断 Codex 配置中单个服务器是否与 Hub 期望一致。
  static McpServerConfigDiagnosis diagnoseCodexServer(
    String? existing, {
    required McpServerEntry server,
  }) {
    if (existing == null || existing.trim().isEmpty) {
      return McpServerConfigDiagnosis(serverId: server.id, missing: true);
    }
    final table = _extractCodexServerTable(existing, server.id);
    if (table == null) {
      return McpServerConfigDiagnosis(serverId: server.id, missing: true);
    }
    return McpServerConfigDiagnosis(
      serverId: server.id,
      missing: false,
      diffs: _codexFieldDiffs(server, table),
    );
  }

  static List<McpClientFieldDiff> _codexFieldDiffs(
    McpServerEntry server,
    _CodexServerTable table,
  ) {
    final diffs = <McpClientFieldDiff>[];
    switch (server.transport) {
      case McpTransport.http:
        final expectedUrl = server.url ?? '';
        if (table.url != expectedUrl) {
          diffs.add(
            McpClientFieldDiff(
              serverId: server.id,
              field: 'url',
              expected: expectedUrl,
              actual: table.url,
            ),
          );
        }
      case McpTransport.stdio:
        final expectedCommand = server.command ?? '';
        if (table.command != expectedCommand) {
          diffs.add(
            McpClientFieldDiff(
              serverId: server.id,
              field: 'command',
              expected: expectedCommand,
              actual: table.command,
            ),
          );
        }
        if (!_listEquals(table.args, server.args)) {
          diffs.add(
            McpClientFieldDiff(
              serverId: server.id,
              field: 'args',
              expected: _formatList(server.args),
              actual: table.args == null ? null : _formatList(table.args!),
            ),
          );
        }
        final expectedCwd =
            (server.cwd != null && server.cwd!.isNotEmpty) ? server.cwd : null;
        final actualCwd =
            (table.cwd != null && table.cwd!.isNotEmpty) ? table.cwd : null;
        if (actualCwd != expectedCwd) {
          diffs.add(
            McpClientFieldDiff(
              serverId: server.id,
              field: 'cwd',
              expected: expectedCwd,
              actual: actualCwd,
            ),
          );
        }
        if (!_mapEquals(table.env, server.env)) {
          diffs.add(
            McpClientFieldDiff(
              serverId: server.id,
              field: 'env',
              expected: _formatMap(server.env),
              actual: table.env == null ? null : _formatMap(table.env!),
            ),
          );
        }
    }
    return diffs;
  }

  static bool isCursorServerConfigured(
    String? existing, {
    required McpServerEntry server,
  }) {
    try {
      return diagnoseCursorServer(existing, server: server).isAligned;
    } catch (_) {
      return false;
    }
  }

  static bool isCodexServerConfigured(
    String? existing, {
    required McpServerEntry server,
  }) {
    return diagnoseCodexServer(existing, server: server).isAligned;
  }

  /// Codex 是否已开启 `rmcp_client = true`（与写入逻辑一致）。
  static bool hasCodexRmcpClient(String? existing) {
    if (existing == null || existing.trim().isEmpty) return false;
    return RegExp(
      r'^\s*rmcp_client\s*=\s*true\s*$',
      multiLine: true,
    ).hasMatch(existing);
  }

  /// 合并 [servers] 到 OpenCode `opencode.json` 的 `mcp.servers`。
  static String upsertOpenCodeJson(
    String? existing, {
    required List<McpServerEntry> servers,
    Set<String> managedIds = const {},
  }) {
    Map<String, dynamic> root;
    if (existing == null || existing.trim().isEmpty) {
      root = {};
    } else {
      final decoded = jsonDecode(existing);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('OpenCode opencode.json 根节点必须是对象');
      }
      root = Map<String, dynamic>.from(decoded);
    }

    final mcp = root['mcp'];
    final mcpMap = mcp is Map
        ? Map<String, dynamic>.from(mcp.map((k, v) => MapEntry(k.toString(), v)))
        : <String, dynamic>{};

    final existingServers = mcpMap['servers'];
    final map = existingServers is Map
        ? Map<String, dynamic>.from(
            existingServers.map((k, v) => MapEntry(k.toString(), v)),
          )
        : <String, dynamic>{};

    for (final id in managedIds) {
      map.remove(id);
    }

    for (final server in servers.where((s) => s.enabled)) {
      map[server.id] = _openCodeEntry(server);
    }

    mcpMap['servers'] = map;
    root['mcp'] = mcpMap;
    return const JsonEncoder.withIndent('  ').convert(root);
  }

  static Map<String, dynamic> _openCodeEntry(McpServerEntry server) {
    return switch (server.transport) {
      McpTransport.http => {
          'type': 'remote',
          'url': server.url ?? '',
        },
      McpTransport.stdio => {
          'type': 'local',
          'command': [
            if (server.command != null && server.command!.isNotEmpty)
              server.command!,
            ...server.args,
          ],
          if (server.env.isNotEmpty) 'environment': server.env,
          if (server.cwd != null && server.cwd!.isNotEmpty) 'cwd': server.cwd,
        },
    };
  }

  /// 诊断 OpenCode 配置中单个服务器是否与 Hub 期望一致。
  static McpServerConfigDiagnosis diagnoseOpenCodeServer(
    String? existing, {
    required McpServerEntry server,
  }) {
    if (existing == null || existing.trim().isEmpty) {
      return McpServerConfigDiagnosis(serverId: server.id, missing: true);
    }
    try {
      final decoded = jsonDecode(existing);
      if (decoded is! Map) {
        return McpServerConfigDiagnosis(serverId: server.id, missing: true);
      }
      final mcp = decoded['mcp'];
      if (mcp is! Map) {
        return McpServerConfigDiagnosis(serverId: server.id, missing: true);
      }
      final servers = mcp['servers'];
      if (servers is! Map) {
        return McpServerConfigDiagnosis(serverId: server.id, missing: true);
      }
      final entry = servers[server.id];
      if (entry is! Map) {
        return McpServerConfigDiagnosis(serverId: server.id, missing: true);
      }
      final map = entry.map((k, v) => MapEntry(k.toString(), v));
      return McpServerConfigDiagnosis(
        serverId: server.id,
        missing: false,
        diffs: _openCodeFieldDiffs(server, map),
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      return McpServerConfigDiagnosis(serverId: server.id, missing: true);
    }
  }

  static List<McpClientFieldDiff> _openCodeFieldDiffs(
    McpServerEntry server,
    Map<String, dynamic> entry,
  ) {
    final diffs = <McpClientFieldDiff>[];
    final type = entry['type']?.toString();
    switch (server.transport) {
      case McpTransport.http:
        if (type != 'remote') {
          diffs.add(
            McpClientFieldDiff(
              serverId: server.id,
              field: 'type',
              expected: 'remote',
              actual: type,
            ),
          );
        }
        final expectedUrl = server.url ?? '';
        final actualUrl = entry['url']?.toString();
        if (actualUrl != expectedUrl) {
          diffs.add(
            McpClientFieldDiff(
              serverId: server.id,
              field: 'url',
              expected: expectedUrl,
              actual: actualUrl,
            ),
          );
        }
      case McpTransport.stdio:
        if (type != 'local') {
          diffs.add(
            McpClientFieldDiff(
              serverId: server.id,
              field: 'type',
              expected: 'local',
              actual: type,
            ),
          );
        }
        final expectedCommand = <String>[
          if (server.command != null && server.command!.isNotEmpty)
            server.command!,
          ...server.args,
        ];
        final actualCommand = _asStringList(entry['command']);
        if (!_listEquals(actualCommand, expectedCommand)) {
          diffs.add(
            McpClientFieldDiff(
              serverId: server.id,
              field: 'command',
              expected: _formatList(expectedCommand),
              actual: actualCommand == null ? null : _formatList(actualCommand),
            ),
          );
        }
        final actualEnv = _asStringMap(entry['environment']);
        if (!_mapEquals(actualEnv, server.env)) {
          diffs.add(
            McpClientFieldDiff(
              serverId: server.id,
              field: 'environment',
              expected: _formatMap(server.env),
              actual: actualEnv == null ? null : _formatMap(actualEnv),
            ),
          );
        }
        final expectedCwd =
            (server.cwd != null && server.cwd!.isNotEmpty) ? server.cwd : null;
        final actualCwdRaw = entry['cwd']?.toString();
        final actualCwd =
            (actualCwdRaw != null && actualCwdRaw.isNotEmpty) ? actualCwdRaw : null;
        if (actualCwd != expectedCwd) {
          diffs.add(
            McpClientFieldDiff(
              serverId: server.id,
              field: 'cwd',
              expected: expectedCwd,
              actual: actualCwd,
            ),
          );
        }
    }
    return diffs;
  }

  static bool isOpenCodeServerConfigured(
    String? existing, {
    required McpServerEntry server,
  }) {
    try {
      return diagnoseOpenCodeServer(existing, server: server).isAligned;
    } catch (_) {
      return false;
    }
  }

  static _CodexServerTable? _extractCodexServerTable(String source, String id) {
    // 必须整行精确匹配，避免命中 `[mcp_servers.id.env]`
    final exact = RegExp(
      '^\\[mcp_servers\\.${RegExp.escape(id)}\\]\\s*\$',
      multiLine: true,
    ).firstMatch(source);
    if (exact == null) return null;
    return _parseCodexServerTable(source, id, exact.end);
  }

  static _CodexServerTable _parseCodexServerTable(
    String source,
    String id,
    int bodyStart,
  ) {
    final rest = source.substring(bodyStart);
    final nextTable = RegExp(r'^\[', multiLine: true).firstMatch(rest);
    final body = nextTable == null ? rest : rest.substring(0, nextTable.start);

    String? readString(String key) {
      final match = RegExp(
        '$key\\s*=\\s*"((?:\\\\.|[^"\\\\])*)"',
      ).firstMatch(body);
      if (match != null) return _unescapeToml(match.group(1)!);
      final single = RegExp(
        "$key\\s*=\\s*'([^']*)'",
      ).firstMatch(body);
      return single?.group(1);
    }

    List<String>? args;
    final argsMatch = RegExp(r'args\s*=\s*\[([\s\S]*?)\]').firstMatch(body);
    if (argsMatch != null) {
      args = RegExp(r'"((?:\\.|[^"\\])*)"')
          .allMatches(argsMatch.group(1)!)
          .map((m) => _unescapeToml(m.group(1)!))
          .toList();
    }

    Map<String, String>? env;
    final envHeader = '[mcp_servers.$id.env]';
    final envStart = source.indexOf(envHeader);
    if (envStart >= 0) {
      final envRest = source.substring(envStart + envHeader.length);
      final envNext = RegExp(r'^\[', multiLine: true).firstMatch(envRest);
      final envBody =
          envNext == null ? envRest : envRest.substring(0, envNext.start);
      env = {};
      for (final match in RegExp(
        r'''^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"((?:\\.|[^"\\])*)"''',
        multiLine: true,
      ).allMatches(envBody)) {
        env[match.group(1)!] = _unescapeToml(match.group(2)!);
      }
    }

    return _CodexServerTable(
      command: readString('command'),
      url: readString('url'),
      cwd: readString('cwd'),
      args: args,
      env: env,
    );
  }

  static List<String>? _asStringList(Object? value) {
    if (value == null) return null;
    if (value is! List) return null;
    return value.map((e) => e.toString()).toList();
  }

  static Map<String, String>? _asStringMap(Object? value) {
    if (value == null) return null;
    if (value is! Map) return null;
    return value.map((k, v) => MapEntry(k.toString(), v.toString()));
  }

  static bool _listEquals(List<String>? actual, List<String> expected) {
    if (expected.isEmpty) {
      return actual == null || actual.isEmpty;
    }
    if (actual == null || actual.length != expected.length) return false;
    for (var i = 0; i < expected.length; i++) {
      if (actual[i] != expected[i]) return false;
    }
    return true;
  }

  static bool _mapEquals(Map<String, String>? actual, Map<String, String> expected) {
    if (expected.isEmpty) {
      return actual == null || actual.isEmpty;
    }
    if (actual == null || actual.length != expected.length) return false;
    for (final entry in expected.entries) {
      if (actual[entry.key] != entry.value) return false;
    }
    return true;
  }

  static String _formatList(List<String> values) =>
      '[${values.map((v) => jsonEncode(v)).join(', ')}]';

  static String _formatMap(Map<String, String> values) {
    final keys = values.keys.toList()..sort();
    return '{${keys.map((k) => '$k=${jsonEncode(values[k])}').join(', ')}}';
  }

  static String _ensureCodexRmcpClient(String source) {
    if (hasCodexRmcpClient(source)) {
      return source;
    }

    final featuresHeader = RegExp(r'^\[features\]\s*$', multiLine: true);
    final match = featuresHeader.firstMatch(source);
    if (match == null) {
      final trimmed = source.trimRight();
      const block = '[features]\nrmcp_client = true\n';
      if (trimmed.isEmpty) return block;
      return '$trimmed\n\n$block';
    }

    final insertAt = match.end;
    return '${source.substring(0, insertAt)}\n'
        'rmcp_client = true'
        '${source.substring(insertAt)}';
  }

  static String _removeTomlTable(String source, String tableName) {
    final exact = RegExp(
      '^\\[${RegExp.escape(tableName)}\\]\\s*\$',
      multiLine: true,
    ).firstMatch(source);
    if (exact == null) {
      // Also strip nested env table if present alone after parent removal.
      final envExact = RegExp(
        '^\\[${RegExp.escape('$tableName.env')}\\]\\s*\$',
        multiLine: true,
      ).firstMatch(source);
      if (envExact == null) return source;
      return _removeTomlTable(source, '$tableName.env');
    }
    final afterHeader = exact.end;
    final rest = source.substring(afterHeader);
    final next = RegExp(r'^\[', multiLine: true).firstMatch(rest);
    final end = next == null ? source.length : afterHeader + next.start;
    final before = source.substring(0, exact.start);
    final after = source.substring(end);
    var result = '$before$after'.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    // Remove orphaned env table for this server.
    result = _removeTomlTable(result, '$tableName.env');
    return result;
  }
}

class _CodexServerTable {
  const _CodexServerTable({
    this.command,
    this.url,
    this.cwd,
    this.args,
    this.env,
  });

  final String? command;
  final String? url;
  final String? cwd;
  final List<String>? args;
  final Map<String, String>? env;
}
