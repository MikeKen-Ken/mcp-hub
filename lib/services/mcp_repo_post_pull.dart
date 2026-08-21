import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'mcp_repo_service.dart';

/// `git pull` 成功后的依赖同步与构建（Node / uv 等）。
abstract final class McpRepoPostPull {
  static Future<McpRepoCloneResult> apply({required String localPath}) async {
    final messages = <String>[];

    final nodeResult = await _rebuildNodeProjectIfNeeded(localPath);
    if (!nodeResult.ok) return nodeResult;
    if (nodeResult.message.isNotEmpty) messages.add(nodeResult.message);

    final uvResult = await _uvSyncIfNeeded(localPath);
    if (!uvResult.ok) return uvResult;
    if (uvResult.message.isNotEmpty) messages.add(uvResult.message);

    return McpRepoCloneResult(
      ok: true,
      localPath: localPath,
      message: messages.join('；'),
    );
  }

  /// 是否存在 `package.json` 且定义了 `build` 脚本。
  static Future<bool> needsNodeRebuild(String localPath) async {
    final scripts = await _readPackageScripts(localPath);
    return scripts != null && scripts.containsKey('build');
  }

  /// 是否存在 `pyproject.toml`（Python / uv 项目）。
  static Future<bool> needsUvSync(String localPath) async {
    return await File(p.join(localPath, 'pyproject.toml')).exists();
  }

  static Future<Map<String, dynamic>?> _readPackageScripts(
    String localPath,
  ) async {
    final file = File(p.join(localPath, 'package.json'));
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      final scripts = decoded['scripts'];
      if (scripts is! Map) return null;
      return scripts.map((k, v) => MapEntry(k.toString(), v));
    } catch (_) {
      return null;
    }
  }

  static Future<McpRepoCloneResult> _rebuildNodeProjectIfNeeded(
    String localPath,
  ) async {
    if (!await needsNodeRebuild(localPath)) {
      return McpRepoCloneResult(ok: true, localPath: localPath, message: '');
    }

    final lockFile = p.join(localPath, 'package-lock.json');
    if (await File(lockFile).exists()) {
      final ci = await _run(
        localPath: localPath,
        command: 'npm',
        args: ['ci'],
        label: 'npm ci',
      );
      if (!ci.ok) return ci;
      if (ci.message.isNotEmpty) {
        // 成功时 message 为空，失败才返回
      }
    }

    return _run(
      localPath: localPath,
      command: 'npm',
      args: ['run', 'build'],
      label: 'npm run build',
      successMessage: 'npm build completed',
    );
  }

  static Future<McpRepoCloneResult> _uvSyncIfNeeded(String localPath) async {
    if (!await needsUvSync(localPath)) {
      return McpRepoCloneResult(ok: true, localPath: localPath, message: '');
    }
    return _run(
      localPath: localPath,
      command: 'uv',
      args: ['sync'],
      label: 'uv sync',
      successMessage: 'uv sync completed',
    );
  }

  static Future<McpRepoCloneResult> _run({
    required String localPath,
    required String command,
    required List<String> args,
    required String label,
    String? successMessage,
  }) async {
    final result = await Process.run(
      command,
      args,
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
            ? '$label failed (code ${result.exitCode})'
            : '$label failed: $detail',
      );
    }
    return McpRepoCloneResult(
      ok: true,
      localPath: localPath,
      message: successMessage ?? '',
    );
  }
}
