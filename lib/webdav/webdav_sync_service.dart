import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:webdav_client/webdav_client.dart';

import '../common/sync_progress.dart';
import 'catalog_merge.dart';
import 'catalog_sync_base_store.dart';
import 'catalog_sync_document.dart';
import 'catalog_zip_codec.dart';
import 'webdav_config.dart';
import 'webdav_zip_paths.dart';
import 'webdav_zip_transfer.dart';

enum CatalogSyncStatus { idle, syncing, success, error }

/// 以固定名 `catalog.zip` 覆盖上传/下载 MCP 清单。
class WebDavSyncService extends ChangeNotifier {
  WebDavSyncService({
    required this._loadConfig,
    required this._loadLocalDocument,
    required this._applyDocument,
    CatalogSyncBaseStore? baseStore,
    CatalogZipCodec? catalogZip,
    WebDavZipTransfer? zipTransfer,
  }) : _baseStore = baseStore ?? CatalogSyncBaseStore(),
       _catalogZip = catalogZip ?? CatalogZipCodec(),
       _zipTransfer = zipTransfer ?? WebDavZipTransfer();

  final Future<WebDavConfig> Function() _loadConfig;
  final Future<CatalogSyncDocument> Function() _loadLocalDocument;
  final Future<void> Function(CatalogSyncDocument doc) _applyDocument;
  final CatalogSyncBaseStore _baseStore;
  final CatalogZipCodec _catalogZip;
  final WebDavZipTransfer _zipTransfer;

  CatalogSyncStatus status = CatalogSyncStatus.idle;
  String? lastError;
  DateTime? lastSyncedAt;
  SyncProgress? progress;
  String? lastAction;

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

