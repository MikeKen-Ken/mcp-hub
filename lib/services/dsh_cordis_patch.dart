import '../models/mcp_server_entry.dart';
import '../models/mcp_transport.dart';
import 'mcp_client_config.dart';

/// DeepSeek Harness MCP rows inside `$DSH_HOME/cordis.patch.yml`.
///
/// The file is a Cordis patch list and may already hold unrelated plugins,
/// including `!!js` tags. Hub rewrites only the marked region and leaves
/// every other line untouched.
abstract final class DshCordisPatch {
  static const beginMarker = '# mcp-hub:begin';
  static const endMarker = '# mcp-hub:end';
  static const pluginName = '@deepseek-ai/dsh-mcp-client';
  static const _serverMarkerPrefix = '# mcp-hub-server: ';

  static final _serverNamePattern = RegExp(r'^[A-Za-z0-9_-]{1,32}$');

  static String upsert(
    String? existing, {
    required List<McpServerEntry> servers,
    Set<String> managedIds = const {},
    Set<String> removeIds = const {},
  }) {
    final drop = {...managedIds, ...removeIds};
    final live = [
      for (final server in servers)
        if (server.enabled && !removeIds.contains(server.id)) server,
    ];
    final block = render(live);
    final text = existing ?? '';
    final begin = text.indexOf(beginMarker);
    final end = text.indexOf(endMarker);
    if (begin >= 0 && end > begin) {
      final after = end + endMarker.length;
      return text.replaceRange(begin, after, block.trimRight());
    }
    if (begin >= 0 || end >= 0) {
      throw const FormatException(
        'cordis.patch.yml mcp-hub markers are incomplete; nothing was written',
      );
    }
    if (drop.isEmpty && live.isEmpty && text.trim().isEmpty) {
      return '';
    }
    if (text.trim().isEmpty) return '${block.trimRight()}\n';
    return '${text.trimRight()}\n\n${block.trimRight()}\n';
  }

  static String render(List<McpServerEntry> servers) {
    final usedNames = <String>{};
    final buffer = StringBuffer()..writeln(beginMarker);
    for (final server in servers) {
      final serverName = allocateServerName(server.id, usedNames);
      buffer.writeln('$_serverMarkerPrefix${server.id}');
      buffer.writeln('- insert:');
      buffer.writeln('    - id: ${quote('mcp-hub-$serverName')}');
      buffer.writeln('      name: ${quote(pluginName)}');
      buffer.writeln('      config:');
      buffer.writeln('        serverName: ${quote(serverName)}');
      switch (server.transport) {
        case McpTransport.http:
          buffer.writeln('        transport: ${quote('streamable-http')}');
          buffer.writeln('        url: ${quote(server.url ?? '')}');
        case McpTransport.stdio:
          buffer.writeln('        transport: ${quote('stdio')}');
          buffer.writeln('        command: ${quote(server.command ?? '')}');
          if (server.args.isNotEmpty) {
            buffer.writeln('        args:');
            for (final arg in server.args) {
              buffer.writeln('          - ${quote(arg)}');
            }
          }
          if (server.env.isNotEmpty) {
            buffer.writeln('        env:');
            for (final entry in server.env.entries) {
              buffer.writeln(
                '          ${yamlKey(entry.key)}: ${quote(entry.value)}',
              );
            }
          }
          final cwd = server.cwd?.trim();
          if (cwd != null && cwd.isNotEmpty) {
            buffer.writeln('        cwd: ${quote(cwd)}');
          }
      }
    }
    buffer.write(endMarker);
    return buffer.toString();
  }

  static List<McpServerEntry> parseServers(String text) {
    final block = markedBlock(text);
    if (block == null) return const [];
    final parsed = _parseBlock(block);
    return [
      for (final row in parsed)
        McpServerEntry(
          id: row.id,
          name: row.serverName ?? row.id,
          transport: row.transport == 'streamable-http'
              ? McpTransport.http
              : McpTransport.stdio,
          command: row.command,
          args: row.args,
          env: row.env,
          cwd: row.cwd,
          url: row.url,
          enabled: true,
        ),
    ];
  }

  static McpServerConfigDiagnosis diagnose(
    String? existing, {
    required McpServerEntry server,
  }) {
    final text = existing ?? '';
    if (text.contains(beginMarker) != text.contains(endMarker)) {
      return McpServerConfigDiagnosis(serverId: server.id, missing: true);
    }
    final rows = _parseBlock(markedBlock(text) ?? '');
    final row = rows.where((item) => item.id == server.id).firstOrNull;
    if (!server.enabled) {
      if (row == null) {
        return McpServerConfigDiagnosis(serverId: server.id, missing: false);
      }
      return McpServerConfigDiagnosis(
        serverId: server.id,
        missing: false,
        diffs: [
          McpClientFieldDiff(
            serverId: server.id,
            field: 'enabled',
            expected: 'false',
            actual: 'true',
          ),
        ],
      );
    }
    if (row == null) {
      return McpServerConfigDiagnosis(serverId: server.id, missing: true);
    }
    return McpServerConfigDiagnosis(
      serverId: server.id,
      missing: false,
      diffs: _diffs(server, row),
    );
  }

