/// Syncable MCP catalog fields (no secrets, no machine paths, no enable state).
class SyncableServer {
  const SyncableServer({
    required this.id,
    required this.name,
    required this.transport,
    required this.updatedAt,
    this.repoUrl,
    this.command,
    this.args = const [],
    this.url,
    this.notes,
  });

  final String id;
  final String name;
  final String transport;
  final int updatedAt;
  final String? repoUrl;
  final String? command;
  final List<String> args;
  final String? url;
  final String? notes;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'transport': transport,
        'updatedAt': updatedAt,
        if (repoUrl != null) 'repoUrl': repoUrl,
        if (command != null) 'command': command,
        if (args.isNotEmpty) 'args': args,
        if (url != null) 'url': url,
        if (notes != null) 'notes': notes,
      };

  factory SyncableServer.fromJson(Map<String, dynamic> json) {
    final argsRaw = json['args'];
    return SyncableServer(
      id: json['id'] as String,
      name: json['name'] as String? ?? json['id'] as String,
      transport: json['transport'] as String? ?? 'stdio',
      updatedAt: json['updatedAt'] as int? ?? 0,
      repoUrl: json['repoUrl'] as String?,
      command: json['command'] as String?,
      args: argsRaw is List
          ? argsRaw.map((e) => e.toString()).toList()
          : const [],
      url: json['url'] as String?,
      // 忽略远端历史字段 enabled：开/关仅本机有效
      notes: json['notes'] as String?,
    );
  }

  bool sameContent(SyncableServer other) {
    return id == other.id &&
        name == other.name &&
        transport == other.transport &&
        repoUrl == other.repoUrl &&
        command == other.command &&
        _listEq(args, other.args) &&
        url == other.url &&
        notes == other.notes;
  }

  static bool _listEq(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// 远端清单信封，放在 `<remotePath>/catalog.zip` 内的 `catalog.json`。
class CatalogSyncDocument {
  const CatalogSyncDocument({
    required this.servers,
    required this.updatedAt,
    this.tombstones = const {},
    this.version = 1,
  });

  final int version;
  final int updatedAt;
  final List<SyncableServer> servers;
  final Map<String, int> tombstones;

  static const empty = CatalogSyncDocument(
    servers: [],
    updatedAt: 0,
    tombstones: {},
  );

  Map<String, dynamic> toJson() => {
        'version': version,
        'updatedAt': updatedAt,
        'servers': servers.map((s) => s.toJson()).toList(),
        'tombstones': tombstones,
      };

  factory CatalogSyncDocument.fromJson(Map<String, dynamic> json) {
    final list = json['servers'];
    final tombs = json['tombstones'];
    return CatalogSyncDocument(
      version: json['version'] as int? ?? 1,
      updatedAt: json['updatedAt'] as int? ?? 0,
      servers: list is List
          ? list
              .whereType<Map>()
              .map((e) => SyncableServer.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      tombstones: tombs is Map
          ? tombs.map(
              (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0),
            )
          : const {},
    );
  }

  CatalogSyncDocument copyWith({
    List<SyncableServer>? servers,
    int? updatedAt,
    Map<String, int>? tombstones,
  }) {
    return CatalogSyncDocument(
      version: version,
      servers: servers ?? this.servers,
      updatedAt: updatedAt ?? this.updatedAt,
      tombstones: tombstones ?? this.tombstones,
    );
  }
}
