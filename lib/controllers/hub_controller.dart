import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/mcp_server_entry.dart';
import '../models/mcp_transport.dart';
import '../services/mcp_catalog_store.dart';
import '../services/mcp_client_configurator.dart';
import '../services/mcp_paths.dart';
import '../services/mcp_process_manager.dart';
import '../services/mcp_repo_service.dart';

/// App-wide Hub state: catalog, toggles, clone, process, client config.
class HubController extends ChangeNotifier {
  HubController({
    McpCatalogStore? catalogStore,
    McpRepoService? repoService,
    McpProcessManager? processManager,
  })  : _catalogStore = catalogStore ?? McpCatalogStore(),
        _repoService = repoService ?? McpRepoService(),
        _processManager = processManager ?? McpProcessManager();

  final McpCatalogStore _catalogStore;
  final McpRepoService _repoService;
  final McpProcessManager _processManager;
  final _uuid = const Uuid();

  List<McpServerEntry> _servers = [];
  bool _loading = true;
  String? _lastMessage;
  bool? _cursorConfigured;
  bool? _codexConfigured;

  List<McpServerEntry> get servers => List.unmodifiable(_servers);
  bool get loading => _loading;
  String? get lastMessage => _lastMessage;
  bool? get cursorConfigured => _cursorConfigured;
  bool? get codexConfigured => _codexConfigured;
  bool get isDesktopSupported => McpPaths.isDesktopSupported;

  McpProcessState processState(String id) => _processManager.stateFor(id);

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    _servers = await _catalogStore.load();
    _loading = false;
    notifyListeners();
    await refreshClientStatus();
    await autoStartEnabledHttpServers();
  }

  Future<void> refreshClientStatus() async {
    _cursorConfigured = await McpClientConfigurator.areEnabledConfigured(
      McpClientKind.cursor,
      servers: _servers,
    );
    _codexConfigured = await McpClientConfigurator.areEnabledConfigured(
      McpClientKind.codex,
      servers: _servers,
    );
    notifyListeners();
  }

  Future<void> autoStartEnabledHttpServers() async {
    for (final server in _servers) {
      if (server.enabled &&
          server.autoStart &&
          server.transport == McpTransport.http) {
        await _processManager.start(server);
      }
    }
    notifyListeners();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final index = _servers.indexWhere((s) => s.id == id);
    if (index < 0) return;
    _servers = [..._servers];
    _servers[index] = _servers[index].copyWith(enabled: enabled);
    await _persist();
    if (!enabled && _servers[index].transport == McpTransport.http) {
      await _processManager.stop(id);
    }
    notifyListeners();
  }

  Future<String> addServer({
    required String name,
    required McpTransport transport,
    String? repoUrl,
    String? command,
    List<String> args = const [],
    Map<String, String> env = const {},
    String? url,
    bool enabled = true,
    bool autoStart = false,
    bool cloneRepo = true,
  }) async {
    final id = _slug(name);
    String? localPath;
    final root = McpPaths.serversRoot;
    if (root != null) {
      localPath = p.join(root, id);
    }

    if (cloneRepo && repoUrl != null && repoUrl.trim().isNotEmpty) {
      final result = await _repoService.clone(id: id, repoUrl: repoUrl.trim());
      _lastMessage = result.message;
      if (!result.ok) {
        notifyListeners();
        throw StateError(result.message);
      }
      localPath = result.localPath ?? localPath;
    }

    final entry = McpServerEntry(
      id: id,
      name: name.trim().isEmpty ? id : name.trim(),
      transport: transport,
      repoUrl: repoUrl?.trim(),
      localPath: localPath,
      command: command?.trim(),
      args: args,
      env: env,
      url: url?.trim(),
      enabled: enabled,
      autoStart: autoStart,
    );

    if (_servers.any((s) => s.id == entry.id)) {
      throw StateError('已存在同名 MCP：$id');
    }

    _servers = [..._servers, entry];
    await _persist();
    _lastMessage = '已添加 ${entry.name}';
    notifyListeners();
    return entry.id;
  }

  Future<void> removeServer(String id) async {
    await _processManager.stop(id);
    _servers = _servers.where((s) => s.id != id).toList();
    await _persist();
    _lastMessage = '已移除 $id';
    notifyListeners();
  }

  Future<void> startServer(String id) async {
    McpServerEntry? server;
    for (final s in _servers) {
      if (s.id == id) {
        server = s;
        break;
      }
    }
    if (server == null) return;
    final state = await _processManager.start(server);
    _lastMessage = switch (state.status) {
      McpProcessStatus.running => '已启动 ${server.name} (pid ${state.pid})',
      McpProcessStatus.error => state.lastError ?? '启动失败',
      _ => state.lastError ?? '未启动',
    };
    notifyListeners();
  }

  Future<void> stopServer(String id) async {
    await _processManager.stop(id);
    _lastMessage = '已停止 $id';
    notifyListeners();
  }

  Future<McpConfigureResult> configureClient(McpClientKind kind) async {
    final result = await McpClientConfigurator.configure(
      kind,
      servers: _servers,
    );
    _lastMessage = result.message;
    await refreshClientStatus();
    notifyListeners();
    return result;
  }

  Future<McpConfigureResult> configureAllClients() async {
    final cursor = await configureClient(McpClientKind.cursor);
    final codex = await configureClient(McpClientKind.codex);
    final message = '${cursor.message}；${codex.message}';
    _lastMessage = message;
    notifyListeners();
    return McpConfigureResult(
      ok: cursor.ok && codex.ok,
      message: message,
    );
  }

  Future<void> _persist() => _catalogStore.save(_servers);

  String _slug(String name) {
    final cleaned = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (cleaned.isNotEmpty) return cleaned;
    return 'mcp-${_uuid.v4().substring(0, 8)}';
  }

  @override
  void dispose() {
    _processManager.stopAll();
    super.dispose();
  }
}
