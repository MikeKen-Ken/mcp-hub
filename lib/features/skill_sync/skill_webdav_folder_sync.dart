import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:webdav_client/webdav_client.dart';

import '../../webdav/webdav_config.dart';
import '../../webdav/webdav_zip_paths.dart';
import '../../webdav/webdav_zip_transfer.dart';
import '../../webdav/zip_directory_codec.dart';
import 'skill_folder_copy.dart';

/// WebDAV 与本地 Skill 文件夹之间的压缩包下载/上传/合并。
class SkillWebDavFolderSync {
  SkillWebDavFolderSync({
    WebDavZipTransfer? zipTransfer,
    ZipDirectoryCodec? zipCodec,
    SkillFolderCopy? folderCopy,
  }) : _zipTransfer = zipTransfer ?? WebDavZipTransfer(),
       _zipCodec = zipCodec ?? const ZipDirectoryCodec(),
       _folderCopy = folderCopy ?? const SkillFolderCopy();

  final WebDavZipTransfer _zipTransfer;
  final ZipDirectoryCodec _zipCodec;
  final SkillFolderCopy _folderCopy;

  Client? clientFor(WebDavConfig config) => _zipTransfer.clientFor(config);

  /// `{remotePath}/skills/cursor`（旧目录树，仅下载回退）。
  String remoteSkillsDir(WebDavConfig config, String targetWireName) {
    return remoteResourceDir(config, 'skills', targetWireName);
  }

  /// `{remotePath}/{skills|commands|rules}/cursor`
  String remoteResourceDir(
    WebDavConfig config,
    String resourceWireName,
    String targetWireName,
  ) {
    return '${WebDavZipPaths.remoteRoot(config)}/$resourceWireName/$targetWireName';
  }

  String remoteResourceZip(WebDavConfig config, String resourceWireName) {
    return WebDavZipPaths.resourceZip(config, resourceWireName);
  }

  /// 将远端压缩包镜像到本地（先清空本地目录再解压）。
  Future<int> pullFolder({
    required Client client,
    required WebDavConfig config,
    required String resourceWireName,
    required String targetWireName,
    required String localDir,
    void Function(int done, int total)? onProgress,
  }) async {
    onProgress?.call(0, 1);
    final zipRemote = remoteResourceZip(config, resourceWireName);
    final extracted = await _downloadZipToDir(
      client: client,
      remoteZip: zipRemote,
      localDir: localDir,
      wipeTarget: true,
    );
    if (extracted != null) {
      onProgress?.call(1, 1);
      return extracted;
    }

    debugPrint('未找到 $zipRemote，回退旧目录树下载');
    return _pullLegacyTree(
      client: client,
      remoteDir: remoteResourceDir(config, resourceWireName, targetWireName),
      localDir: localDir,
      onProgress: onProgress,
    );
  }

