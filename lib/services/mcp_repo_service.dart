import 'dart:io';

import 'package:path/path.dart' as p;

import 'mcp_paths.dart';

class McpRepoCloneResult {
  const McpRepoCloneResult({
    required this.ok,
    required this.message,
    this.localPath,
  });

  final bool ok;
  final String message;
  final String? localPath;
}

/// Clone MCP source repos into `~/.mcp-hub/servers/<id>`.
class McpRepoService {
  Future<McpRepoCloneResult> clone({
    required String id,
    required String repoUrl,
  }) async {
    final root = McpPaths.serversRoot;
    if (root == null) {
      return const McpRepoCloneResult(
        ok: false,
        message: '当前平台不支持本地仓库管理',
      );
    }

    final target = p.join(root, id);
    final dir = Directory(target);
    if (await dir.exists()) {
      return McpRepoCloneResult(
        ok: true,
        message: '目录已存在，跳过 clone',
        localPath: target,
      );
    }

    await Directory(root).create(recursive: true);
    final result = await Process.run(
      'git',
      ['clone', repoUrl, target],
      runInShell: true,
    );
    if (result.exitCode != 0) {
      final err = (result.stderr as String).trim();
      return McpRepoCloneResult(
        ok: false,
        message: err.isEmpty ? 'git clone 失败 (code ${result.exitCode})' : err,
      );
    }
    return McpRepoCloneResult(
      ok: true,
      message: '已 clone 到 $target',
      localPath: target,
    );
  }
}
