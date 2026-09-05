import 'last_sync_attempt_store.dart';

/// Whether a finished WebDAV operation should stamp the last-attempt line.
bool shouldRecordWebDavAttempt({
  required bool ok,
  required bool isWebDavActivity,
  required bool automatic,
  required bool noOpSuccess,
  required bool dataChanged,
}) {
  if (!isWebDavActivity) return false;
  if (ok && noOpSuccess) return false;
  if (!ok) return true;
  if (!automatic) return true;
  return dataChanged;
}

bool isWebDavTransferActivity(String activity) {
  return activity == 'Download' || activity == 'Merge' || activity == 'Upload';
}

Future<void> recordResourceWebDavAttempt({
  required LastSyncAttemptStore? store,
  required String activity,
  required String packageKey,
  required bool ok,
  required bool recordAttempt,
}) async {
  if (store == null) return;
  if (!shouldRecordWebDavAttempt(
    ok: ok,
    isWebDavActivity: isWebDavTransferActivity(activity),
    automatic: false,
    noOpSuccess: ok && !recordAttempt,
    dataChanged: true,
  )) {
    return;
  }
  await store.record(packageKey, ok: ok);
}
