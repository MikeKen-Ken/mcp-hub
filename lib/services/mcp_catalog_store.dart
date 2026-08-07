import 'dart:convert';
import 'dart:io';

import '../models/mcp_server_entry.dart';
import 'mcp_paths.dart';

/// Persist the local MCP catalog under `~/.mcp-hub/catalog.json`.
class McpCatalogStore {
  Future<List<McpServerEntry>> load() async {
    final path = McpPaths.catalogPath;
    if (path == null) return const [];
    final file = File(path);
    if (!await file.exists()) return const [];
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) return const [];
    final list = decoded['servers'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((e) => McpServerEntry.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> save(List<McpServerEntry> servers) async {
    final path = McpPaths.catalogPath;
    if (path == null) {
      throw StateError('catalog path unavailable');
    }
    final file = File(path);
    await file.parent.create(recursive: true);
    final payload = {
      'version': 1,
      'servers': servers.map((s) => s.toJson()).toList(),
    };
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
    );
  }
}
