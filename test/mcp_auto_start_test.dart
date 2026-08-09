import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_hub/models/mcp_server_entry.dart';
import 'package:mcp_hub/models/mcp_transport.dart';

void main() {
  group('shouldAutoStartByHub', () {
    test('已启用 HTTP 且有 command 时应自动启动（不依赖 autoStart 字段）', () {
      const server = McpServerEntry(
        id: 'http-demo',
        name: 'HTTP Demo',
        transport: McpTransport.http,
        command: 'npx',
        args: ['-y', 'demo'],
        url: 'http://127.0.0.1:3000/mcp',
        enabled: true,
        autoStart: false,
      );
      expect(server.canHubStartProcess, isTrue);
      expect(server.shouldAutoStartByHub, isTrue);
    });

    test('未启用时不自动启动', () {
      const server = McpServerEntry(
        id: 'http-demo',
        name: 'HTTP Demo',
        transport: McpTransport.http,
        command: 'npx',
        enabled: false,
        autoStart: true,
      );
      expect(server.shouldAutoStartByHub, isFalse);
    });

    test('仅有 URL、无 command 时 Hub 不拉起进程', () {
      const server = McpServerEntry(
        id: 'remote',
        name: 'Remote',
        transport: McpTransport.http,
        url: 'http://127.0.0.1:9/mcp',
        enabled: true,
        autoStart: true,
      );
      expect(server.canHubStartProcess, isFalse);
      expect(server.shouldAutoStartByHub, isFalse);
    });

    test('已启用 stdio 且有 command 时应自动启动', () {
      const server = McpServerEntry(
        id: 'stdio-demo',
        name: 'Stdio Demo',
        transport: McpTransport.stdio,
        command: 'npx',
        enabled: true,
        autoStart: true,
      );
      expect(server.canHubStartProcess, isTrue);
      expect(server.shouldAutoStartByHub, isTrue);
    });

    test('内置 hubMCP 不走进程管理器自动启动', () {
      const server = McpServerEntry(
        id: 'hubMCP',
        name: 'Agent Hub',
        transport: McpTransport.http,
        url: 'http://127.0.0.1:18766/mcp',
        command: 'ignored',
        enabled: true,
        builtIn: true,
      );
      expect(server.canHubStartProcess, isFalse);
      expect(server.shouldAutoStartByHub, isFalse);
    });

    test('空白 command 视为不可拉起', () {
      const server = McpServerEntry(
        id: 'blank',
        name: 'Blank',
        transport: McpTransport.http,
        command: '   ',
        enabled: true,
      );
      expect(server.canHubStartProcess, isFalse);
      expect(server.shouldAutoStartByHub, isFalse);
    });
  });
}
