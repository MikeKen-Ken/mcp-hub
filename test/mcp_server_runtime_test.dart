import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_hub/controllers/hub_controller.dart';
import 'package:mcp_hub/models/mcp_management_kind.dart';
import 'package:mcp_hub/models/mcp_runtime_phase.dart';
import 'package:mcp_hub/models/mcp_server_entry.dart';
import 'package:mcp_hub/models/mcp_transport.dart';
import 'package:mcp_hub/services/hub_mcp_constants.dart';
import 'package:mcp_hub/services/mcp_process_manager.dart';
import 'package:mcp_hub/services/mcp_server_runtime_resolver.dart';

void main() {
  late HubController hub;

  setUp(() {
    hub = HubController(initiallyLoading: false);
  });

  tearDown(() => hub.dispose());

  group('McpServerRuntimeResolver', () {
    test('内置 hubMCP 归类为 builtInHttp', () {
      const server = McpServerEntry(
        id: HubMcpConstants.serverKey,
        name: 'Agent Hub',
        transport: McpTransport.http,
        url: 'http://127.0.0.1:18766/mcp',
        builtIn: true,
        enabled: true,
      );
      expect(
        McpServerRuntimeResolver.managementKindFor(server),
        McpManagementKind.builtInHttp,
      );
    });

    test('mcp-remote 归类为 remoteBridge', () {
      const server = McpServerEntry(
        id: 'tavily',
        name: 'tavily',
        transport: McpTransport.stdio,
        command: 'cmd',
        args: ['/c', 'npx', '-y', 'mcp-remote', 'https://example.com/mcp'],
        enabled: true,
      );
      expect(
        McpServerRuntimeResolver.managementKindFor(server),
        McpManagementKind.remoteBridge,
      );
    });

    test('Hub Git stdio 运行中时可停止、不可启动', () {
      const server = McpServerEntry(
        id: 'demo',
        name: 'demo',
        transport: McpTransport.stdio,
        repoUrl: 'https://github.com/org/demo',
        localPath: r'C:\Users\Demo\.mcp-hub\servers\demo',
        command: 'node',
        args: ['index.js'],
        enabled: true,
      );
      final info = McpServerRuntimeResolver.resolve(
        server: server,
        hubHost: hub.hubMcpHost,
        processState: const McpProcessState(
          status: McpProcessStatus.running,
          pid: 42,
        ),
        gitManaged: true,
      );
      expect(info.kind, McpManagementKind.hubGitStdio);
      expect(info.phase, McpRuntimePhase.running);
      expect(info.canStart, isFalse);
      expect(info.canStop, isTrue);
      expect(info.canUpdate, isTrue);
      expect(info.phaseBadgeLabel, '运行中 · pid 42');
    });

    test('远端 HTTP 不展示进程控制', () {
      const server = McpServerEntry(
        id: 'remote',
        name: 'remote',
        transport: McpTransport.http,
        url: 'https://example.com/mcp',
        enabled: true,
      );
      final info = McpServerRuntimeResolver.resolve(
        server: server,
        hubHost: hub.hubMcpHost,
        processState: const McpProcessState(status: McpProcessStatus.stopped),
        gitManaged: false,
      );
      expect(info.kind, McpManagementKind.externalHttp);
      expect(info.phase, McpRuntimePhase.external);
      expect(info.canStart, isFalse);
      expect(info.canStop, isFalse);
      expect(info.canUpdate, isFalse);
    });
  });
}
