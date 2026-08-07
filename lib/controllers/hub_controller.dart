import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../app_brand.dart';
import '../features/skill_sync/skill_sync.dart';
import '../models/mcp_server_entry.dart';
import '../models/mcp_transport.dart';
import '../services/hub_mcp_constants.dart';
import '../services/hub_mcp_host.dart';
import '../services/mcp_catalog_store.dart';
import '../services/mcp_client_configurator.dart';
import '../services/mcp_paths.dart';
import '../services/mcp_process_manager.dart';
import '../services/mcp_repo_service.dart';
import '../services/repo_name.dart';
import '../webdav/catalog_sync_document.dart';
import '../webdav/catalog_sync_mapper.dart';
import '../webdav/webdav_config.dart';
import '../webdav/webdav_sync_service.dart';

/// App-wide Hub state: catalog, toggles, clone, process, client config, WebDAV.
class HubController extends ChangeNotifier {
  HubController({
    McpCatalogStore? catalogStore,
    McpRepoService? repoService,
    McpProcessManager? processManager,
    WebDavConfigStore? webDavConfigStore,
    bool initiallyLoading = true,
  })  : _catalogStore = catalogStore ?? McpCatalogStore(),
        _repoService = repoService ?? McpRepoService(),
        _processManager = processManager ?? McpProcessManager(),
        _webDavConfigStore = webDavConfigStore ?? WebDavConfigStore(),
        _loading = initiallyLoading {
    hubMcpHost = HubMcpHost(this);
    hubMcpHost.addListener(_onHostChanged);
    webDavSync = WebDavSyncService(
      loadConfig: () async => webDavConfig,
      loadLocalDocument: () async => CatalogSyncMapper.toDocument(_servers),
      applyDocument: _applySyncDocument,
    );
    webDavSync.addListener(_onWebDavChanged);
    skillSync = SkillSyncService(
      loadConfig: () async => webDavConfig,
    );
    skillSync.addListener(_onSkillSyncChanged);
  }

  final McpCatalogStore _catalogStore;
  final McpRepoService _repoService;
  final McpProcessManager _processManager;
  final WebDavConfigStore _webDavConfigStore;
  final _uuid = const Uuid();

  late final HubMcpHost hubMcpHost;
  late final WebDavSyncService webDavSync;
  late final SkillSyncService skillSync;

  List<McpServerEntry> _servers = [];
  WebDavConfig webDavConfig = WebDavConfig.empty;
  bool _loading;
  String? _lastMessage;
  bool? _cursorConfigured;
  bool? _codexConfigured;

  List<McpServerEntry> get servers => List.unmodifiable(_servers);
  bool get loading => _loading;
  String? get lastMessage => _lastMessage;
  bool? get cursorConfigured => _cursorConfigured;
  bool? get codexConfigured => _codexConfigured;
  bool get isDesktopSupported => McpPaths.isDesktopSupported;

  String get hubEndpointUrl => hubMcpHost.endpointUrl;

  McpProcessState processState(String id) => _processManager.stateFor(id);

  void _onHostChanged() {
    _syncBuiltInUrl();
    notifyListeners();
  }

  void _onWebDavChanged() => notifyListeners();

