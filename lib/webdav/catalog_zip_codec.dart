import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'catalog_sync_document.dart';
import 'webdav_zip_paths.dart';
import 'zip_directory_codec.dart';

/// MCP 清单 ↔ 固定名 `catalog.zip`（包内仅 `catalog.json`）。
class CatalogZipCodec {
  CatalogZipCodec({ZipDirectoryCodec? zipCodec})
    : _zipCodec = zipCodec ?? const ZipDirectoryCodec();

  final ZipDirectoryCodec _zipCodec;

  Future<void> writeDocument({
    required CatalogSyncDocument doc,
    required String zipPath,
  }) async {
    final jsonUtf8 = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(doc.toJson()),
    );
    final bytes = await _zipCodec.packJsonEntry(
      entryName: WebDavZipPaths.catalogEntryName,
      jsonUtf8: jsonUtf8,
    );
    final out = File(zipPath);
    await out.parent.create(recursive: true);
    await out.writeAsBytes(bytes, flush: true);
  }

  Future<CatalogSyncDocument> readDocument(String zipPath) async {
    final bytes = await File(zipPath).readAsBytes();
    return decodeBytes(bytes);
  }

  CatalogSyncDocument decodeBytes(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    ArchiveFile? entry;
    for (final file in archive.files) {
      if (!file.isFile) continue;
      final name = file.name.replaceAll('\\', '/');
      if (name == WebDavZipPaths.catalogEntryName ||
          name.endsWith('/${WebDavZipPaths.catalogEntryName}')) {
        entry = file;
        break;
      }
    }
    if (entry == null) {
      throw FormatException(
        'Archive is missing ${WebDavZipPaths.catalogEntryName}',
      );
    }
    final decoded = jsonDecode(utf8.decode(entry.content as List<int>));
    if (decoded is Map<String, dynamic>) {
      return CatalogSyncDocument.fromJson(decoded);
    }
    if (decoded is Map) {
      return CatalogSyncDocument.fromJson(
        decoded.map((k, v) => MapEntry(k.toString(), v)),
      );
    }
    throw FormatException('catalog.json is not an object');
  }
}
