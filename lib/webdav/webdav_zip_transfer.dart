import 'dart:io' as io;

import 'package:webdav_client/webdav_client.dart';

import 'webdav_config.dart';

/// 把单个本地文件覆盖上传 / 下载到 WebDAV（用于固定名 zip）。
class WebDavZipTransfer {
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

  Future<void> ensureParentDir(Client client, String path) async {
    final idx = path.lastIndexOf('/');
    if (idx <= 0) return;
    final dir = path.substring(0, idx);
    if (dir.isEmpty || dir == '/') return;
    try {
      await client.mkdirAll(dir);
    } catch (_) {
      // 目录可能已存在
    }
  }

  Future<void> uploadFile({
    required Client client,
    required String localPath,
    required String remotePath,
  }) async {
    await ensureParentDir(client, remotePath);
    await client.writeFromFile(localPath, remotePath);
  }

  /// 下载成功返回 true；远端不存在返回 false。
  Future<bool> downloadFile({
    required Client client,
    required String remotePath,
    required String localPath,
  }) async {
    try {
      await io.File(localPath).parent.create(recursive: true);
      await client.read2File(remotePath, localPath);
      return true;
    } catch (error) {
      if (_isNotFound(error)) return false;
      rethrow;
    }
  }

  bool _isNotFound(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('404') ||
        message.contains('not found') ||
        message.contains('no such file');
  }

  Future<io.File> createTempFile(String prefix, String extension) async {
    final file = io.File(
      '${io.Directory.systemTemp.path}${io.Platform.pathSeparator}'
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}$extension',
    );
    return file;
  }
}
