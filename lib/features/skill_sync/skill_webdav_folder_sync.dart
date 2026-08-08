import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:webdav_client/webdav_client.dart';

import '../../webdav/webdav_config.dart';

/// WebDAV 与本地 Skill 文件夹之间的递归同步。
class SkillWebDavFolderSync {
  Client? clientFor(WebDavConfig config) {
    if (!config.isConfigured) return null;
    var url = config.serverUrl.trim();
    if (!url.endsWith('/')) url = '$url/';
    final client = newClient(
      url,
      user: config.username.trim(),
      password: config.password,
      debug: false,
    );
    client.setReceiveTimeout(120000);
    client.setSendTimeout(120000);
    return client;
  }

  /// `{remotePath}/skills/cursor`（远端仅 Cursor；旧 `.../codex` 不再使用）。
  String remoteSkillsDir(WebDavConfig config, String targetWireName) {
    return remoteResourceDir(config, 'skills', targetWireName);
  }

  /// `{remotePath}/{skills|commands|rules}/cursor`
  ///
  /// 权威远端只保留 Cursor 侧目录；历史 `{...}/codex` 可忽略，勿再拉取/上传。
  String remoteResourceDir(
    WebDavConfig config,
    String resourceWireName,
    String targetWireName,
  ) {
    final base = config.remotePath.trim().replaceAll(RegExp(r'/+$'), '');
    final root = base.isEmpty ? WebDavConfig.defaultRemotePath : base;
    return '$root/$resourceWireName/$targetWireName';
  }

  /// 将远端目录镜像到本地（先清空本地目录再下载）。
  Future<int> pullFolder({
    required Client client,
    required String remoteDir,
    required String localDir,
  }) async {
    final local = io.Directory(localDir);
    if (await local.exists()) {
      await local.delete(recursive: true);
    }
    await local.create(recursive: true);

    try {
      await client.mkdirAll(remoteDir);
    } catch (_) {
      // 远端可能已存在
    }

    return _downloadDir(client, remoteDir, localDir);
  }

  /// 将本地目录上传到远端（先确保远端目录存在，覆盖同名文件）。
  Future<int> pushFolder({
    required Client client,
    required String remoteDir,
    required String localDir,
  }) async {
    final local = io.Directory(localDir);
    if (!await local.exists()) {
      await local.create(recursive: true);
    }
    await client.mkdirAll(remoteDir);
    return _uploadDir(client, localDir, remoteDir);
  }

  Future<int> _downloadDir(
    Client client,
    String remoteDir,
    String localDir,
  ) async {
    List<File> entries;
    try {
      entries = await client.readDir(remoteDir);
    } catch (error) {
      final message = error.toString().toLowerCase();
      if (message.contains('404') ||
          message.contains('not found') ||
          message.contains('no such file')) {
        debugPrint('Skill 远端目录不存在，已创建空缓存：$remoteDir');
        return 0;
      }
      rethrow;
    }

    var files = 0;
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
        files += await _downloadDir(client, remotePath, localPath);
      } else {
        await io.File(localPath).parent.create(recursive: true);
        await client.read2File(remotePath, localPath);
        files += 1;
      }
    }
    return files;
  }

  Future<int> _uploadDir(
    Client client,
    String localDir,
    String remoteDir,
  ) async {
    final dir = io.Directory(localDir);
    if (!await dir.exists()) return 0;

    var files = 0;
    await for (final entity in dir.list(followLinks: false)) {
      final name = p.basename(entity.path);
      if (name.startsWith('.')) continue;

      final remotePath = _joinRemote(remoteDir, name);
      if (entity is io.Directory) {
        await client.mkdirAll(remotePath);
        files += await _uploadDir(client, entity.path, remotePath);
      } else if (entity is io.File) {
        await client.writeFromFile(entity.path, remotePath);
        files += 1;
      }
    }
    return files;
  }

  String _joinRemote(String dir, String name) {
    final base = dir.replaceAll(RegExp(r'/+$'), '');
    return '$base/$name';
  }
}
