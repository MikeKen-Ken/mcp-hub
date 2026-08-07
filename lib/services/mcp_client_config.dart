import 'dart:convert';

import '../models/mcp_server_entry.dart';
import '../models/mcp_transport.dart';

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

  static bool isCursorServerConfigured(
    String? existing, {
    required McpServerEntry server,
  }) {
    if (existing == null || existing.trim().isEmpty) return false;
    try {
      final decoded = jsonDecode(existing);
      if (decoded is! Map) return false;
      final servers = decoded['mcpServers'];
      if (servers is! Map) return false;
      final entry = servers[server.id];
      if (entry is! Map) return false;
      return switch (server.transport) {
        McpTransport.http =>
          entry['url'] == server.url && (entry['type'] == null || entry['type'] == 'http'),
        McpTransport.stdio => entry['command'] == server.command,
      };
    } catch (_) {
      return false;
    }
  }

  static bool isCodexServerConfigured(
    String? existing, {
    required McpServerEntry server,
  }) {
    if (existing == null || existing.trim().isEmpty) return false;
    final header = '[mcp_servers.${server.id}]';
    final start = existing.indexOf(header);
    if (start < 0) return false;
    final rest = existing.substring(start + header.length);
    final nextTable = RegExp(r'^\[', multiLine: true).firstMatch(rest);
    final body = nextTable == null ? rest : rest.substring(0, nextTable.start);
    return switch (server.transport) {
      McpTransport.http => RegExp(
            r'''url\s*=\s*["']([^"']+)["']''',
          ).firstMatch(body)?.group(1) ==
          server.url,
      McpTransport.stdio => RegExp(
            r'''command\s*=\s*["']([^"']+)["']''',
          ).firstMatch(body)?.group(1) ==
          server.command,
    };
  }

  static String _ensureCodexRmcpClient(String source) {
    if (RegExp(
      r'^\s*rmcp_client\s*=\s*true\s*$',
      multiLine: true,
    ).hasMatch(source)) {
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
    final header = '[$tableName]';
    final start = source.indexOf(header);
    if (start < 0) {
      // Also strip nested env table if present alone after parent removal.
      final envHeader = '[$tableName.env]';
      final envStart = source.indexOf(envHeader);
      if (envStart < 0) return source;
      return _removeTomlTable(source, '$tableName.env');
    }
    final afterHeader = start + header.length;
    final rest = source.substring(afterHeader);
    final next = RegExp(r'^\[', multiLine: true).firstMatch(rest);
    final end = next == null ? source.length : afterHeader + next.start;
    final before = source.substring(0, start);
    final after = source.substring(end);
    var result = '$before$after'.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    // Remove orphaned env table for this server.
    result = _removeTomlTable(result, '$tableName.env');
    return result;
  }
}
