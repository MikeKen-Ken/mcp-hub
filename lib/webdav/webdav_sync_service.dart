import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:webdav_client/webdav_client.dart';

import 'catalog_merge.dart';
import 'catalog_sync_base_store.dart';
import 'catalog_sync_document.dart';
import 'webdav_config.dart';

enum CatalogSyncStatus { idle, syncing, success, error }

/// Lightweight WebDAV sync for a single MCP catalog file.
class WebDavSyncService extends ChangeNotifier {
  WebDavSyncService({
    required this._loadConfig,
    required this._loadLocalDocument,
    required this._applyDocument,
    CatalogSyncBaseStore? baseStore,
  }) : _baseStore = baseStore ?? CatalogSyncBaseStore();

  final Future<WebDavConfig> Function() _loadConfig;
  final Future<CatalogSyncDocument> Function() _loadLocalDocument;
  final Future<void> Function(CatalogSyncDocument doc) _applyDocument;
  final CatalogSyncBaseStore _baseStore;

  CatalogSyncStatus status = CatalogSyncStatus.idle;
  String? lastError;
  DateTime? lastSyncedAt;

  Timer? _debounceTimer;
  Timer? _pollTimer;
  bool _inFlight = false;
  Map<String, int> _tombstones = {};

  Map<String, int> get tombstones => Map.unmodifiable(_tombstones);

  void setTombstones(Map<String, int> value) {
    _tombstones = Map<String, int>.from(value);
  }

  void rememberTombstone(String id) {
    _tombstones[id] = DateTime.now().millisecondsSinceEpoch;
  }

  Client? _client(WebDavConfig config) {
    if (!config.isConfigured) return null;
    var url = config.serverUrl.trim();
    if (!url.endsWith('/')) url = '$url/';
    final client = newClient(
      url,
      user: config.username.trim(),
      password: config.password,
      debug: false,
    );
    client.setReceiveTimeout(60000);
    client.setSendTimeout(60000);
    return client;
  }

  String _catalogPath(WebDavConfig config) {
    final base = config.remotePath.trim().replaceAll(RegExp(r'/+$'), '');
    final root = base.isEmpty ? WebDavConfig.defaultRemotePath : base;
    return '$root/catalog.json';
  }

  Future<bool> testConnection([WebDavConfig? override]) async {
    final config = override ?? await _loadConfig();
    final client = _client(config);
    if (client == null) return false;
    try {
      await client.ping();
      return true;
    } catch (error) {
      debugPrint('WebDAV ping failed: $error');
      return false;
    }
  }

  void schedulePush() {
    unawaited(() async {
      final config = await _loadConfig();
      if (!config.enabled || !config.autoSync || !config.isConfigured) return;
      _debounceTimer?.cancel();
      _debounceTimer = Timer(
        Duration(seconds: config.pushDebounceSeconds),
        () => unawaited(pushNow()),
      );
    }());
  }

  Future<void> startPolling() async {
    _pollTimer?.cancel();
    final config = await _loadConfig();
    if (!config.enabled || !config.autoPull || !config.isConfigured) return;
    _pollTimer = Timer.periodic(
      Duration(seconds: config.pollIntervalSeconds),
      (_) => unawaited(pullNow()),
    );
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> syncNow() async {
    await pullNow();
    await pushNow();
  }

  Future<void> pushNow() async {
    if (_inFlight) return;
    final config = await _loadConfig();
    if (!config.enabled || !config.isConfigured) return;
    final client = _client(config);
    if (client == null) return;

    _inFlight = true;
    _setStatus(CatalogSyncStatus.syncing);
    try {
      final local = await _loadLocalDocument();
      final doc = CatalogSyncDocument(
        servers: local.servers,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        tombstones: {
          ...local.tombstones,
          ..._tombstones,
        },
      );
      final path = _catalogPath(config);
      await _ensureParentDir(client, path);
      await _writeJson(client, path, doc.toJson());
      await _baseStore.save(doc);
      _tombstones = Map<String, int>.from(doc.tombstones);
      lastSyncedAt = DateTime.now();
      lastError = null;
      _setStatus(CatalogSyncStatus.success);
    } catch (error) {
      lastError = '$error';
      _setStatus(CatalogSyncStatus.error);
      debugPrint('WebDAV push failed: $error');
    } finally {
      _inFlight = false;
    }
  }

  Future<void> pullNow() async {
    if (_inFlight) return;
    final config = await _loadConfig();
    if (!config.enabled || !config.isConfigured) return;
    final client = _client(config);
    if (client == null) return;

    _inFlight = true;
    _setStatus(CatalogSyncStatus.syncing);
    try {
      final path = _catalogPath(config);
      final remoteJson = await _readJson(client, path);
      final remote = remoteJson == null
          ? CatalogSyncDocument.empty
          : CatalogSyncDocument.fromJson(remoteJson);
      final localRaw = await _loadLocalDocument();
      final local = localRaw.copyWith(
        tombstones: {...localRaw.tombstones, ..._tombstones},
      );
      final base = await _baseStore.load();
      final merged = CatalogMerge.merge(
        local: local,
        remote: remote,
        base: base,
      );
      await _applyDocument(merged);
      _tombstones = Map<String, int>.from(merged.tombstones);
      // If merge differs from remote, push back.
      if (!_sameDoc(merged, remote)) {
        await _writeJson(client, path, merged.toJson());
      }
      await _baseStore.save(merged);
      lastSyncedAt = DateTime.now();
      lastError = null;
      _setStatus(CatalogSyncStatus.success);
    } catch (error) {
      lastError = '$error';
      _setStatus(CatalogSyncStatus.error);
      debugPrint('WebDAV pull failed: $error');
    } finally {
      _inFlight = false;
    }
  }

  bool _sameDoc(CatalogSyncDocument a, CatalogSyncDocument b) {
    return jsonEncode(a.toJson()) == jsonEncode(b.toJson());
  }

  Future<void> _ensureParentDir(Client client, String path) async {
    final idx = path.lastIndexOf('/');
    if (idx <= 0) return;
    final dir = path.substring(0, idx);
    if (dir.isEmpty || dir == '/') return;
    try {
      await client.mkdirAll(dir);
    } catch (_) {
      // directory may already exist
    }
  }

  Future<void> _writeJson(
    Client client,
    String path,
    Object data,
  ) async {
    final bytes = Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(data)),
    );
    final tmp = io.File(
      '${io.Directory.systemTemp.path}${io.Platform.pathSeparator}'
      'mcp_hub_webdav_${DateTime.now().microsecondsSinceEpoch}.json',
    );
    try {
      await tmp.writeAsBytes(bytes, flush: true);
      await client.writeFromFile(tmp.path, path);
    } finally {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
    }
  }

  Future<Map<String, dynamic>?> _readJson(Client client, String path) async {
    try {
      final data = await client.read(path);
      final decoded = jsonDecode(utf8.decode(data));
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
      return null;
    } catch (error) {
      final message = error.toString().toLowerCase();
      if (message.contains('404') ||
          message.contains('not found') ||
          message.contains('no such file')) {
        return null;
      }
      rethrow;
    }
  }

  void _setStatus(CatalogSyncStatus value) {
    status = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    stopPolling();
    super.dispose();
  }
}
