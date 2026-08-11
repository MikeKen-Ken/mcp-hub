import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_hub/common/agent_platforms.dart';
import 'package:mcp_hub/models/mcp_server_entry.dart';
import 'package:mcp_hub/models/mcp_transport.dart';
import 'package:mcp_hub/services/mcp_client_config.dart';
import 'package:mcp_hub/services/mcp_client_configurator.dart';

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
      expect(
        McpClientConfig.isCursorServerConfigured(text, server: stdioServer),
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
      expect(
        McpClientConfig.isCodexServerConfigured(text, server: httpServer),
        isTrue,
      );
      expect(McpClientConfig.hasCodexRmcpClient(text), isTrue);
    });
  });

  group('diagnoseCursorServer', () {
    test('reports missing server', () {
      const existing = '{"mcpServers": {}}';
      final d = McpClientConfig.diagnoseCursorServer(
        existing,
        server: httpServer,
      );
      expect(d.missing, isTrue);
      expect(d.isAligned, isFalse);
    });

    test('reports field mismatches for stdio', () {
      const existing = '''
{
  "mcpServers": {
    "filesystem": {
      "command": "node",
      "args": ["wrong"],
      "cwd": "D:\\\\other",
      "env": { "FOO": "baz" }
    }
  }
}
''';
      final d = McpClientConfig.diagnoseCursorServer(
        existing,
        server: stdioServer,
      );
      expect(d.missing, isFalse);
      expect(d.diffs.map((e) => e.field), containsAll(['command', 'args', 'cwd', 'env']));
    });

    test('reports url mismatch for http', () {
      const existing = '''
{
  "mcpServers": {
    "kanbanMCP": { "url": "http://127.0.0.1:1/mcp", "type": "http" }
  }
}
''';
      final d = McpClientConfig.diagnoseCursorServer(
        existing,
        server: httpServer,
      );
      expect(d.missing, isFalse);
      expect(d.diffs.single.field, 'url');
    });
  });

  group('diagnoseCodexServer', () {
    test('reports missing server without matching env table', () {
      const existing = '''
[mcp_servers.filesystem.env]
FOO = "bar"
''';
      final d = McpClientConfig.diagnoseCodexServer(
        existing,
        server: stdioServer,
      );
      expect(d.missing, isTrue);
    });

    test('reports command mismatch and keeps env parse', () {
      final existing = '''
[mcp_servers.filesystem]
command = "node"
args = ["-y", "@modelcontextprotocol/server-filesystem", "."]
cwd = "C:\\\\work\\\\project"

[mcp_servers.filesystem.env]
FOO = "bar"
''';
      final d = McpClientConfig.diagnoseCodexServer(
        existing,
        server: stdioServer,
      );
      expect(d.missing, isFalse);
      expect(d.diffs.single.field, 'command');
      expect(d.diffs.single.actual, 'node');
    });

    test('detects missing rmcp_client', () {
      expect(McpClientConfig.hasCodexRmcpClient('[mcp_servers.x]\ncommand = "a"\n'), isFalse);
      expect(
        McpClientConfig.hasCodexRmcpClient('[features]\nrmcp_client = true\n'),
        isTrue,
      );
    });
  });

  group('upsertOpenCodeJson', () {
    test('writes local and remote entries under flat mcp', () {
      const existing = '''
{
  "mcp": {
    "legacy": {
      "type": "local",
      "command": ["echo", "keep"]
    }
  }
}
''';
      final text = McpClientConfig.upsertOpenCodeJson(
        existing,
        servers: [httpServer, stdioServer],
        managedIds: {'kanbanMCP', 'filesystem'},
      );
      final json = jsonDecode(text) as Map<String, dynamic>;
      final mcp = json['mcp'] as Map<String, dynamic>;
      expect(mcp.containsKey('servers'), isFalse);
      expect(mcp['legacy'], isNotNull);
      expect((mcp['kanbanMCP'] as Map)['url'], httpServer.url);
      expect((mcp['kanbanMCP'] as Map)['type'], 'remote');
      expect((mcp['kanbanMCP'] as Map)['enabled'], isTrue);
      final fs = mcp['filesystem'] as Map;
      expect(fs['type'], 'local');
      expect(fs['command'], ['npx', '-y', '@modelcontextprotocol/server-filesystem', '.']);
      expect(fs['cwd'], r'C:\work\project');
      expect(fs['enabled'], isTrue);
      expect((fs['environment'] as Map)['FOO'], 'bar');
    });

    test('migrates legacy mcp.servers into flat mcp', () {
      const existing = '''
{
  "mcp": {
    "servers": {
      "legacy": {
        "type": "local",
        "command": ["echo", "keep"]
      }
    }
  }
}
''';
      final text = McpClientConfig.upsertOpenCodeJson(
        existing,
        servers: [httpServer],
        managedIds: {'kanbanMCP'},
      );
      final json = jsonDecode(text) as Map<String, dynamic>;
      final mcp = json['mcp'] as Map<String, dynamic>;
      expect(mcp.containsKey('servers'), isFalse);
      expect(mcp['legacy'], isNotNull);
      expect((mcp['kanbanMCP'] as Map)['type'], 'remote');
    });

    test('converts Cursor env placeholders to OpenCode {env:NAME}', () {
      final server = McpServerEntry(
        id: 'tavily',
        name: 'Tavily',
        transport: McpTransport.stdio,
        command: 'npx',
        args: const ['-y', 'mcp-remote'],
        env: const {'TAVILY_API_KEY': r'${env:TAVILY_API_KEY}'},
        enabled: true,
      );
      final text = McpClientConfig.upsertOpenCodeJson(
        null,
        servers: [server],
        managedIds: {'tavily'},
      );
      final json = jsonDecode(text) as Map<String, dynamic>;
      final env =
          ((json['mcp'] as Map)['tavily'] as Map)['environment'] as Map;
      expect(env['TAVILY_API_KEY'], '{env:TAVILY_API_KEY}');
    });

    test('diagnoseOpenCodeServer detects missing and mismatched fields', () {
      const text = '''
{
  "mcp": {
    "kanbanMCP": {
      "type": "remote",
      "url": "http://wrong"
    }
  }
}
''';
      final missing = McpClientConfig.diagnoseOpenCodeServer(
        '{}',
        server: httpServer,
      );
      expect(missing.missing, isTrue);

      final d = McpClientConfig.diagnoseOpenCodeServer(
        text,
        server: httpServer,
      );
      expect(d.missing, isFalse);
      expect(d.diffs.single.field, 'url');
    });
  });

  group('McpClientAlignReport', () {
    test('formats missing and field reasons', () {
      const report = McpClientAlignReport(
        platform: AgentPlatformId.cursor,
        status: McpClientAlignStatus.incomplete,
        missingServerIds: ['hubMCP', 'filesystem'],
        fieldDiffs: [
          McpClientFieldDiff(
            serverId: 'kanbanMCP',
            field: 'url',
            expected: 'a',
            actual: 'b',
          ),
        ],
      );
      expect(report.reasonText, contains('缺少 hubMCP、filesystem'));
      expect(report.reasonText, contains('kanbanMCP.url 不一致'));
      expect(report.prefixedReason, startsWith('Cursor：'));
      expect(report.shortLabel, '未对齐');
    });

    test('formats file missing and parse error', () {
      const missing = McpClientAlignReport(
        platform: AgentPlatformId.codex,
        status: McpClientAlignStatus.fileMissing,
      );
      expect(missing.reasonText, '配置文件不存在');
      expect(missing.shortLabel, '配置文件不存在');

      const parse = McpClientAlignReport(
        platform: AgentPlatformId.cursor,
        status: McpClientAlignStatus.parseError,
        parseErrorMessage: 'Unexpected character',
      );
      expect(parse.reasonText, contains('配置解析失败'));
      expect(parse.reasonText, contains('Unexpected character'));
    });

    test('formats rmcp_client missing', () {
      const report = McpClientAlignReport(
        platform: AgentPlatformId.codex,
        status: McpClientAlignStatus.incomplete,
        rmcpClientMissing: true,
      );
      expect(report.reasonText, '缺少 rmcp_client');
      expect(report.prefixedReason, 'Codex：缺少 rmcp_client');
    });
  });
}
