/// 压缩包版本时间的展示格式（本地时区，精确到分钟）。
String formatPackageTime(DateTime? time) {
  if (time == null) return 'Unknown';
  final local = time.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

String currentPackageVersionLabel(DateTime? time) {
  if (time == null) return 'Current version: not recorded';
  return 'Current version: ${formatPackageTime(time)}';
}

DateTime? dateTimeFromEpochMs(int millis) {
  if (millis <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch(millis);
}
