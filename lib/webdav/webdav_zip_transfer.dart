import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:webdav_client/webdav_client.dart';

import '../common/writable_temp.dart';
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

  /// 下载固定名 zip 的完整字节；远端不存在返回 null。
  Future<Uint8List?> downloadBytes({
    required Client client,
    required String remotePath,
  }) async {
    try {
      final bytes = await client.read(remotePath);
      if (bytes.isEmpty) {
        throw StateError('远端压缩包为空：$remotePath');
      }
      return Uint8List.fromList(bytes);
    } catch (error) {
      if (isRemoteNotFound(error)) return null;
      throw StateError('下载远端压缩包失败：$remotePath（$error）');
    }
  }

  /// HTTP/WebDAV 的远端缺失；本机 [FileSystemException] 不算远端 404。
  @visibleForTesting
  static bool isRemoteNotFound(Object error) {
    if (error is io.FileSystemException) return false;
    final message = error.toString().toLowerCase();
    if (message.contains('pathnotfoundexception')) return false;
    if (message.contains('cannot open file')) return false;
    if (message.contains('cannot create file')) return false;
    if (message.contains('cannot delete file')) return false;
    if (RegExp(r'\b404\b').hasMatch(message)) return true;
    if (message.contains('not found')) return true;
    if (message.contains('no such file')) return true;
    return false;
  }

  Future<io.File> createTempFile(String prefix, String extension) async {
    return WritableTemp.createFile(prefix, extension);
  }
}
