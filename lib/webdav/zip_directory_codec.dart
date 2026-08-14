import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

/// 目录 ↔ zip（条目路径相对根目录，不含外层文件夹名）。
class ZipDirectoryCodec {
  const ZipDirectoryCodec();

  Future<void> packDirectory({
    required String sourceDir,
    required String zipPath,
    bool skipDotEntries = true,
  }) async {
    final archive = Archive();
    final source = Directory(sourceDir);
    if (await source.exists()) {
      await for (final entity in source.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final rel = p.posix.joinAll(
          p.split(p.relative(entity.path, from: source.path)),
        );
        if (skipDotEntries && _hasDotSegment(rel)) continue;
        final data = await entity.readAsBytes();
        archive.addFile(ArchiveFile(rel, data.length, data));
      }
    }
    if (archive.files.isEmpty) {
      archive.addFile(ArchiveFile('.keep', 0, <int>[]));
    }

    final out = File(zipPath);
    await out.parent.create(recursive: true);
    if (await out.exists()) await out.delete();
    final encoded = ZipEncoder().encode(archive);
    await out.writeAsBytes(encoded, flush: true);
  }

  Future<int> extractTo({
    required String zipPath,
    required String targetDir,
    bool wipeTarget = false,
    bool skipDotEntries = true,
  }) async {
    final zipFile = File(zipPath);
    if (!await zipFile.exists()) {
      throw StateError('压缩包不存在：$zipPath');
    }
    final target = Directory(targetDir);
    if (wipeTarget && await target.exists()) {
      await target.delete(recursive: true);
    }
    await target.create(recursive: true);

    final archive = ZipDecoder().decodeBytes(await zipFile.readAsBytes());
    var files = 0;
    for (final entry in archive.files) {
      if (!entry.isFile) continue;
      final rel = entry.name.replaceAll('\\', '/');
      if (rel.contains('..')) continue;
      if (skipDotEntries && _hasDotSegment(rel)) continue;
      final dest = File(p.joinAll([target.path, ...rel.split('/')]));
      await dest.parent.create(recursive: true);
      await dest.writeAsBytes(entry.content, flush: true);
      files += 1;
    }
    return files;
  }

  bool _hasDotSegment(String relativePosixOrOs) {
    final parts = relativePosixOrOs.replaceAll('\\', '/').split('/');
    return parts.any((part) => part.startsWith('.'));
  }

  Future<Uint8List> packJsonEntry({
    required String entryName,
    required List<int> jsonUtf8,
  }) async {
    final archive = Archive()
      ..addFile(ArchiveFile(entryName, jsonUtf8.length, jsonUtf8));
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }
}
