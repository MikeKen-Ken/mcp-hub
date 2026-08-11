/// Hub 对 MCP 的管理/托管方式（静态，来自目录配置）。
enum McpManagementKind {
  /// 内置 hubMCP（Hub 内嵌 HTTP 服务）。
  builtInHttp,

  /// Hub clone 的 Git 仓库 + stdio 进程。
  hubGitStdio,

  /// Hub 可拉起的 stdio 进程，但非 Git 托管（npx/uvx 等）。
  hubStdio,

  /// stdio 桥接远程 MCP（如 mcp-remote）。
  remoteBridge,

  /// 纯远端 HTTP，Hub 不拉起进程。
  externalHttp,

  /// stdio 但缺少启动命令等，无法由 Hub 管理。
  unconfigured,
}

extension McpManagementKindLabels on McpManagementKind {
  String get label => switch (this) {
        McpManagementKind.builtInHttp => '内置',
        McpManagementKind.hubGitStdio => 'Git',
        McpManagementKind.hubStdio => '本地',
        McpManagementKind.remoteBridge => '桥接',
        McpManagementKind.externalHttp => '远端',
        McpManagementKind.unconfigured => '未配置',
      };
}
