import '../../common/app_locale.dart';
import '../config_backup/config_backup_service.dart';
import '../hub_configuration/hub_configuration_result.dart';
import '../skill_sync/skill_sync_result.dart';
import 'operation_log_entry.dart';
import 'operation_log_store.dart';

/// 统一把各子系统的结果转换为结构化 [OperationLogEntry] 并写入 [OperationLogStore]。
class OperationLogRecorder {
  const OperationLogRecorder(this.store);

  final OperationLogStore store;

  Future<void> record({
    required OperationLogCategory category,
    required String action,
    String? target,
    OperationLogTrigger trigger = OperationLogTrigger.manual,
    required bool ok,
    bool partial = false,
    required String message,
    int? durationMs,
    int pulledFiles = 0,
    int pushedFiles = 0,
    int deployedFiles = 0,
    int packageCount = 0,
  }) {
    final resolvedStatus = resolveStatus(
      ok: ok,
      partial: partial,
      message: message,
    );
    final formattedDetail = formatDetail(message);
    final summary = buildSummary(
      status: resolvedStatus,
      message: formattedDetail,
    );
    final now = DateTime.now().toUtc();
    return store.append(
      OperationLogEntry(
        id: store.nextId(now),
        timestamp: now,
        category: category,
        status: resolvedStatus,
        trigger: trigger,
        action: action,
        target: target,
        summary: summary,
        detail: formattedDetail,
        durationMs: durationMs,
        pulledFiles: pulledFiles,
        pushedFiles: pushedFiles,
        deployedFiles: deployedFiles,
        packageCount: packageCount,
      ),
    );
  }

  Future<void> recordSkillSync({
    required OperationLogCategory category,
    required String action,
    String? target,
    OperationLogTrigger trigger = OperationLogTrigger.manual,
    required SkillSyncResult result,
    int? durationMs,
  }) {
    return record(
      category: category,
      action: action,
      target: target,
      trigger: trigger,
      ok: result.ok,
      message: result.message,
      durationMs: durationMs,
      pulledFiles: result.pulledFiles,
      pushedFiles: result.pushedFiles,
      deployedFiles: result.deployedFiles,
      packageCount: result.packageCount,
    );
  }

  Future<SkillSyncResult> runSkillSyncLogged({
    required OperationLogCategory category,
    required String action,
    String? target,
    required Future<SkillSyncResult> Function() run,
  }) async {
    final sw = Stopwatch()..start();
    final result = await run();
    await recordSkillSync(
      category: category,
      action: action,
      target: target,
      result: result,
      durationMs: sw.elapsedMilliseconds,
    );
    return result;
  }

  Future<void> recordWebDavCatalog({
    required String action,
    required bool ok,
    required String message,
    int? durationMs,
    OperationLogTrigger trigger = OperationLogTrigger.manual,
  }) {
    return record(
      category: OperationLogCategory.sync,
      action: action,
      target: tr('MCP 清单 (WebDAV)', 'MCP Catalog (WebDAV)'),
      trigger: trigger,
      ok: ok,
      message: message,
      durationMs: durationMs,
    );
  }

  Future<void> recordHubConfiguration({
    required String action,
    required HubConfigurationResult result,
    int? durationMs,
  }) {
    return record(
      category: OperationLogCategory.sync,
      action: action,
      target: tr('Hub 配置（MCP 清单 + 文件夹资源）', 'Hub configuration (Catalog + Folders)'),
      ok: result.ok,
      message: result.message,
      durationMs: durationMs,
    );
  }

  Future<void> recordBackup({
    required String action,
    String? target,
    OperationLogTrigger trigger = OperationLogTrigger.manual,
    required ConfigBackupResult result,
    int? durationMs,
  }) {
    return record(
      category: OperationLogCategory.backup,
      action: action,
      target: target,
      trigger: trigger,
      ok: result.ok,
      message: result.message,
      durationMs: durationMs,
      deployedFiles: result.fileCount,
    );
  }

  Future<T> runBackupLogged<T>({
    required String action,
    String? target,
    required Future<T> Function() run,
    required ConfigBackupResult Function(T value) toResult,
  }) async {
    final sw = Stopwatch()..start();
    final value = await run();
    await recordBackup(
      action: action,
      target: target,
      result: toResult(value),
      durationMs: sw.elapsedMilliseconds,
    );
    return value;
  }

  static OperationLogStatus resolveStatus({
    required bool ok,
    bool partial = false,
    required String message,
  }) {
    if (ok) return OperationLogStatus.success;
    if (partial) return OperationLogStatus.partial;

    final parts = message
        .split(RegExp(r'[；;\n]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.length > 1) {
      final failed = parts.where(_looksFailed).length;
      if (failed > 0 && failed < parts.length) {
        return OperationLogStatus.partial;
      }
    }
    return OperationLogStatus.failure;
  }

  static bool _looksFailed(String line) {
    final lower = line.toLowerCase();
    return line.contains('失败') ||
        line.contains('部分失败') ||
        lower.contains('failed') ||
        lower.contains('error:') ||
        lower.contains('fatal:');
  }

  /// 将分号分隔的多目标结果格式化为多行，方便在日志详情中逐项核对。
  static String formatDetail(String message) {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.contains('\n')) return trimmed;
    final parts = trimmed
        .split(RegExp(r'[；;]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.length <= 1) return trimmed;
    return parts.join('\n');
  }

  static String buildSummary({
    required OperationLogStatus status,
    required String message,
  }) {
    final lines = message
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      return status.label;
    }
    if (lines.length == 1) {
      return lines.first;
    }
    final failed = lines.where(_looksFailed).length;
    if (failed > 0 && failed < lines.length) {
      return tr(
        '部分失败（${lines.length - failed} 项成功 / $failed 项失败）：${lines.first}',
        'Partial failure (${lines.length - failed} succeeded / $failed failed): ${lines.first}',
      );
    }
    return tr(
      '${lines.first}（共 ${lines.length} 项）',
      '${lines.first} (${lines.length} items)',
    );
  }
}
