import 'package:path/path.dart' as p;

import '../models/mcp_server_entry.dart';
import '../models/mcp_transport.dart';
import '../services/hub_mcp_constants.dart';
import '../services/mcp_paths.dart';
import 'catalog_sync_document.dart';

/// Convert between local catalog entries and syncable documents.
abstract final class CatalogSyncMapper {
  static CatalogSyncDocument toDocument(
    List<McpServerEntry> servers, {
    Map<String, int> tombstones = const {},
  }) {
    final syncable = [
      for (final s in servers)
        if (!s.builtIn && s.id != HubMcpConstants.serverKey) toSyncable(s),
    ]..sort((a, b) => a.id.compareTo(b.id));

    final updatedAt = [
      0,
      ...syncable.map((s) => s.updatedAt),
      ...tombstones.values,
    ].fold<int>(0, (a, b) => a > b ? a : b);

    return CatalogSyncDocument(
      servers: syncable,
      updatedAt: updatedAt,
      tombstones: tombstones,
    );
  }

  static SyncableServer toSyncable(McpServerEntry s) {
    return SyncableServer(
      id: s.id,
      name: s.name,
      transport: s.transport.wireName,
      updatedAt: s.updatedAt,
      repoUrl: s.repoUrl,
      command: s.command,
      args: s.args,
      url: s.url,
      notes: s.notes,
    );
  }

  /// Apply a sync document onto local entries, preserving machine-local fields.
  static List<McpServerEntry> applyDocument({
    required List<McpServerEntry> local,
    required CatalogSyncDocument doc,
  }) {
    final byId = {for (final s in local) s.id: s};
    final result = <McpServerEntry>[];

    // Keep built-in hubMCP first if present.
    final hub = byId[HubMcpConstants.serverKey];
    if (hub != null) result.add(hub);

    for (final sync in doc.servers) {
      if (sync.id == HubMcpConstants.serverKey) continue;
      final existing = byId[sync.id];
      result.add(
        fromSyncable(
          sync,
          existing: existing,
        ),
      );
    }

    // Keep purely local non-synced extras? Deletions in doc remove them.
    // Local-only built-ins already handled.
    return result;
  }

  static McpServerEntry fromSyncable(
    SyncableServer sync, {
    McpServerEntry? existing,
  }) {
    final root = McpPaths.serversRoot;
    final localPath = existing?.localPath ??
        (root == null ? null : p.join(root, sync.id));
    return McpServerEntry(
      id: sync.id,
      name: sync.name,
      transport: McpTransportCodec.parse(sync.transport),
      repoUrl: sync.repoUrl,
      localPath: localPath,
      command: sync.command,
      args: sync.args,
      env: existing?.env ?? const {},
      cwd: existing?.cwd,
      url: sync.url,
      // 开/关仅本机：拉取时保留本地状态；新条目默认关闭
      enabled: existing?.enabled ?? false,
      autoStart: existing?.autoStart ?? false,
      builtIn: false,
      notes: sync.notes,
      updatedAt: sync.updatedAt,
    );
  }
}