  /// 下载压缩包后合并复制到本地（覆盖同名，不删除本地多余项）。
  Future<int> mergeFolder({
    required Client client,
    required WebDavConfig config,
    required String resourceWireName,
    required String targetWireName,
    required String localDir,
    void Function(int done, int total)? onProgress,
  }) async {
    onProgress?.call(0, 1);
    final staging = await io.Directory.systemTemp.createTemp(
      'mcp_hub_merge_${resourceWireName}_',
    );
    try {
      final zipRemote = remoteResourceZip(config, resourceWireName);
      final extracted = await _downloadZipToDir(
        client: client,
        remoteZip: zipRemote,
        localDir: staging.path,
        wipeTarget: true,
      );
      if (extracted == null) {
        debugPrint('未找到 $zipRemote，回退旧目录树合并');
        await _pullLegacyTree(
          client: client,
          remoteDir: remoteResourceDir(
            config,
            resourceWireName,
            targetWireName,
          ),
          localDir: staging.path,
          onProgress: onProgress,
        );
      }
      await io.Directory(localDir).create(recursive: true);
      if (!await staging.exists()) {
        onProgress?.call(1, 1);
        return 0;
      }
      final copied = await _folderCopy.copyContents(
        sourceDir: staging.path,
        targetDir: localDir,
      );
      onProgress?.call(1, 1);
      return copied.copiedFiles;
    } finally {
      try {
        if (await staging.exists()) await staging.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// 将本地目录打成固定名 zip 覆盖上传。
  Future<int> pushFolder({
    required Client client,
    required WebDavConfig config,
    required String resourceWireName,
    required String localDir,
    void Function(int done, int total)? onProgress,
  }) async {
    onProgress?.call(0, 2);
    final local = io.Directory(localDir);
    if (!await local.exists()) {
      await local.create(recursive: true);
    }
    final zipFile = await _zipTransfer.createTempFile(
      'mcp_hub_$resourceWireName',
      '.zip',
    );
    try {
      await _zipCodec.packDirectory(
        sourceDir: localDir,
        zipPath: zipFile.path,
      );
      onProgress?.call(1, 2);
      await _zipTransfer.uploadFile(
        client: client,
        localPath: zipFile.path,
        remotePath: remoteResourceZip(config, resourceWireName),
      );
      onProgress?.call(2, 2);
      return await _countPackedFiles(localDir);
    } finally {
      try {
        if (await zipFile.exists()) await zipFile.delete();
      } catch (_) {}
    }
  }

  Future<int?> _downloadZipToDir({
    required Client client,
    required String remoteZip,
    required String localDir,
    required bool wipeTarget,
  }) async {
    final zipFile = await _zipTransfer.createTempFile('mcp_hub_dl', '.zip');
    try {
      final ok = await _zipTransfer.downloadFile(
        client: client,
        remotePath: remoteZip,
        localPath: zipFile.path,
      );
      if (!ok) return null;
      return _zipCodec.extractTo(
        zipPath: zipFile.path,
        targetDir: localDir,
        wipeTarget: wipeTarget,
      );
    } finally {
      try {
        if (await zipFile.exists()) await zipFile.delete();
      } catch (_) {}
    }
  }

  Future<int> _countPackedFiles(String localDir) async {
    final dir = io.Directory(localDir);
    if (!await dir.exists()) return 0;
    var count = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! io.File) continue;
      if (p.basename(entity.path).startsWith('.')) continue;
      count += 1;
    }
    return count;
  }

  /// 旧 `{remote}/{resource}/cursor` 目录树，仅当压缩包不存在时使用。
  Future<int> _pullLegacyTree({
    required Client client,
    required String remoteDir,
    required String localDir,
    void Function(int done, int total)? onProgress,
  }) async {
    final local = io.Directory(localDir);
    if (await local.exists()) {
      await local.delete(recursive: true);
    }
    await local.create(recursive: true);

    final files = <({String remote, String local})>[];
    try {
      await _collectRemoteFiles(client, remoteDir, localDir, files);
    } catch (error) {
      final message = error.toString().toLowerCase();
      if (message.contains('404') ||
          message.contains('not found') ||
          message.contains('no such file')) {
        debugPrint('Skill 远端目录不存在，已创建空缓存：$remoteDir');
        onProgress?.call(0, 0);
        return 0;
      }
      rethrow;
    }

    onProgress?.call(0, files.length);
    var done = 0;
    for (final file in files) {
      await io.File(file.local).parent.create(recursive: true);
      await client.read2File(file.remote, file.local);
      done += 1;
      onProgress?.call(done, files.length);
    }
    return files.length;
  }

  Future<void> _collectRemoteFiles(
    Client client,
    String remoteDir,
    String localDir,
    List<({String remote, String local})> files,
  ) async {
    final entries = await client.readDir(remoteDir);
    for (final entry in entries) {
      final name = entry.name;
      if (name == null || name.isEmpty || name == '.' || name == '..') {
        continue;
      }
      if (name.startsWith('.')) continue;

      final remotePath = entry.path ?? _joinRemote(remoteDir, name);
      final localPath = p.join(localDir, name);

      if (entry.isDir == true) {
        await io.Directory(localPath).create(recursive: true);
        await _collectRemoteFiles(client, remotePath, localPath, files);
      } else {
        files.add((remote: remotePath, local: localPath));
      }
    }
  }

  String _joinRemote(String dir, String name) {
    final base = dir.replaceAll(RegExp(r'/+$'), '');
    return '$base/$name';
  }
}
