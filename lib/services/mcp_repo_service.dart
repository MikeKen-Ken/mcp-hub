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
      return const McpRepoCloneResult(ok: false, message: '当前平台不支持本地仓库管理');
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
    final result = await Process.run('git', [
      'clone',
      repoUrl,
      target,
    ], runInShell: true);
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
      return McpRepoCloneResult(ok: false, message: '本地目录不存在：$localPath');
    }
    if (!await isHubGitCheckout(localPath)) {
      return McpRepoCloneResult(
        ok: false,
        localPath: localPath,
        message: '不是 Hub 管理的 Git 仓库，无法 git 更新',
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
            ? 'git pull 失败 (code ${result.exitCode})'
            : 'git pull 失败：$detail',
      );
    }
    final out = (result.stdout as String).trim();
    if (out.isEmpty ||
        out.contains('Already up to date') ||
        out.contains('Already up-to-date')) {
      return McpRepoCloneResult(
        ok: true,
        localPath: localPath,
        message: '已是最新',
      );
    }
    return McpRepoCloneResult(
      ok: true,
      localPath: localPath,
      message: '已更新；$out',
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
      return const McpRepoCloneResult(ok: false, message: '当前平台不支持本地仓库管理');
    }

    if (!_isUnderServersRoot(localPath)) {
      return McpRepoCloneResult(
        ok: true,
        localPath: p.normalize(localPath),
        message: '路径不在 Hub servers 下，跳过删除本地目录',
      );
    }
    final normalizedPath = p.normalize(localPath);

    final dir = Directory(normalizedPath);
    if (!await dir.exists()) {
      return McpRepoCloneResult(
        ok: true,
        localPath: normalizedPath,
        message: '本地目录不存在，跳过删除',
      );
    }

    try {
      await dir.delete(recursive: true);
      return McpRepoCloneResult(
        ok: true,
        localPath: normalizedPath,
        message: '已删除本地目录 $normalizedPath',
      );
    } catch (error) {
      return McpRepoCloneResult(
        ok: false,
        localPath: normalizedPath,
        message: '删除本地目录失败：$error',
      );
    }
  }
}
