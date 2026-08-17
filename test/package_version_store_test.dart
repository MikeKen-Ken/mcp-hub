import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_hub/common/package_time.dart';
import 'package:mcp_hub/webdav/package_version_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('formatPackageTime 使用本地时区精确到分钟', () {
    final time = DateTime(2026, 8, 17, 9, 5, 33);
    expect(formatPackageTime(time), '2026-08-17 09:05');
    expect(formatPackageTime(null), '未知');
    expect(currentPackageVersionLabel(null), '当前版本：尚未记录');
    expect(dateTimeFromEpochMs(0), isNull);
  });

  test('PackageVersionStore 可往返保存上传时间', () async {
    SharedPreferences.setMockInitialValues({});
    final store = PackageVersionStore();
    final uploaded = DateTime.utc(2026, 8, 17, 1, 30);
    await store.save('skills', uploaded);
    final other = PackageVersionStore();
    await other.load();
    expect(other.get('skills')?.toUtc(), uploaded);
  });
}
