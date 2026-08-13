import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:webdav_client/webdav_client.dart';

import '../../webdav/webdav_config.dart';

/// WebDAV 与本地 Skill 文件夹之间的递归下载/上传。
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
  /// 权威远端只保留 Cursor 侧目录；历史 `{...}/codex` 可忽略，勿再下载/上传。
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
    void Function(int done, int total)? onProgress,
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

    return _downloadDir(client, remoteDir, localDir, onProgress: onProgress);
  }

  /// 将本地目录全量镜像到远端（覆盖同名，并删除远端多余项）。
  Future<int> pushFolder({
    required Client client,
    required String remoteDir,
    required String localDir,
    void Function(int done, int total)? onProgress,
  }) async {
    final local = io.Directory(localDir);
    if (!await local.exists()) {
      await local.create(recursive: true);
    }
    await client.mkdirAll(remoteDir);
    final uploaded = await _uploadDir(
      client,
      localDir,
      remoteDir,
      onProgress: onProgress,
    );
    await _deleteRemoteExtras(client, localDir, remoteDir);
    return uploaded;
  }

  /// 删除远端有、本地没有的条目，使远端与本地目录一致。
  Future<void> _deleteRemoteExtras(
    Client client,
    String localDir,
    String remoteDir,
  ) async {
    List<File> entries;
    try {
      entries = await client.readDir(remoteDir);
    } catch (error) {
      final message = error.toString().toLowerCase();
      if (message.contains('404') ||
          message.contains('not found') ||
          message.contains('no such file')) {
        return;
      }
      rethrow;
    }

    final localNames = <String>{};
    final local = io.Directory(localDir);
    if (await local.exists()) {
      await for (final entity in local.list(followLinks: false)) {
        final name = p.basename(entity.path);
        if (name.startsWith('.')) continue;
        localNames.add(name);
      }
    }

    for (final entry in entries) {
      final name = entry.name;
      if (name == null || name.isEmpty || name == '.' || name == '..') {
        continue;
      }
      if (name.startsWith('.')) continue;

      final remotePath = entry.path ?? _joinRemote(remoteDir, name);
      if (!localNames.contains(name)) {
        try {
          // 部分 WebDAV 服务删除目录要求路径以 / 结尾。
          final path = entry.isDir == true && !remotePath.endsWith('/')
              ? '$remotePath/'
              : remotePath;
          await client.remove(path);
          debugPrint('已删除远端多余项：$path');
        } catch (error) {
          debugPrint('删除远端多余项失败 $remotePath: $error');
          rethrow;
        }
        continue;
      }

      if (entry.isDir == true) {
        await _deleteRemoteExtras(client, p.join(localDir, name), remotePath);
      }
    }
  }

  Future<int> _downloadDir(
    Client client,
    String remoteDir,
    String localDir, {
    void Function(int done, int total)? onProgress,
  }) async {
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

  Future<int> _uploadDir(
    Client client,
    String localDir,
    String remoteDir, {
    void Function(int done, int total)? onProgress,
  }) async {
    final files = <({String local, String remote})>[];
    await _collectLocalFiles(localDir, remoteDir, files);
    onProgress?.call(0, files.length);
    var done = 0;
    for (final file in files) {
      final parent = p.dirname(file.remote).replaceAll(r'\', '/');
      if (parent.isNotEmpty && parent != '.' && parent != '/') {
        await client.mkdirAll(parent);
      }
      await client.writeFromFile(file.local, file.remote);
      done += 1;
      onProgress?.call(done, files.length);
    }
    return files.length;
  }

  Future<void> _collectLocalFiles(
    String localDir,
    String remoteDir,
    List<({String local, String remote})> files,
  ) async {
    final dir = io.Directory(localDir);
    if (!await dir.exists()) return;
    await for (final entity in dir.list(followLinks: false)) {
      final name = p.basename(entity.path);
      if (name.startsWith('.')) continue;
      final remotePath = _joinRemote(remoteDir, name);
      if (entity is io.Directory) {
        await _collectLocalFiles(entity.path, remotePath, files);
      } else if (entity is io.File) {
        files.add((local: entity.path, remote: remotePath));
      }
    }
  }

  String _joinRemote(String dir, String name) {
    final base = dir.replaceAll(RegExp(r'/+$'), '');
    return '$base/$name';
  }
}
