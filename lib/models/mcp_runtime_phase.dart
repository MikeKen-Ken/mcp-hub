import '../common/app_locale.dart';

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
    McpRuntimePhase.stopped => tr('已停止', 'Stopped'),
    McpRuntimePhase.starting => tr('启动中', 'Starting'),
    McpRuntimePhase.running => tr('运行中', 'Running'),
    McpRuntimePhase.error => tr('异常', 'Error'),
    McpRuntimePhase.external => tr('外部', 'External'),
  };

  bool get isActive => this == McpRuntimePhase.running;
}
