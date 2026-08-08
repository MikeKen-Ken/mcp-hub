/// 配置备份包清单（写入 zip 根目录 `manifest.json`）。
class ConfigBackupManifest {
  const ConfigBackupManifest({
    required this.formatVersion,
    required this.exportedAt,
    required this.appName,
    this.fileCount = 0,
    this.includesCatalog = true,
    this.includesResources = true,
    this.notes,
  });

  static const currentFormatVersion = 1;
  static const fileName = 'manifest.json';

  final int formatVersion;
  final DateTime exportedAt;
  final String appName;
  final int fileCount;
  final bool includesCatalog;
  final bool includesResources;
  final String? notes;

  Map<String, dynamic> toJson() => {
        'formatVersion': formatVersion,
        'exportedAt': exportedAt.toUtc().toIso8601String(),
        'appName': appName,
        'fileCount': fileCount,
        'includesCatalog': includesCatalog,
        'includesResources': includesResources,
        if (notes != null) 'notes': notes,
      };

  factory ConfigBackupManifest.fromJson(Map<String, dynamic> json) {
    return ConfigBackupManifest(
      formatVersion: json['formatVersion'] as int? ?? 0,
      exportedAt: DateTime.tryParse(json['exportedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      appName: json['appName'] as String? ?? 'Agent Hub',
      fileCount: json['fileCount'] as int? ?? 0,
      includesCatalog: json['includesCatalog'] as bool? ?? true,
      includesResources: json['includesResources'] as bool? ?? true,
      notes: json['notes'] as String?,
    );
  }
}
