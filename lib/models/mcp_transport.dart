/// How an MCP server is exposed to Cursor / Codex.
enum McpTransport {
  /// Client spawns the process (command + args).
  stdio,

  /// Hub (or another process) serves HTTP; clients connect by URL.
  http,
}

extension McpTransportCodec on McpTransport {
  String get wireName => switch (this) {
        McpTransport.stdio => 'stdio',
        McpTransport.http => 'http',
      };

  static McpTransport parse(String? raw) {
    return switch (raw) {
      'http' => McpTransport.http,
      _ => McpTransport.stdio,
    };
  }
}
