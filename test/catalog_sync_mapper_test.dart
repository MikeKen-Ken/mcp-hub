import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_hub/models/mcp_server_entry.dart';
import 'package:mcp_hub/models/mcp_transport.dart';
import 'package:mcp_hub/webdav/catalog_sync_document.dart';
import 'package:mcp_hub/webdav/catalog_sync_mapper.dart';

void main() {
  test('toSyncable 不含 enabled', () {
    final entry = McpServerEntry(
      id: 'demo',
      name: 'Demo',
      transport: McpTransport.stdio,
      command: 'npx',
      enabled: true,
      updatedAt: 10,
    );
    final sync = CatalogSyncMapper.toSyncable(entry);
    expect(sync.toJson().containsKey('enabled'), isFalse);
  });

  test('applyDocument 保留本机 enabled / env / cwd', () {
    final local = [
      const McpServerEntry(
        id: 'hubMCP',
        name: 'MCP Hub',
        transport: McpTransport.http,
        url: 'http://127.0.0.1:18766/mcp',
        enabled: true,
        builtIn: true,
      ),
      const McpServerEntry(
        id: 'demo',
        name: 'Demo',
        transport: McpTransport.stdio,
        command: 'old',
        env: {'K': 'v'},
        cwd: r'C:\local',
        enabled: true,
        updatedAt: 1,
      ),
    ];
    final doc = CatalogSyncDocument(
      servers: [
        const SyncableServer(
          id: 'demo',
          name: 'Demo',
          transport: 'stdio',
          updatedAt: 2,
          command: 'new',
        ),
      ],
      updatedAt: 2,
    );
    final applied = CatalogSyncMapper.applyDocument(local: local, doc: doc);
    final demo = applied.firstWhere((s) => s.id == 'demo');
    expect(demo.command, 'new');
    expect(demo.enabled, isTrue);
    expect(demo.env, {'K': 'v'});
    expect(demo.cwd, r'C:\local');
  });

  test('远端新条目默认 enabled=false', () {
    final applied = CatalogSyncMapper.applyDocument(
      local: const [],
      doc: CatalogSyncDocument(
        servers: [
          const SyncableServer(
            id: 'fresh',
            name: 'Fresh',
            transport: 'http',
            updatedAt: 1,
            url: 'http://127.0.0.1:9/mcp',
          ),
        ],
        updatedAt: 1,
      ),
    );
    expect(applied.single.enabled, isFalse);
  });
}
