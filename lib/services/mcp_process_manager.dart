import 'dart:async';
import 'dart:io';

import '../models/mcp_server_entry.dart';
import '../models/mcp_transport.dart';

enum McpProcessStatus { stopped, starting, running, error }

class McpProcessState {
  const McpProcessState({
    required this.status,
    this.pid,
    this.lastError,
  });

  final McpProcessStatus status;
  final int? pid;
  final String? lastError;
}

/// Minimal process supervisor for HTTP MCP servers Hub starts itself.
/// stdio servers are left to Cursor / Codex.
class McpProcessManager {
  final Map<String, Process> _processes = {};
  final Map<String, McpProcessState> _states = {};

  McpProcessState stateFor(String id) =>
      _states[id] ?? const McpProcessState(status: McpProcessStatus.stopped);

  Future<McpProcessState> start(McpServerEntry server) async {
    if (server.transport != McpTransport.http) {
      return const McpProcessState(
        status: McpProcessStatus.stopped,
        lastError: 'stdio MCP 由 Cursor/Codex 按需拉起，Hub 不驻留进程',
      );
    }
    final command = server.command;
    if (command == null || command.trim().isEmpty) {
      final state = const McpProcessState(
        status: McpProcessStatus.error,
        lastError: '缺少启动命令',
      );
      _states[server.id] = state;
      return state;
    }

    await stop(server.id);
    _states[server.id] = const McpProcessState(status: McpProcessStatus.starting);

    try {
      final process = await Process.start(
        command,
        server.args,
        workingDirectory: server.cwd ?? server.localPath,
        environment: {
          ...Platform.environment,
          ...server.env,
        },
        runInShell: true,
      );
      _processes[server.id] = process;
      final state = McpProcessState(
        status: McpProcessStatus.running,
        pid: process.pid,
      );
      _states[server.id] = state;
      unawaited(process.exitCode.then((code) {
        if (_processes[server.id] == process) {
          _processes.remove(server.id);
          _states[server.id] = McpProcessState(
            status: McpProcessStatus.stopped,
            lastError: code == 0 ? null : '进程退出 code $code',
          );
        }
      }));
      return state;
    } catch (error) {
      final state = McpProcessState(
        status: McpProcessStatus.error,
        lastError: '$error',
      );
      _states[server.id] = state;
      return state;
    }
  }

  Future<void> stop(String id) async {
    final process = _processes.remove(id);
    if (process != null) {
      process.kill();
      try {
        await process.exitCode.timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
    _states[id] = const McpProcessState(status: McpProcessStatus.stopped);
  }

  Future<void> stopAll() async {
    final ids = _processes.keys.toList();
    for (final id in ids) {
      await stop(id);
    }
  }
}
