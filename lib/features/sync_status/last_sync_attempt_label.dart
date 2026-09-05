import '../../common/package_time.dart';
import 'last_sync_attempt.dart';

String lastSyncAttemptLabel(LastSyncAttempt? attempt) {
  if (attempt == null) return 'Not synced yet';
  final when = formatPackageTime(attempt.at);
  return attempt.ok ? 'Last succeeded $when' : 'Last failed $when';
}

String lastSyncAttemptOverviewLabel({
  required LastSyncAttempt? latest,
  required bool syncing,
}) {
  final base = lastSyncAttemptLabel(latest);
  if (!syncing) return base;
  return '$base · Syncing…';
}
