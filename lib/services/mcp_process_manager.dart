import 'dart:async';
import 'dart:io';

import '../models/mcp_server_entry.dart';

enum McpProcessStatus { stopped, starting, running, error }

class McpProcessState {
  const McpProcessState({required this.status, this.pid, this.lastError});

  final McpProcessStatus status;
  final int? pid;
  final String? lastError;
}

typedef McpProcessStateCallback = void Function();

/// Hub 拉起的 MCP 进程的最小进程管理器。
class McpProcessManager {
  McpProcessManager({this.onStateChanged});

  McpProcessStateCallback? onStateChanged;

  final Map<String, Process> _processes = {};
  final Map<String, McpProcessState> _states = {};

  void _notifyStateChanged() => onStateChanged?.call();

  McpProcessState stateFor(String id) =>
      _states[id] ?? const McpProcessState(status: McpProcessStatus.stopped);

  /// 只使用真实存在的目录，避免 Windows 因失效 cwd 报找不到路径。
  Future<String?> resolveWorkingDirectory(McpServerEntry server) async {
    for (final candidate in [server.cwd, server.localPath]) {
      if (candidate == null || candidate.trim().isEmpty) continue;
      if (await Directory(candidate).exists()) return candidate;
    }
    return null;
  }

  Future<McpProcessState> start(McpServerEntry server) async {
    final command = server.command;
    if (command == null || command.trim().isEmpty) {
      final state = const McpProcessState(
        status: McpProcessStatus.error,
        lastError: 'Start command is missing',
      );
      _states[server.id] = state;
      _notifyStateChanged();
      return state;
    }

    await stop(server.id);
    _states[server.id] = const McpProcessState(
      status: McpProcessStatus.starting,
    );
    _notifyStateChanged();

    try {
      final workingDirectory = await resolveWorkingDirectory(server);
      final process = await Process.start(
        command,
        server.args,
        workingDirectory: workingDirectory,
        environment: {...Platform.environment, ...server.env},
        runInShell: true,
      );
      // 持续排空子进程输出管道，避免日志写满 OS 缓冲区后阻塞子进程。
      unawaited(process.stdout.drain<void>().catchError((_) {}));
      unawaited(process.stderr.drain<void>().catchError((_) {}));
      _processes[server.id] = process;
      final state = McpProcessState(
        status: McpProcessStatus.running,
        pid: process.pid,
      );
      _states[server.id] = state;
      _notifyStateChanged();
      unawaited(
        process.exitCode.then((code) {
          if (_processes[server.id] == process) {
            _processes.remove(server.id);
            _states[server.id] = McpProcessState(
              status: McpProcessStatus.stopped,
              lastError: code == 0 ? null : 'Process exited with code $code',
            );
            _notifyStateChanged();
          }
        }),
      );
      return state;
    } catch (error) {
      final state = McpProcessState(
        status: McpProcessStatus.error,
        lastError: '$error',
      );
      _states[server.id] = state;
      _notifyStateChanged();
      return state;
    }
  }

  Future<void> stop(String id) async {
    final process = _processes.remove(id);
    if (process != null) {
      if (Platform.isWindows) {
        // runInShell 在 Windows 下只返回 cmd.exe 的 PID，用 taskkill /T /F
        // 清理整棵子进程树，防止 python/node/uv 残留并锁住本地目录。
        try {
          await Process.run('taskkill', [
            '/PID',
            '${process.pid}',
            '/T',
            '/F',
          ]).timeout(const Duration(seconds: 3));
        } catch (_) {}
      }
      process.kill();
      try {
        await process.exitCode.timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
    _states[id] = const McpProcessState(status: McpProcessStatus.stopped);
    _notifyStateChanged();
  }

  Future<void> stopAll() async {
    final ids = _processes.keys.toList();
    for (final id in ids) {
      await stop(id);
    }
  }
}
