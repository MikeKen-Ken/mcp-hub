import 'dart:convert';
import 'dart:io';

import '../services/mcp_paths.dart';
import 'catalog_sync_document.dart';

/// Last successfully synced catalog baseline for three-way merge.
class CatalogSyncBaseStore {
  Future<CatalogSyncDocument> load() async {
    final path = McpPaths.syncBasePath;
    if (path == null) return CatalogSyncDocument.empty;
    final file = File(path);
    if (!await file.exists()) return CatalogSyncDocument.empty;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return CatalogSyncDocument.empty;
      return CatalogSyncDocument.fromJson(decoded);
    } catch (_) {
      return CatalogSyncDocument.empty;
    }
  }

  Future<void> save(CatalogSyncDocument doc) async {
    final path = McpPaths.syncBasePath;
    if (path == null) return;
    final file = File(path);
    await file.parent.create(recursive: true);
    final tmp = File('$path.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(doc.toJson()),
      flush: true,
    );
    if (await file.exists()) await file.delete();
    await tmp.rename(path);
  }
}
