import '../../common/app_locale.dart';
import '../../common/package_time.dart';
import 'last_sync_attempt.dart';

String lastSyncAttemptLabel(LastSyncAttempt? attempt) {
  if (attempt == null) return tr('尚未同步', 'Not synced yet');
  final when = formatPackageTime(attempt.at);
  return attempt.ok
      ? tr('最近成功 $when', 'Last succeeded $when')
      : tr('最近失败 $when', 'Last failed $when');
}

String lastSyncAttemptOverviewLabel({
  required LastSyncAttempt? latest,
  required bool syncing,
}) {
  final base = lastSyncAttemptLabel(latest);
  if (!syncing) return base;
  return tr('$base · 正在同步…', '$base · Syncing…');
}
