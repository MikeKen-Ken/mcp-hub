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
        McpRuntimePhase.stopped => '已停止',
        McpRuntimePhase.starting => '启动中',
        McpRuntimePhase.running => '运行中',
        McpRuntimePhase.error => '异常',
        McpRuntimePhase.external => '外部',
      };

  bool get isActive => this == McpRuntimePhase.running;
}
