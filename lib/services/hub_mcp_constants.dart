/// Built-in Hub MCP (Streamable HTTP) conventions.
abstract final class HubMcpConstants {
  static const serverKey = 'hubMCP';
  static const defaultPort = 18766;
  static const host = '127.0.0.1';
  static const path = '/mcp';
  static const implementationName = 'mcp-hub';
  static const implementationVersion = '0.1.0';

  static String endpointUrl([int port = defaultPort]) =>
      'http://$host:$port$path';
}
