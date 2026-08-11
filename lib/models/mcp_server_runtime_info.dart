import 'mcp_management_kind.dart';
import 'mcp_runtime_phase.dart';

/// 单个 MCP 的管理能力与运行状态快照（供 UI / MCP 工具使用）。
class McpServerRuntimeInfo {
  const McpServerRuntimeInfo({
    required this.kind,
    required this.phase,
    required this.canStart,
    required this.canStop,
    required this.canUpdate,
    this.pid,
    this.lastError,
  });

  final McpManagementKind kind;
  final McpRuntimePhase phase;
  final bool canStart;
  final bool canStop;
  final bool canUpdate;
  final int? pid;
  final String? lastError;

  String get kindLabel => kind.label;
  String get phaseLabel => phase.label;

  bool get isRunning => phase == McpRuntimePhase.running;

  String get phaseBadgeLabel {
    if (phase == McpRuntimePhase.running && pid != null) {
      return '运行中 · pid $pid';
    }
    return phaseLabel;
  }

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'kindLabel': kindLabel,
        'phase': phase.name,
        'phaseLabel': phaseLabel,
        'canStart': canStart,
        'canStop': canStop,
        'canUpdate': canUpdate,
        if (pid != null) 'pid': pid,
        if (lastError != null) 'lastError': lastError,
      };
}
