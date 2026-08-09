import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../models/mcp_server_entry.dart';
import '../../services/mcp_paths.dart';
import 'auto_backup_settings.dart';
import 'config_backup_service.dart';

enum AutoBackupStatus { idle, backingUp, success, error }

/// 自动备份调度、设置持久化与过期文件清理。
class AutoConfigBackupService extends ChangeNotifier {
  AutoConfigBackupService({
    required Future<List<McpServerEntry>> Function() loadServers,
    ConfigBackupService? backupService,
    AutoBackupSettingsStore? settingsStore,
    DateTime Function()? now,
    String? defaultDirectory,
  }) : _loadServers = loadServers,
       _backupService = backupService ?? ConfigBackupService(),
       _settingsStore = settingsStore ?? AutoBackupSettingsStore(),
       _now = now ?? DateTime.now,
       _defaultDirectory = defaultDirectory;

  static const autoFilePrefix = 'AgentHub-auto-backup-';

  final Future<List<McpServerEntry>> Function() _loadServers;
  final ConfigBackupService _backupService;
  final AutoBackupSettingsStore _settingsStore;
  final DateTime Function() _now;
  final String? _defaultDirectory;

  AutoBackupSettings settings = const AutoBackupSettings();
  AutoBackupStatus status = AutoBackupStatus.idle;
  DateTime? lastBackupAt;
  String? lastBackupPath;
  String? lastError;
  bool initialized = false;

  Timer? _timer;
  bool _inFlight = false;

  String? get defaultDirectory =>
      _defaultDirectory ??
      (McpPaths.hubDataRoot == null
          ? null
          : p.join(McpPaths.hubDataRoot!, 'backups'));

  String? get effectiveDirectory => settings.directory ?? defaultDirectory;

  bool get isScheduled => _timer?.isActive == true;

  Future<void> initialize() async {
    settings = await _settingsStore.load();
    initialized = true;
    _reschedule();
    notifyListeners();
  }

  Future<void> updateSettings(AutoBackupSettings value) async {
    settings = value.copyWith(intervalMinutes: value.intervalMinutes);
    await _settingsStore.save(settings);
    _reschedule();
    notifyListeners();
  }

  /// 生成一次自动备份；定时触发和界面“立即备份”共用该入口。
  Future<ConfigBackupResult> backupNow() async {
    if (_inFlight) {
      return const ConfigBackupResult(ok: false, message: '自动备份正在进行中，请稍候');
    }
    final directoryPath = effectiveDirectory;
    if (directoryPath == null || directoryPath.trim().isEmpty) {
      return const ConfigBackupResult(ok: false, message: '当前平台没有可用的自动备份目录');
    }

    _inFlight = true;
    status = AutoBackupStatus.backingUp;
    lastError = null;
    notifyListeners();
    try {
      final directory = Directory(directoryPath);
      await directory.create(recursive: true);
      await cleanupExpiredBackups(directoryPath);
      final at = _now();
      final zipPath = p.join(directoryPath, _autoFileName(at));
      final result = await _backupService.exportToZip(
        zipPath: zipPath,
        servers: await _loadServers(),
      );
      if (result.ok) {
        lastBackupAt = at;
        lastBackupPath = result.path;
        status = AutoBackupStatus.success;
      } else {
        lastError = result.message;
        status = AutoBackupStatus.error;
      }
      notifyListeners();
      return result;
    } catch (error) {
      lastError = '$error';
      status = AutoBackupStatus.error;
      notifyListeners();
      return ConfigBackupResult(ok: false, message: '自动备份失败：$error');
    } finally {
      _inFlight = false;
    }
  }

  /// 只清理本功能生成且超过保留期的 zip，不影响用户手动导出的文件。
  Future<int> cleanupExpiredBackups(String directoryPath) async {
    final directory = Directory(directoryPath);
    if (!await directory.exists()) return 0;
    final cutoff = _now().subtract(
      const Duration(days: AutoBackupSettings.retentionDays),
    );
    var deleted = 0;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!name.startsWith(autoFilePrefix) ||
          p.extension(name).toLowerCase() != '.zip') {
        continue;
      }
      if ((await entity.lastModified()).isBefore(cutoff)) {
        await entity.delete();
        deleted += 1;
      }
    }
    return deleted;
  }

  String _autoFileName(DateTime at) {
    final local = at.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '$autoFilePrefix'
        '${local.year}${two(local.month)}${two(local.day)}-'
        '${two(local.hour)}${two(local.minute)}${two(local.second)}.zip';
  }

  void _reschedule() {
    _timer?.cancel();
    _timer = null;
    if (!settings.enabled || !McpPaths.isDesktopSupported) return;
    _timer = Timer.periodic(
      Duration(minutes: settings.intervalMinutes),
      (_) => unawaited(backupNow()),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