  void _onSkillSyncChanged() => notifyListeners();

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    webDavConfig = await _webDavConfigStore.load();
    _servers = await _catalogStore.load();
    await _ensureBuiltInHubMcp();
    _loading = false;
    notifyListeners();
    await refreshClientStatus();
    await _syncHubMcpHost();
    await autoStartEnabledHttpServers();
    if (webDavConfig.enabled &&
        webDavConfig.autoPull &&
        webDavConfig.isConfigured) {
      unawaited(webDavSync.pullNow());
    }
    await webDavSync.startPolling();
  }

  Future<void> _applySyncDocument(CatalogSyncDocument doc) async {
    _servers = CatalogSyncMapper.applyDocument(local: _servers, doc: doc);
    await _ensureBuiltInHubMcp(persist: false);
    await _catalogStore.save(_servers);
    _lastMessage = '已从 WebDAV 合并目录（${doc.servers.length} 个 MCP）';
    notifyListeners();
  }

  Future<void> _ensureBuiltInHubMcp({bool persist = true}) async {
    final index =
        _servers.indexWhere((s) => s.id == HubMcpConstants.serverKey);
    final builtIn = McpServerEntry(
      id: HubMcpConstants.serverKey,
      name: AppBrand.displayName,
      transport: McpTransport.http,
      url: hubEndpointUrl,
      enabled: true,
      builtIn: true,
      notes: '内置：用 AI 管理本 Hub（添加仓库、开关、一键配置等）',
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    if (index < 0) {
      _servers = [builtIn, ..._servers];
    } else {
      final existing = _servers[index];
      _servers = [..._servers];
      _servers[index] = existing.copyWith(
        name: AppBrand.displayName,
        transport: McpTransport.http,
        url: hubEndpointUrl,
        builtIn: true,
        notes: builtIn.notes,
      );
    }
    if (persist) await _persist(scheduleRemote: false);
  }

  void _syncBuiltInUrl() {
    final index =
        _servers.indexWhere((s) => s.id == HubMcpConstants.serverKey);
    if (index < 0) return;
    if (_servers[index].url == hubEndpointUrl) return;
    _servers = [..._servers];
    _servers[index] = _servers[index].copyWith(url: hubEndpointUrl);
    unawaited(_persist(scheduleRemote: false));
  }

  Future<void> _syncHubMcpHost() async {
    McpServerEntry? hub;
    for (final s in _servers) {
      if (s.id == HubMcpConstants.serverKey) {
        hub = s;
        break;
      }
    }
    await hubMcpHost.syncWithSettings(enabled: hub?.enabled ?? true);
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
      if (server.builtIn) continue;
      if (server.enabled &&
          server.autoStart &&
          server.transport == McpTransport.http &&
          server.command != null) {
        await _processManager.start(server);
      }
    }
    notifyListeners();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final index = _servers.indexWhere((s) => s.id == id);
    if (index < 0) return;
    _servers = [..._servers];
    // 开/关不 bump updatedAt，避免 WebDAV 把本机开关当成清单变更
    _servers[index] = _servers[index].copyWith(enabled: enabled);
    await _persist();
    if (id == HubMcpConstants.serverKey) {
      await _syncHubMcpHost();
    } else if (!enabled && _servers[index].transport == McpTransport.http) {
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
    String? cwd,
    String? url,
    bool enabled = true,
    bool autoStart = false,
    bool cloneRepo = true,
  }) async {
    final fromUrl = RepoName.fromGitUrl(repoUrl);
    final resolvedName =
        name.trim().isNotEmpty ? name.trim() : (fromUrl ?? '');
    final id = _slug(resolvedName.isNotEmpty ? resolvedName : fromUrl ?? '');
    if (id == HubMcpConstants.serverKey) {
      throw StateError('不能使用保留名 ${HubMcpConstants.serverKey}');
    }

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
      name: resolvedName.isNotEmpty ? resolvedName : id,
      transport: transport,
      repoUrl: repoUrl?.trim(),
      localPath: localPath,
      command: command?.trim(),
      args: args,
      env: env,
      cwd: cwd?.trim().isEmpty == true ? null : cwd?.trim(),
      url: url?.trim(),
      enabled: enabled,
      autoStart: autoStart,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
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

  Future<void> updateServer(String id) async {
    McpServerEntry? server;
    for (final s in _servers) {
      if (s.id == id) {
        server = s;
        break;
      }
    }
    if (server == null) {
      throw StateError('找不到 MCP：$id');
    }
    if (server.builtIn) {
      throw StateError('内置 hubMCP 无需 git pull');
    }
    final path = server.localPath;
    if (path == null || path.isEmpty) {
      throw StateError('没有本地仓库路径，无法更新');
    }
    final result = await _repoService.pull(localPath: path);
    _lastMessage = '${server.name}: ${result.message}';
    notifyListeners();
    if (!result.ok) {
      throw StateError(result.message);
    }
  }

  Future<void> updateAllServers() async {
    final withPath = _servers
        .where(
          (s) =>
              !s.builtIn &&
              s.localPath != null &&
              s.localPath!.isNotEmpty,
        )
        .toList();
    if (withPath.isEmpty) {
      _lastMessage = '没有可更新的本地仓库';
      notifyListeners();
      return;
    }
    final lines = <String>[];
    for (final server in withPath) {
      final result = await _repoService.pull(localPath: server.localPath!);
      lines.add('${server.name}: ${result.message}');
    }
    _lastMessage = lines.join('\n');
    notifyListeners();
  }

  Future<void> removeServer(String id) async {
    if (id == HubMcpConstants.serverKey) {
      throw StateError('不能移除内置 hubMCP');
    }
    McpServerEntry? server;
    for (final s in _servers) {
      if (s.id == id) {
        server = s;
        break;
      }
    }
    await _processManager.stop(id);

    String? deleteMsg;
    final path = server?.localPath;
    if (path != null && path.isNotEmpty) {
      final result = await _repoService.deleteLocal(localPath: path);
      deleteMsg = result.message;
      if (!result.ok) {
        _lastMessage = '已停止进程，但删除本地目录失败：$deleteMsg';
        notifyListeners();
        throw StateError(deleteMsg);
      }
    }

    webDavSync.rememberTombstone(id);
    _servers = _servers.where((s) => s.id != id).toList();
    await _persist();
    _lastMessage =
        deleteMsg == null ? '已移除 $id' : '已移除 $id；$deleteMsg';
    notifyListeners();
  }

  Future<void> startServer(String id) async {
    if (id == HubMcpConstants.serverKey) {
      await hubMcpHost.start();
      _lastMessage = hubMcpHost.isRunning
          ? 'hubMCP 已启动 $hubEndpointUrl'
          : (hubMcpHost.lastError ?? '启动失败');
      notifyListeners();
      return;
    }
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
    if (id == HubMcpConstants.serverKey) {
      await hubMcpHost.stop();
      _lastMessage = 'hubMCP 已停止';
      notifyListeners();
      return;
    }
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

  Future<bool> testWebDav(WebDavConfig config) =>
      webDavSync.testConnection(config);

  Future<void> saveWebDavConfig(WebDavConfig config) async {
    webDavConfig = config;
    await _webDavConfigStore.save(config);
    webDavSync.stopPolling();
    if (config.enabled && config.isConfigured) {
      if (config.autoPull) {
        unawaited(webDavSync.pullNow());
      }
      await webDavSync.startPolling();
      if (config.autoSync) {
        webDavSync.schedulePush();
      }
    }
    _lastMessage = config.enabled ? 'WebDAV 已保存并启用' : 'WebDAV 已关闭';
    notifyListeners();
  }

  Future<void> syncWebDavNow() async {
    await webDavSync.syncNow();
    _lastMessage = webDavSync.status == CatalogSyncStatus.success
        ? 'WebDAV 同步完成'
        : (webDavSync.lastError ?? '同步失败');
    notifyListeners();
  }

  Future<SkillSyncResult> syncSkillsFromWebDav(SkillTarget target) async {
    final result = await skillSync.syncFromWebDav(target);
    _lastMessage = result.message;
    notifyListeners();
    return result;
  }

  Future<SkillSyncResult> pushSkillsToWebDav(SkillTarget target) async {
    final result = await skillSync.pushToWebDav(target);
    _lastMessage = result.message;
    notifyListeners();
    return result;
  }

  Future<SkillSyncResult> syncResourceFromWebDav(
    AgentResourceKind resource,
    SkillTarget target,
  ) async {
    final result = await skillSync.syncResourceFromWebDav(resource, target);
    _lastMessage = result.message;
    notifyListeners();
    return result;
  }

  Future<SkillSyncResult> pushResourceToWebDav(
    AgentResourceKind resource,
    SkillTarget target,
  ) async {
    final result = await skillSync.pushResourceToWebDav(resource, target);
    _lastMessage = result.message;
    notifyListeners();
    return result;
  }

  Future<SkillSyncResult> syncResourceToAllTargets(
    AgentResourceKind resource,
  ) async {
    final result = await skillSync.syncResourceToAllTargets(resource);
    _lastMessage = result.message;
    notifyListeners();
    return result;
  }

  Future<SkillSyncResult> pushResourceToAllTargets(
    AgentResourceKind resource,
  ) async {
    final result = await skillSync.pushResourceToAllTargets(resource);
    _lastMessage = result.message;
    notifyListeners();
    return result;
  }

  Future<SkillSyncResult> syncAllSkillsFromWebDav() async {
    return syncResourceToAllTargets(AgentResourceKind.skill);
  }

  Future<SkillSyncResult> pushAllSkillsToWebDav() async {
    return pushResourceToAllTargets(AgentResourceKind.skill);
  }

  Future<void> _persist({bool scheduleRemote = true}) async {
    await _catalogStore.save(_servers);
    if (scheduleRemote) webDavSync.schedulePush();
  }

  String _slug(String name) {
    final cleaned = RepoName.slug(name);
    if (cleaned.isNotEmpty) return cleaned;
    return 'mcp-${_uuid.v4().substring(0, 8)}';
  }

  @override
  void dispose() {
    hubMcpHost.removeListener(_onHostChanged);
    webDavSync.removeListener(_onWebDavChanged);
    skillSync.removeListener(_onSkillSyncChanged);
    hubMcpHost.dispose();
    webDavSync.dispose();
    skillSync.dispose();
    _processManager.stopAll();
    super.dispose();
  }
}
