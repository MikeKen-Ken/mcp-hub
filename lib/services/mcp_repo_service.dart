import 'dart:io';

import 'package:path/path.dart' as p;

import 'mcp_paths.dart';
import 'mcp_repo_post_pull.dart';

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
        message:
            'Local repository management is not supported on this platform',
      );
    }

    final target = p.join(root, id);
    final dir = Directory(target);
    if (await dir.exists()) {
      return McpRepoCloneResult(
        ok: true,
        message: 'Directory already exists; clone skipped',
        localPath: target,
      );
    }

    await Directory(root).create(recursive: true);
    final result = await Process.run('git', [
      'clone',
      repoUrl,
      target,
    ], runInShell: true);
    if (result.exitCode != 0) {
      final err = (result.stderr as String).trim();
      return McpRepoCloneResult(
        ok: false,
        message: err.isEmpty
            ? 'git clone failed (code ${result.exitCode})'
            : err,
      );
    }
    return McpRepoCloneResult(
      ok: true,
      message: 'Cloned to $target',
      localPath: target,
    );
  }

  /// 是否为 Hub `servers` 目录下的 Git 检出（可安全 pull / 删除）。
  Future<bool> isHubGitCheckout(String? localPath) async {
    if (localPath == null || localPath.trim().isEmpty) return false;
    if (!_isUnderServersRoot(localPath)) return false;
    return await Directory(p.join(localPath, '.git')).exists();
  }

  bool _isUnderServersRoot(String localPath) {
    final root = McpPaths.serversRoot;
    if (root == null) return false;
    final normalizedRoot = p.normalize(root);
    final normalizedPath = p.normalize(localPath);
    final relative = p.relative(normalizedPath, from: normalizedRoot);
    if (relative == '.' ||
        relative.startsWith('..') ||
        p.isAbsolute(relative)) {
      return false;
    }
    return true;
  }

  /// `git pull --ff-only` in an existing checkout.
  Future<McpRepoCloneResult> pull({required String localPath}) async {
    final dir = Directory(localPath);
    if (!await dir.exists()) {
      return McpRepoCloneResult(
        ok: false,
        message: 'Local directory does not exist: $localPath',
      );
    }
    if (!await isHubGitCheckout(localPath)) {
      return McpRepoCloneResult(
        ok: false,
        localPath: localPath,
        message:
            'This is not a Hub-managed Git repository; it cannot be updated',
      );
    }
    final result = await Process.run(
      'git',
      ['pull', '--ff-only'],
      workingDirectory: localPath,
      runInShell: true,
    );
    if (result.exitCode != 0) {
      final err = (result.stderr as String).trim();
      final out = (result.stdout as String).trim();
      final detail = err.isNotEmpty ? err : out;
      return McpRepoCloneResult(
        ok: false,
        localPath: localPath,
        message: detail.isEmpty
            ? 'git pull failed (code ${result.exitCode})'
            : 'git pull failed: $detail',
      );
    }
    final out = (result.stdout as String).trim();
    if (out.isEmpty ||
        out.contains('Already up to date') ||
        out.contains('Already up-to-date')) {
      return McpRepoCloneResult(
        ok: true,
        localPath: localPath,
        message: 'Already up to date',
      );
    }
    return McpRepoCloneResult(
      ok: true,
      localPath: localPath,
      message: 'Updated; $out',
    );
  }

  /// `git pull` 后按项目类型执行 npm 构建 / uv sync 等。
  Future<McpRepoCloneResult> updateCheckout({required String localPath}) async {
    final pullResult = await pull(localPath: localPath);
    if (!pullResult.ok) return pullResult;

    final postPull = await McpRepoPostPull.apply(localPath: localPath);
    if (!postPull.ok) {
      return McpRepoCloneResult(
        ok: false,
        localPath: localPath,
        message: _joinMessages([pullResult.message, postPull.message]),
      );
    }

    return McpRepoCloneResult(
      ok: true,
      localPath: localPath,
      message: _joinMessages([pullResult.message, postPull.message]),
    );
  }

  static String joinMessages(List<String> parts) {
    return parts.where((p) => p.trim().isNotEmpty).join('；');
  }

  static String _joinMessages(List<String> parts) => joinMessages(parts);

  /// 删除 Hub 管理的本地 clone（仅允许 `serversRoot` 下的子目录）。
  Future<McpRepoCloneResult> deleteLocal({required String localPath}) async {
    final root = McpPaths.serversRoot;
    if (root == null) {
      return const McpRepoCloneResult(
        ok: false,
        message:
            'Local repository management is not supported on this platform',
      );
    }

    if (!_isUnderServersRoot(localPath)) {
      return McpRepoCloneResult(
        ok: true,
        localPath: p.normalize(localPath),
        message:
            'Path is outside Hub servers; local directory deletion skipped',
      );
    }
    final normalizedPath = p.normalize(localPath);

    final dir = Directory(normalizedPath);
    if (!await dir.exists()) {
      return McpRepoCloneResult(
        ok: true,
        localPath: normalizedPath,
        message: 'Local directory does not exist; deletion skipped',
      );
    }

    try {
      await dir.delete(recursive: true);
      return McpRepoCloneResult(
        ok: true,
        localPath: normalizedPath,
        message: 'Deleted local directory $normalizedPath',
      );
    } catch (error) {
      return McpRepoCloneResult(
        ok: false,
        localPath: normalizedPath,
        message: 'Failed to delete local directory: $error',
      );
    }
  }
}
