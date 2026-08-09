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
    this.cwd,
    this.url,
    this.enabled = false,
    this.autoStart = false,
    this.builtIn = false,
    this.notes,
    this.updatedAt = 0,
  });

  final String id;
  final String name;
  final McpTransport transport;
  final String? repoUrl;
  final String? localPath;
  final String? command;
  final List<String> args;
  final Map<String, String> env;

  /// stdio 工作目录（写入 Cursor/Codex；本机字段，不进 WebDAV）
  final String? cwd;
  final String? url;
  final bool enabled;
  final bool autoStart;
  final bool builtIn;
  final String? notes;

  /// Epoch ms; used for WebDAV conflict resolution.
  final int updatedAt;

  /// Hub 是否可拉起该进程（非内置，且有启动命令）。
  bool get canHubStartProcess {
    if (builtIn) return false;
    final cmd = command?.trim();
    return cmd != null && cmd.isNotEmpty;
  }

  /// 已启用且可由 Hub 拉起时，应在应用启动/启用时自动启动。
  bool get shouldAutoStartByHub => enabled && canHubStartProcess;

  McpServerEntry copyWith({
    String? id,
    String? name,
    McpTransport? transport,
    String? repoUrl,
    String? localPath,
    String? command,
    List<String>? args,
    Map<String, String>? env,
    String? cwd,
    String? url,
    bool? enabled,
    bool? autoStart,
    bool? builtIn,
    String? notes,
    int? updatedAt,
    bool touch = false,
    bool clearCwd = false,
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
      cwd: clearCwd ? null : (cwd ?? this.cwd),
      url: url ?? this.url,
      enabled: enabled ?? this.enabled,
      autoStart: autoStart ?? this.autoStart,
      builtIn: builtIn ?? this.builtIn,
      notes: notes ?? this.notes,
      updatedAt: touch
          ? DateTime.now().millisecondsSinceEpoch
          : (updatedAt ?? this.updatedAt),
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
    if (cwd != null) 'cwd': cwd,
    if (url != null) 'url': url,
    'enabled': enabled,
    'autoStart': autoStart,
    'builtIn': builtIn,
    if (notes != null) 'notes': notes,
    'updatedAt': updatedAt,
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
      cwd: json['cwd'] as String?,
      url: json['url'] as String?,
      enabled: json['enabled'] as bool? ?? false,
      autoStart: json['autoStart'] as bool? ?? false,
      builtIn: json['builtIn'] as bool? ?? false,
      notes: json['notes'] as String?,
      updatedAt: json['updatedAt'] as int? ?? 0,
    );
  }
}
