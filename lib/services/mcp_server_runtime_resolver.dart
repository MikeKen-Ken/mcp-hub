import 'package:path/path.dart' as p;

import '../models/mcp_management_kind.dart';
import '../models/mcp_runtime_phase.dart';
import '../models/mcp_server_entry.dart';
import '../models/mcp_server_runtime_info.dart';
import '../models/mcp_transport.dart';
import 'hub_mcp_constants.dart';
import 'hub_mcp_host.dart';
import 'mcp_paths.dart';
import 'mcp_process_manager.dart';

/// 根据目录条目与 Hub 运行时状态推导管理能力与运行阶段。
abstract final class McpServerRuntimeResolver {
  static McpManagementKind managementKindFor(McpServerEntry server) {
    if (server.builtIn || server.id == HubMcpConstants.serverKey) {
      return McpManagementKind.builtInHttp;
    }
    if (server.transport == McpTransport.http) {
      return McpManagementKind.externalHttp;
    }
    if (_isRemoteBridge(server)) {
      return McpManagementKind.remoteBridge;
    }
    if (server.canHubStartProcess) {
      final hasRepo = server.repoUrl != null && server.repoUrl!.trim().isNotEmpty;
      if (hasRepo && _isHubManagedLocalPath(server.localPath)) {
        return McpManagementKind.hubGitStdio;
      }
      return McpManagementKind.hubStdio;
    }
    return McpManagementKind.unconfigured;
  }

  static McpServerRuntimeInfo resolve({
    required McpServerEntry server,
    required HubMcpHost hubHost,
    required McpProcessState processState,
    required bool gitManaged,
  }) {
    final kind = managementKindFor(server);

    if (kind == McpManagementKind.builtInHttp) {
      final phase = _phaseFromHubHost(hubHost.status);
      return McpServerRuntimeInfo(
        kind: kind,
        phase: phase,
        canStart: false,
        canStop: false,
        canUpdate: false,
        lastError: hubHost.lastError,
      );
    }

    if (kind == McpManagementKind.externalHttp) {
      return const McpServerRuntimeInfo(
        kind: McpManagementKind.externalHttp,
        phase: McpRuntimePhase.external,
        canStart: false,
        canStop: false,
        canUpdate: false,
      );
    }

    if (kind == McpManagementKind.unconfigured) {
      return const McpServerRuntimeInfo(
        kind: McpManagementKind.unconfigured,
        phase: McpRuntimePhase.external,
        canStart: false,
        canStop: false,
        canUpdate: false,
      );
    }

    final phase = _phaseFromProcess(processState.status);
    final canManageProcess = server.canHubStartProcess;
    final runningOrStarting =
        phase == McpRuntimePhase.running || phase == McpRuntimePhase.starting;

    return McpServerRuntimeInfo(
      kind: kind,
      phase: phase,
      canStart: canManageProcess && !runningOrStarting,
      canStop: canManageProcess && runningOrStarting,
      canUpdate: gitManaged,
      pid: processState.pid,
      lastError: processState.lastError,
    );
  }

  static bool _isRemoteBridge(McpServerEntry server) {
    for (final arg in server.args) {
      if (arg.contains('mcp-remote')) return true;
    }
    final cmd = server.command?.toLowerCase() ?? '';
    return cmd.contains('mcp-remote');
  }

  static bool _isHubManagedLocalPath(String? localPath) {
    if (localPath == null || localPath.trim().isEmpty) return false;
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

  static McpRuntimePhase _phaseFromHubHost(HubMcpStatus status) =>
      switch (status) {
        HubMcpStatus.stopped => McpRuntimePhase.stopped,
        HubMcpStatus.starting => McpRuntimePhase.starting,
        HubMcpStatus.running => McpRuntimePhase.running,
        HubMcpStatus.error => McpRuntimePhase.error,
      };

  static McpRuntimePhase _phaseFromProcess(McpProcessStatus status) =>
      switch (status) {
        McpProcessStatus.stopped => McpRuntimePhase.stopped,
        McpProcessStatus.starting => McpRuntimePhase.starting,
        McpProcessStatus.running => McpRuntimePhase.running,
        McpProcessStatus.error => McpRuntimePhase.error,
      };
}
