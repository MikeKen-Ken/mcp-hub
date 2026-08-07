import 'catalog_sync_document.dart';

/// Entry-level three-way merge for MCP catalog sync.
abstract final class CatalogMerge {
  static CatalogSyncDocument merge({
    required CatalogSyncDocument local,
    required CatalogSyncDocument remote,
    required CatalogSyncDocument base,
  }) {
    if (_docsEqual(local, remote)) return local;
    if (_docsEqual(remote, base)) return local;
    if (_docsEqual(local, base)) return remote;

    final localMap = {for (final s in local.servers) s.id: s};
    final remoteMap = {for (final s in remote.servers) s.id: s};
    final baseMap = {for (final s in base.servers) s.id: s};

    final tombstones = <String, int>{
      ...base.tombstones,
      ...local.tombstones,
      ...remote.tombstones,
    };

    final ids = <String>{
      ...localMap.keys,
      ...remoteMap.keys,
      ...baseMap.keys,
    };

    final merged = <SyncableServer>[];
    for (final id in ids) {
      final l = localMap[id];
      final r = remoteMap[id];
      final b = baseMap[id];
      final tombAt = tombstones[id] ?? 0;

      if (l == null && r == null) {
        continue;
      }

      // Deletion wins if tombstone is newer than surviving copy.
      if (l == null && r != null) {
        if (tombAt > r.updatedAt) continue;
        // Local deleted after base, remote unchanged -> keep deletion.
        if (b != null && r.sameContent(b) && tombAt >= b.updatedAt) {
          continue;
        }
        merged.add(r);
        continue;
      }
      if (r == null && l != null) {
        if (tombAt > l.updatedAt) continue;
        if (b != null && l.sameContent(b) && tombAt >= b.updatedAt) {
          continue;
        }
        merged.add(l);
        continue;
      }

      // Both present.
      final left = l!;
      final right = r!;
      if (left.sameContent(right)) {
        merged.add(left.updatedAt >= right.updatedAt ? left : right);
        continue;
      }
      if (b != null && left.sameContent(b)) {
        merged.add(right);
        continue;
      }
      if (b != null && right.sameContent(b)) {
        merged.add(left);
        continue;
      }
      // Same-entry conflict: newer updatedAt wins; device-stable tie-break by id+name hash not needed.
      merged.add(left.updatedAt >= right.updatedAt ? left : right);
    }

    // Drop tombstones for live ids.
    final live = {for (final s in merged) s.id};
    tombstones.removeWhere((id, _) => live.contains(id));

    final updatedAt = [
      local.updatedAt,
      remote.updatedAt,
      ...merged.map((s) => s.updatedAt),
    ].fold<int>(0, (a, b) => a > b ? a : b);

    merged.sort((a, b) => a.id.compareTo(b.id));
    return CatalogSyncDocument(
      servers: merged,
      updatedAt: updatedAt,
      tombstones: tombstones,
    );
  }

  static bool _docsEqual(CatalogSyncDocument a, CatalogSyncDocument b) {
    if (a.servers.length != b.servers.length) return false;
    if (a.tombstones.length != b.tombstones.length) return false;
    final am = {for (final s in a.servers) s.id: s};
    for (final s in b.servers) {
      final other = am[s.id];
      if (other == null || !other.sameContent(s)) return false;
    }
    for (final e in a.tombstones.entries) {
      if (b.tombstones[e.key] != e.value) return false;
    }
    return true;
  }
}