  static String? markedBlock(String text) {
    final begin = text.indexOf(beginMarker);
    final end = text.indexOf(endMarker);
    if (begin < 0 || end < begin) return null;
    return text.substring(begin, end + endMarker.length);
  }

  static String allocateServerName(String id, Set<String> used) {
    final cleaned = id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    var base = cleaned.length > 32 ? cleaned.substring(0, 32) : cleaned;
    if (base.isEmpty || !_serverNamePattern.hasMatch(base)) base = 'server';
    var name = base;
    var n = 2;
    while (!used.add(name)) {
      final suffix = '_$n';
      final room = 32 - suffix.length;
      final stem = base.length > room ? base.substring(0, room) : base;
      name = '$stem$suffix';
      n++;
      if (n > 1000) break;
    }
    return name;
  }

  static String quote(String value) {
    final escaped = value
        .replaceAll(r'\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll('\n', r'\n');
    return '"$escaped"';
  }

  static String yamlKey(String key) {
    if (RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(key)) return key;
    return quote(key);
  }

  static List<_DshMcpRow> _parseBlock(String block) {
    final rows = <_DshMcpRow>[];
    _DshMcpRow? current;
    var mode = '';
    for (final line in block.split('\n')) {
      if (line.startsWith(_serverMarkerPrefix)) {
        current = _DshMcpRow(line.substring(_serverMarkerPrefix.length).trim());
        rows.add(current);
        mode = '';
        continue;
      }
      if (current == null) continue;
      final trimmed = line.trim();
      if (mode == 'args' && trimmed.startsWith('- ')) {
        current.args.add(unquote(trimmed.substring(2).trim()));
        continue;
      }
      if (mode == 'env' &&
          line.startsWith('          ') &&
          trimmed.contains(':')) {
        final colon = trimmed.indexOf(':');
        current.env[unquote(trimmed.substring(0, colon).trim())] = unquote(
          trimmed.substring(colon + 1).trim(),
        );
        continue;
      }
      mode = '';
      if (trimmed.startsWith('serverName:')) {
        current.serverName = unquote(trimmed.substring('serverName:'.length));
      } else if (trimmed.startsWith('transport:')) {
        current.transport = unquote(trimmed.substring('transport:'.length));
      } else if (trimmed.startsWith('command:')) {
        current.command = unquote(trimmed.substring('command:'.length));
      } else if (trimmed.startsWith('url:')) {
        current.url = unquote(trimmed.substring('url:'.length));
      } else if (trimmed.startsWith('cwd:')) {
        current.cwd = unquote(trimmed.substring('cwd:'.length));
      } else if (trimmed == 'args:') {
        mode = 'args';
      } else if (trimmed == 'env:') {
        mode = 'env';
      }
    }
    return rows;
  }

  static String unquote(String raw) {
    final text = raw.trim();
    if (text.length >= 2 && text.startsWith('"') && text.endsWith('"')) {
      return _unescape(text.substring(1, text.length - 1));
    }
    if (text.length >= 2 && text.startsWith("'") && text.endsWith("'")) {
      return text.substring(1, text.length - 1).replaceAll("''", "'");
    }
    return text;
  }

  static String _unescape(String inner) {
    final out = StringBuffer();
    for (var i = 0; i < inner.length; i++) {
      if (inner[i] == r'\' && i + 1 < inner.length) {
        final next = inner[i + 1];
        if (next == 'n') {
          out.write('\n');
          i++;
          continue;
        }
        if (next == '"' || next == r'\') {
          out.write(next);
          i++;
          continue;
        }
      }
      out.write(inner[i]);
    }
    return out.toString();
  }

  static List<McpClientFieldDiff> _diffs(
    McpServerEntry server,
    _DshMcpRow row,
  ) {
    final diffs = <McpClientFieldDiff>[];
    void add(String field, String? expected, String? actual) {
      if (expected == actual) return;
      diffs.add(
        McpClientFieldDiff(
          serverId: server.id,
          field: field,
          expected: expected,
          actual: actual,
        ),
      );
    }

    switch (server.transport) {
      case McpTransport.http:
        add('transport', 'streamable-http', row.transport);
        add('url', server.url ?? '', row.url);
      case McpTransport.stdio:
        add('transport', 'stdio', row.transport);
        add('command', server.command ?? '', row.command);
        if (!_listEquals(row.args, server.args)) {
          add('args', server.args.join('\n'), row.args.join('\n'));
        }
        if (!_mapEquals(row.env, server.env)) {
          add('env', _formatMap(server.env), _formatMap(row.env));
        }
        final expectedCwd = server.cwd?.trim();
        final cwd = (expectedCwd == null || expectedCwd.isEmpty)
            ? null
            : expectedCwd;
        add('cwd', cwd, row.cwd);
    }
    return diffs;
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _mapEquals(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final entry in b.entries) {
      if (a[entry.key] != entry.value) return false;
    }
    return true;
  }

  static String _formatMap(Map<String, String> map) {
    final keys = map.keys.toList()..sort();
    return [for (final key in keys) '$key=${map[key]}'].join(',');
  }
}

class _DshMcpRow {
  _DshMcpRow(this.id);

  final String id;
  String? serverName;
  String? transport;
  String? command;
  final List<String> args = [];
  final Map<String, String> env = {};
  String? cwd;
  String? url;
}
