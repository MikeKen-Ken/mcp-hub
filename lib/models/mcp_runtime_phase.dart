/// MCP 在 Hub 视角下的运行阶段（动态）。
enum McpRuntimePhase {
  stopped,
  starting,
  running,
  error,

  /// 不由 Hub 跟踪进程（远端 HTTP 等）。
  external,
}

extension McpRuntimePhaseLabels on McpRuntimePhase {
  String get label => switch (this) {
    McpRuntimePhase.stopped => 'Stopped',
    McpRuntimePhase.starting => 'Starting',
    McpRuntimePhase.running => 'Running',
    McpRuntimePhase.error => 'Error',
    McpRuntimePhase.external => 'External',
  };

  bool get isActive => this == McpRuntimePhase.running;
}