  Client? _client(WebDavConfig config) => _zipTransfer.clientFor(config);

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
      (_) => unawaited(mergeNow()),
    );
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// 合并远端清单后再覆盖上传压缩包。
  Future<void> syncNow() async {
    await mergeNow();
    await pushNow();
  }

  Future<void> pushNow() async {
    if (_inFlight) return;
    final config = await _loadConfig();
    if (!config.enabled || !config.isConfigured) return;
    final client = _client(config);
    if (client == null) return;

    _inFlight = true;
    lastAction = '上传';
    progress = const SyncProgress(label: '正在打包 MCP 清单', current: 0, total: 2);
    _setStatus(CatalogSyncStatus.syncing);
    try {
      final local = await _loadLocalDocument();
      final doc = CatalogSyncDocument(
        servers: local.servers,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        tombstones: {...local.tombstones, ..._tombstones},
      );
      progress = const SyncProgress(label: '正在上传压缩包', current: 1, total: 2);
      notifyListeners();
      await _writeCatalogZip(client, config, doc);
      await _baseStore.save(doc);
      _tombstones = Map<String, int>.from(doc.tombstones);
      lastSyncedAt = DateTime.now();
      lastError = null;
      progress = const SyncProgress(label: '上传完成', current: 2, total: 2);
      _setStatus(CatalogSyncStatus.success);
    } catch (error) {
      lastError = '$error';
      _setStatus(CatalogSyncStatus.error);
      debugPrint('WebDAV push failed: $error');
    } finally {
      progress = null;
      _inFlight = false;
      notifyListeners();
    }
  }

  /// 用远端压缩包覆盖本机清单（不合并）。
  Future<void> pullNow() async {
    await _pullRemote(merge: false);
  }

  /// 下载压缩包后与本机做三路合并。
  Future<void> mergeNow() async {
    await _pullRemote(merge: true);
  }

  Future<void> _pullRemote({required bool merge}) async {
    if (_inFlight) return;
    final config = await _loadConfig();
    if (!config.enabled || !config.isConfigured) return;
    final client = _client(config);
    if (client == null) return;

    _inFlight = true;
    lastAction = merge ? '合并' : '下载';
    progress = SyncProgress(
      label: merge ? '正在下载并合并 MCP 清单' : '正在下载 MCP 清单',
      current: 0,
      total: 3,
    );
    _setStatus(CatalogSyncStatus.syncing);
    try {
      final remote = await _readRemoteCatalog(client, config);
      if (!merge && remote == null) {
        lastSyncedAt = DateTime.now();
        lastError = null;
        progress = const SyncProgress(label: '远端暂无清单', current: 3, total: 3);
        _setStatus(CatalogSyncStatus.success);
        return;
      }
      final remoteDoc = remote ?? CatalogSyncDocument.empty;
      progress = SyncProgress(
        label: merge ? '正在合并清单' : '正在覆盖本机清单',
        current: 1,
        total: 3,
      );
      notifyListeners();
      final localRaw = await _loadLocalDocument();
      final local = localRaw.copyWith(
        tombstones: {...localRaw.tombstones, ..._tombstones},
      );
      final CatalogSyncDocument next;
      if (merge) {
        final base = await _baseStore.load();
        next = CatalogMerge.merge(local: local, remote: remoteDoc, base: base);
      } else {
        next = remoteDoc;
      }
      progress = const SyncProgress(label: '正在写入本机', current: 2, total: 3);
      notifyListeners();
      await _applyDocument(next);
      _tombstones = Map<String, int>.from(next.tombstones);
      if (merge && !_sameDoc(next, remoteDoc)) {
        await _writeCatalogZip(client, config, next);
      }
      await _baseStore.save(next);
      lastSyncedAt = DateTime.now();
      lastError = null;
      progress = SyncProgress(
        label: merge ? '合并完成' : '下载完成',
        current: 3,
        total: 3,
      );
      _setStatus(CatalogSyncStatus.success);
    } catch (error) {
      lastError = '$error';
      _setStatus(CatalogSyncStatus.error);
      debugPrint('WebDAV pull failed: $error');
    } finally {
      progress = null;
      _inFlight = false;
      notifyListeners();
    }
  }

  bool _sameDoc(CatalogSyncDocument a, CatalogSyncDocument b) {
    return jsonEncode(a.toJson()) == jsonEncode(b.toJson());
  }

  Future<void> _writeCatalogZip(
    Client client,
    WebDavConfig config,
    CatalogSyncDocument doc,
  ) async {
    final tmp = await _zipTransfer.createTempFile('mcp_hub_catalog', '.zip');
    try {
      await _catalogZip.writeDocument(doc: doc, zipPath: tmp.path);
      await _zipTransfer.uploadFile(
        client: client,
        localPath: tmp.path,
        remotePath: WebDavZipPaths.catalogZip(config),
      );
    } finally {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
    }
  }

  Future<CatalogSyncDocument?> _readRemoteCatalog(
    Client client,
    WebDavConfig config,
  ) async {
    final zipPath = WebDavZipPaths.catalogZip(config);
    final tmp = await _zipTransfer.createTempFile('mcp_hub_catalog_dl', '.zip');
    try {
      final ok = await _zipTransfer.downloadFile(
        client: client,
        remotePath: zipPath,
        localPath: tmp.path,
      );
      if (ok) {
        return _catalogZip.readDocument(tmp.path);
      }
    } finally {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
    }

    final legacy = await _readLegacyJson(
      client,
      WebDavZipPaths.legacyCatalogJson(config),
    );
    if (legacy != null) {
      debugPrint('已从旧 catalog.json 读取清单，下次上传将改为 catalog.zip');
    }
    return legacy;
  }

  Future<CatalogSyncDocument?> _readLegacyJson(
    Client client,
    String path,
  ) async {
    try {
      final data = await client.read(path);
      return _decodeCatalogJson(data);
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

  CatalogSyncDocument? _decodeCatalogJson(List<int> data) {
    final decoded = jsonDecode(utf8.decode(data));
    if (decoded is Map<String, dynamic>) {
      return CatalogSyncDocument.fromJson(decoded);
    }
    if (decoded is Map) {
      return CatalogSyncDocument.fromJson(
        decoded.map((k, v) => MapEntry(k.toString(), v)),
      );
    }
    return null;
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
