import 'dart:convert';

import '../models/mcp_server_entry.dart';
import '../models/mcp_transport.dart';
import 'hub_mcp_constants.dart';
import 'mcp_client_config.dart';

/// 从客户端 MCP 配置文件反向解析为 Hub 目录条目。
abstract final class McpClientConfigReader {
  static List<McpServerEntry> parseCursorServers(String? text) {
    if (text == null || text.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) return const [];
      final servers = decoded['mcpServers'];
      if (servers is! Map) return const [];
      final result = <McpServerEntry>[];
      for (final entry in servers.entries) {
        final id = entry.key.toString().trim();
        if (id.isEmpty || id == HubMcpConstants.serverKey) continue;
        if (entry.value is! Map) continue;
        final map = Map<String, dynamic>.from(
          (entry.value as Map).map((k, v) => MapEntry(k.toString(), v)),
        );
        final parsed = _fromCursorMap(id, map);
        if (parsed != null) result.add(parsed);
      }
      return result;
    } on FormatException {
      return const [];
    }
  }

  static List<McpServerEntry> parseCodexServers(String? text) {
    if (text == null || text.trim().isEmpty) return const [];
    final ids = <String>{};
    for (final match in RegExp(
      r'^\[mcp_servers\.([^.\]]+)\]\s*$',
      multiLine: true,
    ).allMatches(text)) {
      final id = match.group(1)!;
      if (id.isNotEmpty && id != HubMcpConstants.serverKey) ids.add(id);
    }
    final result = <McpServerEntry>[];
    for (final id in ids) {
      final table = McpClientConfig.readCodexServerTable(text, id);
      if (table == null) continue;
      final parsed = _fromCodexTable(id, table);
      if (parsed != null) result.add(parsed);
    }
    return result;
  }

  static List<McpServerEntry> parseOpenCodeServers(String? text) {
    if (text == null || text.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) return const [];
      final mcp = decoded['mcp'];
      if (mcp is! Map) return const [];
      final mcpMap = Map<String, dynamic>.from(
        mcp.map((k, v) => MapEntry(k.toString(), v)),
      );
      McpClientConfig.prepareOpenCodeMcpMap(mcpMap);
      final result = <McpServerEntry>[];
      for (final entry in mcpMap.entries) {
        final id = entry.key.trim();
        if (id.isEmpty || id == HubMcpConstants.serverKey) continue;
        if (entry.value is! Map) continue;
        final map = Map<String, dynamic>.from(
          (entry.value as Map).map((k, v) => MapEntry(k.toString(), v)),
        );
        if (!McpClientConfig.isOpenCodeServerEntry(map)) continue;
        final parsed = _fromOpenCodeMap(id, map);
        if (parsed != null) result.add(parsed);
      }
      return result;
    } on FormatException {
      return const [];
    }
  }

  static McpServerEntry? _fromCursorMap(String id, Map<String, dynamic> map) {
    final type = map['type']?.toString();
    final url = _nonEmpty(map['url']);
    final command = _nonEmpty(map['command']);
    if (type == 'http' || (url != null && command == null)) {
      if (url == null) return null;
      return _entry(
        id: id,
        transport: McpTransport.http,
        url: url,
      );
    }
    if (command == null) return null;
    return _entry(
      id: id,
      transport: McpTransport.stdio,
      command: command,
      args: _stringList(map['args']),
      env: _stringMap(map['env']),
      cwd: _nonEmpty(map['cwd']),
    );
  }

  static McpServerEntry? _fromCodexTable(String id, CodexServerTable table) {
    final url = _nonEmpty(table.url);
    final command = _nonEmpty(table.command);
    if (url != null && command == null) {
      return _entry(id: id, transport: McpTransport.http, url: url);
    }
    if (command == null) return null;
    return _entry(
      id: id,
      transport: McpTransport.stdio,
      command: command,
      args: table.args ?? const [],
      env: table.env ?? const {},
      cwd: _nonEmpty(table.cwd),
    );
  }

  static McpServerEntry? _fromOpenCodeMap(String id, Map<String, dynamic> map) {
    final type = map['type']?.toString();
    final enabled = map['enabled'] as bool? ?? true;
    if (type == 'remote') {
      final url = _nonEmpty(map['url']);
      if (url == null) return null;
      return _entry(
        id: id,
        transport: McpTransport.http,
        url: url,
        enabled: enabled,
      );
    }
    if (type != 'local') return null;
    final commandList = _stringList(map['command']);
    if (commandList.isEmpty) return null;
    final command = commandList.first;
    final args =
        commandList.length > 1 ? commandList.sublist(1) : const <String>[];
    return _entry(
      id: id,
      transport: McpTransport.stdio,
      command: command,
      args: args,
      env: _fromOpenCodeEnv(_stringMap(map['environment'])),
      cwd: _nonEmpty(map['cwd']),
      enabled: enabled,
    );
  }

  static Map<String, String> _fromOpenCodeEnv(Map<String, String> env) {
    if (env.isEmpty) return const {};
    return {
      for (final e in env.entries)
        e.key: e.value.replaceAllMapped(
          RegExp(r'^\{env:([^}]+)\}$'),
          (m) => '\${env:${m[1]}}',
        ),
    };
  }

  static McpServerEntry _entry({
    required String id,
    required McpTransport transport,
    String? command,
    List<String> args = const [],
    Map<String, String> env = const {},
    String? cwd,
    String? url,
    bool enabled = true,
  }) {
    final canStart = transport == McpTransport.stdio &&
        command != null &&
        command.trim().isNotEmpty;
    return McpServerEntry(
      id: id,
      name: id,
      transport: transport,
      command: command,
      args: args,
      env: env,
      cwd: cwd,
      url: url,
      enabled: enabled,
      autoStart: enabled && canStart,
      builtIn: false,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  static String? _nonEmpty(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return value.map((e) => e.toString()).toList();
  }

  static Map<String, String> _stringMap(Object? value) {
    if (value is! Map) return const {};
    return value.map((k, v) => MapEntry(k.toString(), v.toString()));
  }
}
