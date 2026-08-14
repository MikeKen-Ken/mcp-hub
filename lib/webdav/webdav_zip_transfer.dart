import 'dart:io' as io;

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

  /// 下载成功返回 true；远端不存在返回 false。
  Future<bool> downloadFile({
    required Client client,
    required String remotePath,
    required String localPath,
  }) async {
    final local = io.File(localPath);
    try {
      await local.parent.create(recursive: true);
      var usable = false;
      try {
        await client.read2File(remotePath, localPath);
        usable = await isUsableLocalFile(localPath);
      } catch (error) {
        if (isRemoteNotFound(error)) return false;
        debugPrint('流式下载落盘失败，改用整包写入: $error');
      }
      if (!usable) {
        final bytes = await client.read(remotePath);
        await local.writeAsBytes(bytes, flush: true);
      }
      await ensureDownloadedFile(localPath);
      return true;
    } catch (error) {
      if (isRemoteNotFound(error)) return false;
      throw StateError('下载远端文件失败：$remotePath → $localPath（$error）');
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

  @visibleForTesting
  static Future<bool> isUsableLocalFile(String localPath) async {
    try {
      await ensureDownloadedFile(localPath);
      return true;
    } catch (_) {
      return false;
    }
  }

  @visibleForTesting
  static Future<void> ensureDownloadedFile(String localPath) async {
    final file = io.File(localPath);
    try {
      final raf = await file.open(mode: io.FileMode.read);
      final length = await raf.length();
      await raf.close();
      if (length <= 0) {
        throw StateError('下载完成但本地文件为空：$localPath');
      }
    } on io.FileSystemException catch (error) {
      throw StateError('下载完成但无法打开本地文件：$localPath（$error）');
    }
  }

  Future<io.File> createTempFile(String prefix, String extension) async {
    return WritableTemp.createFile(prefix, extension);
  }
}
