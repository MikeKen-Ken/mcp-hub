import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_hub/common/package_time.dart';
import 'package:mcp_hub/features/sync_status/sync_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('shouldRecordWebDavAttempt skips apply and no-op success', () {
    expect(
      shouldRecordWebDavAttempt(
        ok: true,
        isWebDavActivity: false,
        automatic: false,
        noOpSuccess: false,
        dataChanged: true,
      ),
      isFalse,
    );
    expect(
      shouldRecordWebDavAttempt(
        ok: true,
        isWebDavActivity: true,
        automatic: false,
        noOpSuccess: true,
        dataChanged: false,
      ),
      isFalse,
    );
  });

  test('shouldRecordWebDavAttempt records failures and real auto success', () {
    expect(
      shouldRecordWebDavAttempt(
        ok: false,
        isWebDavActivity: true,
        automatic: true,
        noOpSuccess: false,
        dataChanged: false,
      ),
      isTrue,
    );
    expect(
      shouldRecordWebDavAttempt(
        ok: true,
        isWebDavActivity: true,
        automatic: true,
        noOpSuccess: false,
        dataChanged: false,
      ),
      isFalse,
    );
    expect(
      shouldRecordWebDavAttempt(
        ok: true,
        isWebDavActivity: true,
        automatic: true,
        noOpSuccess: false,
        dataChanged: true,
      ),
      isTrue,
    );
    expect(
      shouldRecordWebDavAttempt(
        ok: true,
        isWebDavActivity: true,
        automatic: false,
        noOpSuccess: false,
        dataChanged: false,
      ),
      isTrue,
    );
  });

  test('last-attempt labels are last result only', () {
    expect(lastSyncAttemptLabel(null), 'Not synced yet');
    final at = DateTime(2026, 9, 5, 11, 12);
    expect(
      lastSyncAttemptLabel(
        LastSyncAttempt(packageKey: 'catalog', ok: true, at: at),
      ),
      'Last succeeded ${formatPackageTime(at)}',
    );
    expect(
      lastSyncAttemptOverviewLabel(
        latest: LastSyncAttempt(packageKey: 'skills', ok: false, at: at),
        syncing: true,
      ),
      'Last failed ${formatPackageTime(at)} · Syncing…',
    );
  });

  test('LastSyncAttemptStore round-trips and latest wins', () async {
    SharedPreferences.setMockInitialValues({});
    final store = LastSyncAttemptStore();
    await store.record(
      LastSyncAttemptKeys.catalog,
      ok: true,
      at: DateTime.utc(2026, 9, 5, 1),
    );
    await store.record(
      LastSyncAttemptKeys.skills,
      ok: false,
      at: DateTime.utc(2026, 9, 5, 3),
    );
    final other = LastSyncAttemptStore();
    await other.load();
    expect(other.get(LastSyncAttemptKeys.catalog)?.ok, isTrue);
    expect(other.get(LastSyncAttemptKeys.skills)?.ok, isFalse);
    expect(other.latest()?.packageKey, LastSyncAttemptKeys.skills);
    expect(other.toStatusJson()[LastSyncAttemptKeys.skills], isA<Map>());
  });
}
