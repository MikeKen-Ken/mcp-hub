import 'package:flutter/foundation.dart';
import 'package:mcp_dart/mcp_dart.dart';

import '../controllers/hub_controller.dart';
import 'hub_mcp_constants.dart';
import 'hub_mcp_tools.dart';
import 'mcp_paths.dart';

enum HubMcpStatus { stopped, starting, running, error }

/// Embedded Streamable HTTP MCP for Agent Hub itself.
class HubMcpHost extends ChangeNotifier {
  HubMcpHost(this._hub);

  final HubController _hub;
  StreamableMcpServer? _server;
  HubMcpStatus status = HubMcpStatus.stopped;
  String? lastError;
  int boundPort = HubMcpConstants.defaultPort;

  bool get isSupported => McpPaths.isDesktopSupported;

  String get endpointUrl => HubMcpConstants.endpointUrl(boundPort);

  bool get isRunning => status == HubMcpStatus.running;

  Future<void> syncWithSettings({required bool enabled}) async {
    if (!isSupported) {
      await stop();
      return;
    }
    if (!enabled) {
      await stop();
      return;
    }
    if (isRunning) return;
    await start();
  }

  Future<void> start({int port = HubMcpConstants.defaultPort}) async {
    if (!isSupported) {
      lastError = '当前平台不支持内嵌 MCP（请用 Windows/macOS/Linux 桌面端）';
      status = HubMcpStatus.error;
      notifyListeners();
      return;
    }

    await stop();
    status = HubMcpStatus.starting;
    lastError = null;
    boundPort = port;
    notifyListeners();

    try {
      final server = StreamableMcpServer(
        serverFactory: (_) => _buildServer(),
        host: HubMcpConstants.host,
        port: port,
        path: HubMcpConstants.path,
        eventStore: InMemoryEventStore(),
        enableDnsRebindingProtection: true,
        allowedHosts: const {'127.0.0.1', 'localhost'},
        enableJsonResponse: true,
      );
      await server.start();
      _server = server;
      boundPort = server.boundPort;
      status = HubMcpStatus.running;
      debugPrint('Hub MCP 已监听 $endpointUrl');
    } catch (error) {
      _server = null;
      status = HubMcpStatus.error;
      lastError = error.toString();
      debugPrint('Hub MCP 启动失败：$error');
    }
    notifyListeners();
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    if (server != null) {
      try {
        await server.stop();
      } catch (error) {
        debugPrint('Hub MCP 停止失败：$error');
      }
    }
    if (status != HubMcpStatus.stopped) {
      status = HubMcpStatus.stopped;
      notifyListeners();
    }
  }

  McpServer _buildServer() {
    final server = McpServer(
      const Implementation(
        name: HubMcpConstants.implementationName,
        version: HubMcpConstants.implementationVersion,
      ),
      options: const McpServerOptions(
        protocol: McpProtocol.stable,
        capabilities: ServerCapabilities(
          tools: ServerCapabilitiesTools(),
        ),
      ),
    );
    registerHubMcpTools(server, _hub);
    return server;
  }

  @override
  void dispose() {
    final server = _server;
    _server = null;
    server?.stop();
    super.dispose();
  }
}
