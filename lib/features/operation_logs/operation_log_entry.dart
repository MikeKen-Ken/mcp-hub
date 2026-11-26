import '../../common/app_locale.dart';

enum OperationLogCategory {
  sync,
  apply,
  convert,
  mcp,
  backup;

  String get label => switch (this) {
    OperationLogCategory.sync => tr('同步/上下行', 'Sync / Transfer'),
    OperationLogCategory.apply => tr('应用/写入', 'Apply / Write'),
    OperationLogCategory.convert => tr('资源转换', 'Convert'),
    OperationLogCategory.mcp => tr('MCP 管理', 'MCP'),
    OperationLogCategory.backup => tr('配置备份', 'Backup'),
  };

  static OperationLogCategory fromWire(String? raw) {
    return OperationLogCategory.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => OperationLogCategory.sync,
    );
  }
}

enum OperationLogStatus {
  success,
  partial,
  failure;

  String get label => switch (this) {
    OperationLogStatus.success => tr('成功', 'Success'),
    OperationLogStatus.partial => tr('部分失败', 'Partial'),
    OperationLogStatus.failure => tr('失败', 'Failed'),
  };

  static OperationLogStatus fromWire(String? raw) {
    return OperationLogStatus.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => OperationLogStatus.failure,
    );
  }
}

enum OperationLogTrigger {
  manual,
  auto;

  String get label => switch (this) {
    OperationLogTrigger.manual => tr('手动', 'Manual'),
    OperationLogTrigger.auto => tr('自动', 'Auto'),
  };

  static OperationLogTrigger fromWire(String? raw) {
    return OperationLogTrigger.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => OperationLogTrigger.manual,
    );
  }
}

/// 一条持久化的 Hub 操作日志（覆盖同步、下载、上传、应用、转换、MCP、备份）。
class OperationLogEntry {
  const OperationLogEntry({
    required this.id,
    required this.timestamp,
    required this.category,
    required this.status,
    required this.action,
    required this.summary,
    required this.detail,
    this.trigger = OperationLogTrigger.manual,
    this.target,
    this.durationMs,
    this.pulledFiles = 0,
    this.pushedFiles = 0,
    this.deployedFiles = 0,
    this.packageCount = 0,
  });

  final String id;
  final DateTime timestamp;
  final OperationLogCategory category;
  final OperationLogStatus status;
  final OperationLogTrigger trigger;
  final String action;
  final String? target;
  final String summary;
  final String detail;
  final int? durationMs;
  final int pulledFiles;
  final int pushedFiles;
  final int deployedFiles;
  final int packageCount;

  bool get ok => status == OperationLogStatus.success;

  String get formattedTime {
    final local = timestamp.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  String? get formattedDuration {
    final ms = durationMs;
    if (ms == null) return null;
    if (ms < 1000) return '${ms}ms';
    return '${(ms / 1000).toStringAsFixed(ms >= 10000 ? 1 : 2)}s';
  }

  List<String> get metricChips {
    final items = <String>[];
    if (pulledFiles > 0) {
      items.add(tr('拉取 $pulledFiles 个文件', '$pulledFiles pulled'));
    }
    if (pushedFiles > 0) {
      items.add(tr('上传 $pushedFiles 个文件', '$pushedFiles pushed'));
    }
    if (deployedFiles > 0) {
      items.add(tr('写入 $deployedFiles 项', '$deployedFiles written'));
    }
    if (packageCount > 0) {
      items.add(tr('$packageCount 个包', '$packageCount packages'));
    }
    return items;
  }

  String toPlainText() {
    final buffer = StringBuffer()
      ..write('[$formattedTime] [${status.label}] [${category.label}] ')
      ..write(action);
    if (target != null && target!.trim().isNotEmpty) {
      buffer.write(' ($target)');
    }
    if (trigger == OperationLogTrigger.auto) {
      buffer.write(' [${trigger.label}]');
    }
    final dur = formattedDuration;
    if (dur != null) {
      buffer.write(' · $dur');
    }
    final metrics = metricChips;
    if (metrics.isNotEmpty) {
      buffer.write(' · ${metrics.join(', ')}');
    }
    buffer
      ..writeln()
      ..writeln(detail.trim().isEmpty ? summary : detail.trim());
    return buffer.toString();
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'timestamp': timestamp.toUtc().toIso8601String(),
    'category': category.name,
    'status': status.name,
    'trigger': trigger.name,
    'action': action,
    if (target != null) 'target': target,
    'summary': summary,
    'detail': detail,
    if (durationMs != null) 'durationMs': durationMs,
    if (pulledFiles > 0) 'pulledFiles': pulledFiles,
    if (pushedFiles > 0) 'pushedFiles': pushedFiles,
    if (deployedFiles > 0) 'deployedFiles': deployedFiles,
    if (packageCount > 0) 'packageCount': packageCount,
  };

  static OperationLogEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id']?.toString();
    final ts = DateTime.tryParse('${raw['timestamp']}');
    final action = raw['action']?.toString();
    if (id == null || id.isEmpty || ts == null || action == null) {
      return null;
    }
    int intVal(String key) {
      final v = raw[key];
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse('$v') ?? 0;
    }

    final durationRaw = raw['durationMs'];
    final duration = durationRaw is int
        ? durationRaw
        : (durationRaw is num ? durationRaw.toInt() : null);

    return OperationLogEntry(
      id: id,
      timestamp: ts.toUtc(),
      category: OperationLogCategory.fromWire(raw['category']?.toString()),
      status: OperationLogStatus.fromWire(raw['status']?.toString()),
      trigger: OperationLogTrigger.fromWire(raw['trigger']?.toString()),
      action: action,
      target: raw['target']?.toString(),
      summary: raw['summary']?.toString() ?? '',
      detail: raw['detail']?.toString() ?? '',
      durationMs: duration,
      pulledFiles: intVal('pulledFiles'),
      pushedFiles: intVal('pushedFiles'),
      deployedFiles: intVal('deployedFiles'),
      packageCount: intVal('packageCount'),
    );
  }
}
