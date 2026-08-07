import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_hub/webdav/catalog_merge.dart';
import 'package:mcp_hub/webdav/catalog_sync_document.dart';

SyncableServer server(String id, {int updatedAt = 1, String? name}) {
  return SyncableServer(
    id: id,
    name: name ?? id,
    transport: 'stdio',
    updatedAt: updatedAt,
    command: 'npx',
  );
}

void main() {
  test('remote-only addition is kept', () {
    final base = CatalogSyncDocument(servers: [server('a')], updatedAt: 1);
    final local = base;
    final remote = CatalogSyncDocument(
      servers: [server('a'), server('b', updatedAt: 2)],
      updatedAt: 2,
    );
    final merged = CatalogMerge.merge(local: local, remote: remote, base: base);
    expect(merged.servers.map((s) => s.id), ['a', 'b']);
  });

  test('local-only addition is kept', () {
    final base = CatalogSyncDocument(servers: [server('a')], updatedAt: 1);
    final remote = base;
    final local = CatalogSyncDocument(
      servers: [server('a'), server('c', updatedAt: 3)],
      updatedAt: 3,
    );
    final merged = CatalogMerge.merge(local: local, remote: remote, base: base);
    expect(merged.servers.map((s) => s.id), ['a', 'c']);
  });

  test('same id conflict prefers newer updatedAt', () {
    final base = CatalogSyncDocument(
      servers: [server('a', name: 'old', updatedAt: 1)],
      updatedAt: 1,
    );
    final local = CatalogSyncDocument(
      servers: [server('a', name: 'local', updatedAt: 5)],
      updatedAt: 5,
    );
    final remote = CatalogSyncDocument(
      servers: [server('a', name: 'remote', updatedAt: 4)],
      updatedAt: 4,
    );
    final merged = CatalogMerge.merge(local: local, remote: remote, base: base);
    expect(merged.servers.single.name, 'local');
  });

  test('tombstone deletes when newer than entry', () {
    final base = CatalogSyncDocument(
      servers: [server('a', updatedAt: 1)],
      updatedAt: 1,
    );
    final local = CatalogSyncDocument(
      servers: const [],
      updatedAt: 3,
      tombstones: const {'a': 3},
    );
    final remote = CatalogSyncDocument(
      servers: [server('a', updatedAt: 1)],
      updatedAt: 1,
    );
    final merged = CatalogMerge.merge(local: local, remote: remote, base: base);
    expect(merged.servers, isEmpty);
    expect(merged.tombstones['a'], 3);
  });
}
