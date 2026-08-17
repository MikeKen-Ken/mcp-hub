import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../common/agent_platforms.dart';
import '../common/package_time.dart';
import '../app_brand.dart';
import '../features/config_backup/config_backup.dart';
import '../features/skill_sync/skill_sync.dart';
import '../models/mcp_server_entry.dart';
import '../models/mcp_transport.dart';
import '../services/hub_mcp_constants.dart';
import '../services/hub_mcp_host.dart';
import '../services/mcp_catalog_store.dart';
import '../services/mcp_client_configurator.dart';
import '../services/mcp_paths.dart';
import '../services/mcp_process_manager.dart';
import '../services/mcp_repo_post_pull.dart';
import '../services/mcp_repo_service.dart';
import '../models/mcp_server_runtime_info.dart';
import '../services/mcp_server_runtime_resolver.dart';
import '../services/repo_name.dart';
import '../webdav/catalog_sync_document.dart';
import '../webdav/catalog_sync_mapper.dart';
import '../webdav/package_version_store.dart';
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
  }) : _catalogStore = catalogStore ?? McpCatalogStore(),
       _repoService = repoService ?? McpRepoService(),
       _processManager =
           processManager ?? McpProcessManager(onStateChanged: () {}),
       _webDavConfigStore = webDavConfigStore ?? WebDavConfigStore(),
       _loading = initiallyLoading {
    if (processManager == null) {
      _processManager.onStateChanged = _onProcessStateChanged;
    }
    hubMcpHost = HubMcpHost(this);
    hubMcpHost.addListener(_onHostChanged);
    _packageVersions = PackageVersionStore();
    webDavSync = WebDavSyncService(
      loadConfig: () async => webDavConfig,
      loadLocalDocument: () async => CatalogSyncMapper.toDocument(_servers),
      applyDocument: _applySyncDocument,
      versionStore: _packageVersions,
    );
    webDavSync.addListener(_onWebDavChanged);
    skillSync = SkillSyncService(
      loadConfig: () async => webDavConfig,
      versionStore: _packageVersions,
    );
    skillSync.addListener(_onSkillSyncChanged);
    configBackup = ConfigBackupService();
    autoConfigBackup = AutoConfigBackupService(
      backupService: configBackup,
      loadServers: () async => List<McpServerEntry>.from(_servers),
    );
    autoConfigBackup.addListener(_onAutoConfigBackupChanged);
  }

  final McpCatalogStore _catalogStore;
  final McpRepoService _repoService;
  final McpProcessManager _processManager;
  final WebDavConfigStore _webDavConfigStore;
  final _uuid = const Uuid();

  late final HubMcpHost hubMcpHost;
  late final PackageVersionStore _packageVersions;
  late final WebDavSyncService webDavSync;
  late final SkillSyncService skillSync;
  late final ConfigBackupService configBackup;
  late final AutoConfigBackupService autoConfigBackup;

  List<McpServerEntry> _servers = [];
  WebDavConfig webDavConfig = WebDavConfig.empty;
  bool _loading;
  String? _lastMessage;
  final Map<AgentPlatformId, McpClientAlignReport?> _clientAlignReports = {};
  final Map<String, bool> _gitManaged = {};

  List<McpServerEntry> get servers => List.unmodifiable(_servers);
  bool get loading => _loading;
  String? get lastMessage => _lastMessage;

  McpClientAlignReport? clientAlignReport(AgentPlatformId platform) =>
      _clientAlignReports[platform];

  /// 兼容旧 UI。
  McpClientAlignReport? get cursorAlignReport =>
      _clientAlignReports[AgentPlatformId.cursor];

  /// 兼容旧 UI。
  McpClientAlignReport? get codexAlignReport =>
      _clientAlignReports[AgentPlatformId.codex];

  McpClientAlignReport? get openCodeAlignReport =>
      _clientAlignReports[AgentPlatformId.openCode];

  Iterable<McpClientAlignReport?> get mcpClientAlignReports =>
      AgentPlatforms.mcpConfigurable.map((p) => _clientAlignReports[p.id]);

  /// `null` 表示检测中；兼容旧 UI。
  bool? get cursorConfigured =>
      _clientAlignReports[AgentPlatformId.cursor]?.isAligned;

  /// `null` 表示检测中；兼容旧 UI。
  bool? get codexConfigured =>
      _clientAlignReports[AgentPlatformId.codex]?.isAligned;
  bool get isDesktopSupported => McpPaths.isDesktopSupported;

  String get hubEndpointUrl => hubMcpHost.endpointUrl;

  McpProcessState processState(String id) => _processManager.stateFor(id);

  bool isGitManaged(String id) => _gitManaged[id] ?? false;

  McpServerRuntimeInfo runtimeInfoFor(McpServerEntry server) {
    return McpServerRuntimeResolver.resolve(
      server: server,
      hubHost: hubMcpHost,
      processState: processState(server.id),
      gitManaged: isGitManaged(server.id),
    );
  }

  bool get hasUpdatableServers => _servers.any((s) => isGitManaged(s.id));

  void _onProcessStateChanged() => notifyListeners();

  void _onHostChanged() {
    _syncBuiltInUrl();
    notifyListeners();
  }

  void _onWebDavChanged() => notifyListeners();

  void _onSkillSyncChanged() => notifyListeners();

  void _onAutoConfigBackupChanged() => notifyListeners();

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    webDavConfig = await _webDavConfigStore.load();
    _servers = await _catalogStore.load();
    await _packageVersions.load();
    webDavSync.hydrateCatalogUploadedAt(
      _packageVersions.get(PackageVersionStore.catalogKey),
    );
    skillSync.hydratePackageUploadedAt(_packageVersions.snapshot());
    await webDavSync.seedCatalogUploadedAtIfMissing();
    await _ensureBuiltInHubMcp();
    await _repairInvalidWorkingDirectories();
    await _migrateAutoStartForEnabledServers();
    await _refreshGitManagedFlags();
    _loading = false;
    notifyListeners();
    await refreshClientStatus();
    await _syncHubMcpHost();
    await autoStartEnabledServers();
    await autoConfigBackup.initialize();
    if (webDavConfig.enabled &&
        webDavConfig.autoPull &&
        webDavConfig.isConfigured) {
      unawaited(webDavSync.mergeNow());
    }
    await webDavSync.startPolling();
  }

  /// 旧目录里「已启用但 autoStart=false」会导致不启动；迁移为一致标记。
  Future<void> _migrateAutoStartForEnabledServers() async {
    var changed = false;
    final next = <McpServerEntry>[];
    for (final server in _servers) {
      if (server.shouldAutoStartByHub && !server.autoStart) {
        changed = true;
        next.add(server.copyWith(autoStart: true));
      } else {
        next.add(server);
      }
    }
    if (!changed) return;
    _servers = next;
    await _persist(scheduleRemote: false);
  }

  Future<void> _refreshGitManagedFlags() async {
    final next = <String, bool>{};
    for (final server in _servers) {
      next[server.id] = await _repoService.isHubGitCheckout(server.localPath);
    }
    _gitManaged
      ..clear()
      ..addAll(next);
  }

  /// 客户端会直接使用目录中的 cwd；失效目录会令 Windows 无法创建 stdio
  /// 进程。优先回退到已存在的本地仓库，否则清空 cwd 让客户端继承自身目录。
  Future<void> _repairInvalidWorkingDirectories() async {
    var changed = false;
    final next = <McpServerEntry>[];
    for (final server in _servers) {
      final configured = server.cwd;
      if (configured == null || configured.trim().isEmpty) {
        next.add(server);
        continue;
      }
      final resolved = await _processManager.resolveWorkingDirectory(server);
      if (resolved == configured) {
        next.add(server);
        continue;
      }
      changed = true;
      next.add(
        resolved == null
            ? server.copyWith(clearCwd: true)
            : server.copyWith(cwd: resolved),
      );
    }
    if (!changed) return;
    _servers = next;
    await _persist(scheduleRemote: false);
  }

  Future<void> _applySyncDocument(CatalogSyncDocument doc) async {
    _servers = CatalogSyncMapper.applyDocument(local: _servers, doc: doc);
    await _ensureBuiltInHubMcp(persist: false);
    await _repairInvalidWorkingDirectories();
    await _catalogStore.save(_servers);
    await _refreshGitManagedFlags();
    _lastMessage = '已从 WebDAV 合并目录（${doc.servers.length} 个 MCP）';
    notifyListeners();
    await refreshClientStatus();
    // 合并后补拉本机已启用且有启动命令的 MCP。
    await autoStartEnabledServers();
  }

  Future<void> _ensureBuiltInHubMcp({bool persist = true}) async {
    final index = _servers.indexWhere((s) => s.id == HubMcpConstants.serverKey);
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
    final index = _servers.indexWhere((s) => s.id == HubMcpConstants.serverKey);
    if (index < 0) return;
    if (_servers[index].url == hubEndpointUrl) return;
    _servers = [..._servers];
    _servers[index] = _servers[index].copyWith(url: hubEndpointUrl);
    unawaited(_persist(scheduleRemote: false));
    unawaited(refreshClientStatus());
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
    for (final platform in AgentPlatforms.mcpConfigurable) {
      _clientAlignReports[platform.id] = null;
    }
    notifyListeners();
    for (final platform in AgentPlatforms.mcpConfigurable) {
      _clientAlignReports[platform.id] =
          await McpClientConfigurator.diagnoseAll(
            platform.id,
            servers: _servers,
          );
    }
    notifyListeners();
  }

  /// 已启用且有启动命令的 MCP 在 Hub 启动时自动拉起。
  /// 不再依赖单独的 autoStart 开关，避免「已启用却不启动」。
  Future<void> autoStartEnabledServers() async {
    for (final server in _servers) {
      if (!server.shouldAutoStartByHub) continue;
      await _processManager.start(server);
    }
    notifyListeners();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final index = _servers.indexWhere((s) => s.id == id);
    if (index < 0) return;
    _servers = [..._servers];
    // 开/关不 bump updatedAt，避免 WebDAV 把本机开关当成清单变更
    final current = _servers[index];
    _servers[index] = current.copyWith(
      enabled: enabled,
      // 启用可拉起的 MCP 时同步标记，便于列表展示「自动」
      autoStart: enabled && current.canHubStartProcess
          ? true
          : current.autoStart,
    );
    await _persist();
    if (id == HubMcpConstants.serverKey) {
      await _syncHubMcpHost();
    } else if (_servers[index].canHubStartProcess) {
      if (enabled && _servers[index].shouldAutoStartByHub) {
        await _processManager.start(_servers[index]);
      } else if (!enabled) {
        await _processManager.stop(id);
      }
    }
    notifyListeners();
    final sync = await configureAllClients();
    if (sync.ok) {
      _lastMessage = enabled
          ? '已启用 $id，并同步到 Cursor / Codex / OpenCode'
          : '已禁用 $id，并同步到 Cursor / Codex / OpenCode';
      notifyListeners();
    }
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
    bool? autoStart,
    bool cloneRepo = true,
  }) async {
    final fromUrl = RepoName.fromGitUrl(repoUrl);
    final resolvedName = name.trim().isNotEmpty ? name.trim() : (fromUrl ?? '');
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
      if (localPath != null && localPath.isNotEmpty) {
        final postPull = await McpRepoPostPull.apply(localPath: localPath);
        if (!postPull.ok) {
          _lastMessage = McpRepoService.joinMessages([
            result.message,
            postPull.message,
          ]);
          notifyListeners();
          throw StateError(postPull.message);
        }
        _lastMessage = McpRepoService.joinMessages([
          result.message,
          postPull.message,
        ]);
      }
    }

    final trimmedCommand = command?.trim();
    final resolvedCommand = (trimmedCommand == null || trimmedCommand.isEmpty)
        ? null
        : trimmedCommand;
    // 有启动命令的 MCP 默认自动启动。
    final resolvedAutoStart = autoStart ?? (enabled && resolvedCommand != null);

    final entry = McpServerEntry(
      id: id,
      name: resolvedName.isNotEmpty ? resolvedName : id,
      transport: transport,
      repoUrl: repoUrl?.trim(),
      localPath: localPath,
      command: resolvedCommand,
      args: args,
      env: env,
      cwd: cwd?.trim().isEmpty == true ? null : cwd?.trim(),
      url: url?.trim(),
      enabled: enabled,
      autoStart: resolvedAutoStart,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    if (_servers.any((s) => s.id == entry.id)) {
      throw StateError('已存在同名 MCP：$id');
    }

    _servers = [..._servers, entry];
    await _persist();
    await _refreshGitManagedFlags();
    if (entry.shouldAutoStartByHub) {
      await _processManager.start(entry);
    }
    _lastMessage = '已添加 ${entry.name}';
    notifyListeners();
    await refreshClientStatus();
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
    if (!await _repoService.isHubGitCheckout(path)) {
      throw StateError('不是 Hub 管理的 Git 仓库，无法 git 更新');
    }
    final wasRunning = processState(id).status == McpProcessStatus.running;
    final result = await _repoService.updateCheckout(localPath: path);
    _lastMessage = '${server.name}: ${result.message}';
    notifyListeners();
    if (!result.ok) {
      throw StateError(result.message);
    }
    if (wasRunning && server.shouldAutoStartByHub) {
      await _processManager.start(server);
      _lastMessage = '${server.name}: ${result.message}（已重启进程）';
      notifyListeners();
    }
  }

  Future<void> updateAllServers() async {
    await _refreshGitManagedFlags();
    final withPath = _servers
        .where((s) => !s.builtIn && isGitManaged(s.id))
        .toList();
    if (withPath.isEmpty) {
      _lastMessage = '没有可更新的本地仓库';
      notifyListeners();
      return;
    }
    final lines = <String>[];
    var failCount = 0;
    for (final server in withPath) {
      final wasRunning =
          processState(server.id).status == McpProcessStatus.running;
      final result = await _repoService.updateCheckout(
        localPath: server.localPath!,
      );
      var line = '${server.name}: ${result.message}';
      if (!result.ok) {
        failCount++;
      } else if (wasRunning && server.shouldAutoStartByHub) {
        await _processManager.start(server);
        line = '$line（已重启进程）';
      }
      lines.add(line);
    }
    final summary = failCount == 0
        ? '已更新 ${lines.length} 个仓库'
        : '部分失败（${lines.length - failCount} 成功 / $failCount 失败）';
    _lastMessage = '$summary\n${lines.join('\n')}';
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
    await _refreshGitManagedFlags();
    _lastMessage = deleteMsg == null ? '已移除 $id' : '已移除 $id；$deleteMsg';
    notifyListeners();
    await refreshClientStatus();
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

  Future<McpConfigureResult> configureClient(AgentPlatformId platform) async {
    final removeIds = webDavSync.tombstones.keys.toSet();
    final result = await McpClientConfigurator.configure(
      platform,
      servers: _servers,
      removeIds: removeIds,
    );
    _lastMessage = result.message;
    await refreshClientStatus();
    notifyListeners();
    return result;
  }

  Future<McpConfigureResult> configureAllClients() async {
    final removeIds = webDavSync.tombstones.keys.toSet();
    final results = <McpConfigureResult>[];
    for (final platform in AgentPlatforms.mcpConfigurable) {
      results.add(
        await McpClientConfigurator.configure(
          platform.id,
          servers: _servers,
          removeIds: removeIds,
        ),
      );
    }
    final message = results.map((r) => r.message).join('；');
    final ok = results.every((r) => r.ok);
    _lastMessage = message;
    notifyListeners();
    await refreshClientStatus();
    return McpConfigureResult(ok: ok, message: message);
  }

  /// 从 Cursor / Codex / Open Code 配置导入 Hub 未登记的 MCP。
  Future<McpClientImportResult> importMissingFromClients() async {
    final result = await McpClientConfigurator.importMissingServers(
      hubServers: _servers,
    );
    if (!result.ok || result.imported.isEmpty) {
      _lastMessage = result.message;
      notifyListeners();
      return result;
    }
    await _mergeImportedServers(result.imported);
    _lastMessage =
        '已导入 ${result.importedCount} 个 MCP：${result.imported.map((s) => s.id).join('、')}';
    notifyListeners();
    return result.copyWith(message: _lastMessage!);
  }

  Future<void> _mergeImportedServers(List<McpServerEntry> imported) async {
    final existing = {for (final s in _servers) s.id: s};
    final root = McpPaths.serversRoot;
    for (final server in imported) {
      if (existing.containsKey(server.id)) continue;
      final localPath = root == null ? null : p.join(root, server.id);
      final merged = server.copyWith(localPath: localPath);
      _servers = [
        ..._servers,
        merged.canHubStartProcess && merged.enabled
            ? merged.copyWith(autoStart: true)
            : merged,
      ];
      existing[server.id] = server;
    }
    await _persist();
    await _refreshGitManagedFlags();
  }

  Future<bool> testWebDav(WebDavConfig config) =>
      webDavSync.testConnection(config);

  Future<void> saveWebDavConfig(WebDavConfig config) async {
    webDavConfig = config;
    await _webDavConfigStore.save(config);
    webDavSync.stopPolling();
    if (config.enabled && config.isConfigured) {
      if (config.autoPull) {
        unawaited(webDavSync.mergeNow());
      }
      await webDavSync.startPolling();
      if (config.autoSync) {
        webDavSync.schedulePush();
      }
    }
    _lastMessage = config.enabled ? 'WebDAV 已保存并启用' : 'WebDAV 已关闭';
    notifyListeners();
  }

  bool get isWebDavReady => webDavConfig.enabled && webDavConfig.isConfigured;

  bool get isWebDavSyncing => webDavSync.status == CatalogSyncStatus.syncing;

  Future<DateTime?> peekRemoteCatalogUploadedAt() {
    return webDavSync.peekCatalogUploadedAt();
  }

  Future<DateTime?> peekRemoteResourceUploadedAt(AgentResourceKind resource) {
    return skillSync.peekRemoteUploadedAt(resource);
  }

  Future<void> syncWebDavNow() async {
    if (!_ensureWebDavReadyForManualSync()) return;
    await webDavSync.syncNow();
    _lastMessage = webDavSync.status == CatalogSyncStatus.success
        ? 'WebDAV 合并并上传完成'
        : '合并/上传失败：${webDavSync.lastError ?? '未知错误'}';
    notifyListeners();
  }

  /// 用远端 catalog.zip 覆盖本机 MCP 清单（不合并）。
  Future<void> pullWebDavNow() async {
    if (!_ensureWebDavReadyForManualSync()) return;
    await webDavSync.pullNow();
    _lastMessage = webDavSync.status == CatalogSyncStatus.success
        ? (webDavSync.catalogUploadedAt == null
            ? '已从 WebDAV 下载并覆盖 MCP 清单'
            : '已从 WebDAV 下载并覆盖 MCP 清单（远端版本 ${formatPackageTime(webDavSync.catalogUploadedAt)}）')
        : '下载失败：${webDavSync.lastError ?? '未知错误'}';
    notifyListeners();
  }

  /// 下载 catalog.zip 后与本机三路合并。
  Future<void> mergeWebDavNow() async {
    if (!_ensureWebDavReadyForManualSync()) return;
    await webDavSync.mergeNow();
    _lastMessage = webDavSync.status == CatalogSyncStatus.success
        ? '已从 WebDAV 合并 MCP 清单'
        : '合并失败：${webDavSync.lastError ?? '未知错误'}';
    notifyListeners();
  }

  /// 把本机 MCP 清单打成 catalog.zip 覆盖上传。
  Future<void> pushWebDavNow() async {
    if (!_ensureWebDavReadyForManualSync()) return;
    await webDavSync.pushNow();
    _lastMessage = webDavSync.status == CatalogSyncStatus.success
        ? '已上传 MCP 清单压缩包到 WebDAV'
        : '上传失败：${webDavSync.lastError ?? '未知错误'}';
    notifyListeners();
  }

  bool _ensureWebDavReadyForManualSync() {
    if (!isWebDavReady) {
      _lastMessage = '请先启用并配置 WebDAV';
      notifyListeners();
      return false;
    }
    if (isWebDavSyncing) {
      _lastMessage = '下载/上传进行中，请稍候';
      notifyListeners();
      return false;
    }
    return true;
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

  Future<SkillSyncResult> mergeResourceToAllTargets(
    AgentResourceKind resource,
  ) async {
    final result = await skillSync.mergeResourceToAllTargets(resource);
    _lastMessage = result.message;
    notifyListeners();
    return result;
  }

  Future<SkillSyncResult> convertResourceFromCursor(
    AgentResourceKind resource, {
    SkillTarget target = SkillTarget.codex,
  }) async {
    final result = await skillSync.convertFromCursor(resource, target: target);
    _lastMessage = result.message;
    notifyListeners();
    return result;
  }

  /// 转换单个资源到全部可转换目标（不碰缓存，只读 Cursor 正式目录）。
  Future<SkillSyncResult> convertResourceToAllTargets(
    AgentResourceKind resource,
  ) async {
    final result = await skillSync.convertResourceToAllTargets(resource);
    _lastMessage = result.message;
    notifyListeners();
    return result;
  }

  /// 一键转换全部可转换资源（Cursor → Codex / Open Code）。
  Future<SkillSyncResult> convertAllResourcesFromCursor() async {
    final result = await skillSync.convertAllFromCursor();
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

  Future<SkillSyncResult> syncAllResourcesFromWebDav() async {
    final result = await skillSync.syncAllResourcesFromWebDav();
    _lastMessage = result.message;
    notifyListeners();
    return result;
  }

  Future<SkillSyncResult> pushAllResourcesToWebDav() async {
    final result = await skillSync.pushAllResourcesToWebDav();
    _lastMessage = result.message;
    notifyListeners();
    return result;
  }

  Future<SkillSyncResult> mergeAllResourcesFromWebDav() async {
    final result = await skillSync.mergeAllResourcesFromWebDav();
    _lastMessage = result.message;
    notifyListeners();
    return result;
  }

  /// 用缓存覆盖正式 Cursor 目录（不自动转换；请另点「一键转换」）。
  Future<SkillSyncResult> applyResourceFromCache(
    AgentResourceKind resource,
  ) async {
    final result = await skillSync.applyResourceFromCache(resource);
    _lastMessage = result.message;
    notifyListeners();
    return result;
  }

  Future<SkillSyncResult> applyAllResourcesFromCache() async {
    final result = await skillSync.applyAllResourcesFromCache();
    _lastMessage = result.message;
    notifyListeners();
    return result;
  }

  Future<ConfigBackupResult> exportConfigBackup(String zipPath) async {
    final result = await configBackup.exportToZip(
      zipPath: zipPath,
      servers: _servers,
    );
    _lastMessage = result.message;
    notifyListeners();
    return result;
  }

  Future<ConfigBackupResult> importConfigBackup(String zipPath) async {
    final payload = await configBackup.importFromZip(zipPath);
    if (!payload.result.ok) {
      _lastMessage = payload.result.message;
      notifyListeners();
      return payload.result;
    }

    if (payload.servers != null) {
      await _applyImportedServers(payload.servers!);
      await autoStartEnabledServers();
    }

    await refreshClientStatus();
    _lastMessage = payload.result.message;
    notifyListeners();
    return payload.result;
  }

  Future<void> saveAutoBackupSettings(AutoBackupSettings settings) async {
    await autoConfigBackup.updateSettings(settings);
    _lastMessage = settings.enabled ? '自动备份已启用' : '自动备份已关闭';
    notifyListeners();
  }

  Future<ConfigBackupResult> runAutoBackupNow() async {
    final result = await autoConfigBackup.backupNow();
    _lastMessage = result.message;
    notifyListeners();
    return result;
  }

  Future<ConfigBackupResult> cleanupExpiredAutoBackups() async {
    final result = await autoConfigBackup.cleanupNow();
    _lastMessage = result.message;
    notifyListeners();
    return result;
  }

  /// 用备份清单替换非内置 MCP，并按本机 servers 根目录重写 localPath。
  Future<void> _applyImportedServers(List<McpServerEntry> imported) async {
    final hubIndex = _servers.indexWhere(
      (s) => s.id == HubMcpConstants.serverKey,
    );
    final hub = hubIndex >= 0 ? _servers[hubIndex] : null;
    final root = McpPaths.serversRoot;
    _servers = [
      ?hub,
      for (final s in imported)
        if (!s.builtIn && s.id != HubMcpConstants.serverKey)
          s.copyWith(
            localPath: root == null ? s.localPath : p.join(root, s.id),
          ),
    ];
    await _ensureBuiltInHubMcp(persist: false);
    await _persist();
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
    autoConfigBackup.removeListener(_onAutoConfigBackupChanged);
    hubMcpHost.dispose();
    webDavSync.dispose();
    skillSync.dispose();
    autoConfigBackup.dispose();
    _processManager.stopAll();
    super.dispose();
  }
}
