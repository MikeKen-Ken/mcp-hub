/// 一次下载/上传的进度快照。
class SyncProgress {
  const SyncProgress({required this.label, this.current = 0, this.total});

  /// 例如「正在下载 Skill」。
  final String label;
  final int current;

  /// 未知总数时为 null，进度条走不确定态。
  final int? total;

  double? get value {
    final max = total;
    if (max == null || max <= 0) return null;
    return (current / max).clamp(0.0, 1.0);
  }

  String get caption {
    final max = total;
    if (max != null && max > 0) return '$label  $current / $max';
    if (current > 0) return '$label  已处理 $current 个';
    return label;
  }
}
