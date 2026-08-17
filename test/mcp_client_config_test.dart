import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_hub/common/agent_platforms.dart';
import 'package:mcp_hub/models/mcp_server_entry.dart';
import 'package:mcp_hub/models/mcp_transport.dart';
import 'package:mcp_hub/services/mcp_client_config.dart';
import 'package:mcp_hub/services/mcp_client_config_reader.dart';
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

    test('removes tombstoned servers while keeping unrelated entries', () {
      const existing = '''
{
  "mcpServers": {
    "removed": { "command": "echo" },
    "unityMCP": {
      "url": "http://127.0.0.1:8080/mcp"
    },
    "kanbanMCP": {
      "url": "http://127.0.0.1:1/mcp",
      "type": "http"
    }
  }
}
''';
      final text = McpClientConfig.upsertCursorJson(
        existing,
        servers: [httpServer],
        managedIds: {'kanbanMCP'},
        removeIds: {'removed'},
      );
      final servers = (jsonDecode(text) as Map)['mcpServers'] as Map;
      expect(servers.containsKey('removed'), isFalse);
      expect(servers['unityMCP'], isNotNull);
      expect((servers['kanbanMCP'] as Map)['url'], httpServer.url);
    });

    test('omits disabled managed servers from Cursor', () {
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
      expect(text, contains('enabled = true'));
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

    test('removes tombstoned tables', () {
      final existing = '''
[mcp_servers.removed]
command = "echo"

[mcp_servers.kanbanMCP]
url = "http://127.0.0.1:1/mcp"
''';
      final text = McpClientConfig.upsertCodexToml(
        existing,
        servers: [httpServer],
        managedIds: {'kanbanMCP'},
        removeIds: {'removed'},
      );
      expect(text, isNot(contains('[mcp_servers.removed]')));
      expect(text, contains('[mcp_servers.kanbanMCP]'));
      expect(text, contains('url = "${httpServer.url}"'));
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

    test('treats absent Cursor entry as aligned when Hub disabled', () {
      final disabled = httpServer.copyWith(enabled: false);
      final d = McpClientConfig.diagnoseCursorServer(
        '{"mcpServers": {}}',
        server: disabled,
      );
      expect(d.isAligned, isTrue);
    });

    test('reports leftover Cursor entry when Hub disabled', () {
      final disabled = httpServer.copyWith(enabled: false);
      const existing = '''
{
  "mcpServers": {
    "kanbanMCP": { "url": "http://127.0.0.1:18765/mcp", "type": "http" }
  }
}
''';
      final d = McpClientConfig.diagnoseCursorServer(
        existing,
        server: disabled,
      );
      expect(d.isAligned, isFalse);
      expect(d.diffs.single.field, 'enabled');
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

    test('writes and diagnoses Codex enabled flag', () {
      final disabled = httpServer.copyWith(enabled: false);
      final text = McpClientConfig.upsertCodexToml(
        null,
        servers: [disabled],
        managedIds: {'kanbanMCP'},
      );
      expect(text, contains('enabled = false'));
      expect(
        McpClientConfig.diagnoseCodexServer(text, server: disabled).isAligned,
        isTrue,
      );
      expect(
        McpClientConfig.diagnoseCodexServer(text, server: httpServer)
            .diffs
            .map((e) => e.field),
        contains('enabled'),
      );
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

    test('converts whole-value env placeholders to OpenCode {env:NAME}', () {
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

    test('expands embedded env placeholders using provided environment', () {
      final server = McpServerEntry(
        id: 'aseprite',
        name: 'Aseprite',
        transport: McpTransport.stdio,
        command: 'uv',
        args: const ['run', '-m', 'aseprite_mcp'],
        env: const {
          'ASEPRITE_PATH':
              r'${env:USERPROFILE}/Downloads/aseprite/aseprite.exe',
        },
        enabled: true,
      );
      final text = McpClientConfig.upsertOpenCodeJson(
        null,
        servers: [server],
        managedIds: {'aseprite'},
        environment: const {'USERPROFILE': r'C:\Users\Demo'},
      );
      final json = jsonDecode(text) as Map<String, dynamic>;
      final env =
          ((json['mcp'] as Map)['aseprite'] as Map)['environment'] as Map;
      expect(
        env['ASEPRITE_PATH'],
        r'C:\Users\Demo/Downloads/aseprite/aseprite.exe',
      );
      // 确保 JSON 文本里反斜杠已转义，避免 OpenCode 文本替换后破坏解析
      expect(text, contains(r'C:\\Users\\Demo/Downloads/aseprite/aseprite.exe'));
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

    test('writes OpenCode enabled=false when Hub disabled', () {
      final disabled = httpServer.copyWith(enabled: false);
      final text = McpClientConfig.upsertOpenCodeJson(
        null,
        servers: [disabled],
        managedIds: {'kanbanMCP'},
      );
      final json = jsonDecode(text) as Map<String, dynamic>;
      expect(((json['mcp'] as Map)['kanbanMCP'] as Map)['enabled'], isFalse);
      expect(
        McpClientConfig.diagnoseOpenCodeServer(text, server: disabled).isAligned,
        isTrue,
      );
    });
  });

  group('McpClientConfigReader', () {
    test('parseCursorServers reads http and stdio', () {
      const text = '''
{
  "mcpServers": {
    "kanbanMCP": { "url": "http://127.0.0.1:18765/mcp", "type": "http" },
    "filesystem": {
      "command": "npx",
      "args": ["-y", "fs"],
      "env": { "FOO": "bar" },
      "cwd": "C:\\\\work"
    },
    "hubMCP": { "url": "http://127.0.0.1:1/mcp" }
  }
}
''';
      final servers = McpClientConfigReader.parseCursorServers(text);
      expect(servers.map((s) => s.id), ['kanbanMCP', 'filesystem']);
      expect(servers.first.transport, McpTransport.http);
      expect(servers.first.enabled, isTrue);
      expect(servers.last.command, 'npx');
      expect(servers.last.env['FOO'], 'bar');
    });

    test('parseCodexServers reads tables', () {
      final text = '''
[mcp_servers.kanbanMCP]
url = "http://127.0.0.1:18765/mcp"

[mcp_servers.filesystem]
command = "npx"
args = ["-y", "fs"]
cwd = "C:\\\\work"

[mcp_servers.filesystem.env]
FOO = "bar"
''';
      final servers = McpClientConfigReader.parseCodexServers(text);
      expect(servers.map((s) => s.id), containsAll(['kanbanMCP', 'filesystem']));
    });

    test('parseOpenCodeServers reads local and remote', () {
      const text = '''
{
  "mcp": {
    "kanbanMCP": {
      "type": "remote",
      "url": "http://127.0.0.1:18765/mcp",
      "enabled": true
    },
    "filesystem": {
      "type": "local",
      "command": ["npx", "-y", "fs"],
      "environment": { "FOO": "{env:FOO}" },
      "enabled": false
    }
  }
}
''';
      final servers = McpClientConfigReader.parseOpenCodeServers(text);
      expect(servers.length, 2);
      final remote = servers.firstWhere((s) => s.id == 'kanbanMCP');
      expect(remote.enabled, isTrue);
      final local = servers.firstWhere((s) => s.id == 'filesystem');
      expect(local.command, 'npx');
      expect(local.args, ['-y', 'fs']);
      expect(local.env['FOO'], r'${env:FOO}');
      expect(local.enabled, isFalse);
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
