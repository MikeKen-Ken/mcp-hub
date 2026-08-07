import 'mcp_transport.dart';

/// One managed MCP server in the local catalog.
class McpServerEntry {
  const McpServerEntry({
    required this.id,
    required this.name,
    required this.transport,
    this.repoUrl,
    this.localPath,
    this.command,
    this.args = const [],
    this.env = const {},
    this.url,
    this.enabled = false,
    this.autoStart = false,
    this.notes,
  });

  final String id;
  final String name;
  final McpTransport transport;

  /// Git remote used to clone / update the server sources.
  final String? repoUrl;

  /// Checkout directory under the hub servers root (absolute or relative).
  final String? localPath;

  /// stdio: executable
  final String? command;
  final List<String> args;
  final Map<String, String> env;

  /// http: endpoint URL (e.g. http://127.0.0.1:18765/mcp)
  final String? url;

  /// Whether this server should be written into Cursor / Codex.
  final bool enabled;

  /// For HTTP servers: start process when Hub launches.
  final bool autoStart;

  final String? notes;

  McpServerEntry copyWith({
    String? id,
    String? name,
    McpTransport? transport,
    String? repoUrl,
    String? localPath,
    String? command,
    List<String>? args,
    Map<String, String>? env,
    String? url,
    bool? enabled,
    bool? autoStart,
    String? notes,
  }) {
    return McpServerEntry(
      id: id ?? this.id,
      name: name ?? this.name,
      transport: transport ?? this.transport,
      repoUrl: repoUrl ?? this.repoUrl,
      localPath: localPath ?? this.localPath,
      command: command ?? this.command,
      args: args ?? this.args,
      env: env ?? this.env,
      url: url ?? this.url,
      enabled: enabled ?? this.enabled,
      autoStart: autoStart ?? this.autoStart,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'transport': transport.wireName,
        if (repoUrl != null) 'repoUrl': repoUrl,
        if (localPath != null) 'localPath': localPath,
        if (command != null) 'command': command,
        if (args.isNotEmpty) 'args': args,
        if (env.isNotEmpty) 'env': env,
        if (url != null) 'url': url,
        'enabled': enabled,
        'autoStart': autoStart,
        if (notes != null) 'notes': notes,
      };

  factory McpServerEntry.fromJson(Map<String, dynamic> json) {
    final argsRaw = json['args'];
    final envRaw = json['env'];
    return McpServerEntry(
      id: json['id'] as String,
      name: json['name'] as String? ?? json['id'] as String,
      transport: McpTransportCodec.parse(json['transport'] as String?),
      repoUrl: json['repoUrl'] as String?,
      localPath: json['localPath'] as String?,
      command: json['command'] as String?,
      args: argsRaw is List
          ? argsRaw.map((e) => e.toString()).toList()
          : const [],
      env: envRaw is Map
          ? envRaw.map((k, v) => MapEntry(k.toString(), v.toString()))
          : const {},
      url: json['url'] as String?,
      enabled: json['enabled'] as bool? ?? false,
      autoStart: json['autoStart'] as bool? ?? false,
      notes: json['notes'] as String?,
    );
  }
}
