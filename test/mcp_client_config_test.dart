import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_hub/models/mcp_server_entry.dart';
import 'package:mcp_hub/models/mcp_transport.dart';
import 'package:mcp_hub/services/mcp_client_config.dart';

void main() {
  final httpServer = McpServerEntry(
    id: 'kanbanMCP',
    name: 'Kanban',
    transport: McpTransport.http,
    url: 'http://127.0.0.1:18765/mcp',
    enabled: true,
  );

  final stdioServer = McpServerEntry(
    id: 'filesystem',
    name: 'Filesystem',
    transport: McpTransport.stdio,
    command: 'npx',
    args: const ['-y', '@modelcontextprotocol/server-filesystem', '.'],
    env: const {'FOO': 'bar'},
    cwd: r'C:\work\project',
    enabled: true,
  );

  group('upsertCursorJson', () {
    test('writes http and stdio entries and keeps others', () {
      const existing = '''
{
  "mcpServers": {
    "unityMCP": {
      "url": "http://127.0.0.1:8080/mcp"
    }
  }
}
''';
      final text = McpClientConfig.upsertCursorJson(
        existing,
        servers: [httpServer, stdioServer],
        managedIds: {'kanbanMCP', 'filesystem'},
      );
      final json = jsonDecode(text) as Map<String, dynamic>;
      final servers = json['mcpServers'] as Map;
      expect(servers['unityMCP'], isNotNull);
      expect((servers['kanbanMCP'] as Map)['url'], httpServer.url);
      expect((servers['filesystem'] as Map)['command'], 'npx');
      expect((servers['filesystem'] as Map)['cwd'], r'C:\work\project');
      expect((servers['filesystem'] as Map)['env'], {'FOO': 'bar'});
      expect(
        McpClientConfig.isCursorServerConfigured(text, server: httpServer),
        isTrue,
      );
    });

    test('removes disabled managed servers', () {
      final disabled = httpServer.copyWith(enabled: false);
      const existing = '''
{
  "mcpServers": {
    "kanbanMCP": { "url": "http://127.0.0.1:1/mcp", "type": "http" },
    "other": { "command": "echo" }
  }
}
''';
      final text = McpClientConfig.upsertCursorJson(
        existing,
        servers: [disabled],
        managedIds: {'kanbanMCP'},
      );
      final servers = (jsonDecode(text) as Map)['mcpServers'] as Map;
      expect(servers.containsKey('kanbanMCP'), isFalse);
      expect(servers['other'], isNotNull);
    });
  });

  group('upsertCodexToml', () {
    test('writes blocks and rmcp_client', () {
      final text = McpClientConfig.upsertCodexToml(
        null,
        servers: [httpServer, stdioServer],
        managedIds: {'kanbanMCP', 'filesystem'},
      );
      expect(text, contains('[mcp_servers.kanbanMCP]'));
      expect(text, contains('url = "${httpServer.url}"'));
      expect(text, contains('[mcp_servers.filesystem]'));
      expect(text, contains('command = "npx"'));
      expect(text, contains(r'cwd = "C:\\work\\project"'));
      expect(text, contains('[mcp_servers.filesystem.env]'));
      expect(text, contains('FOO = "bar"'));
      expect(text, contains('rmcp_client = true'));
      expect(
        McpClientConfig.isCodexServerConfigured(text, server: stdioServer),
        isTrue,
      );
    });
  });
}
