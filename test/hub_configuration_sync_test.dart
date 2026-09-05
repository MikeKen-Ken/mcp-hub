import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_hub/features/hub_configuration/hub_configuration_result.dart';
import 'package:mcp_hub/features/skill_sync/skill_sync_result.dart';

void main() {
  test('combine fails if Catalog fails even when Folder resources succeed', () {
    final result = combineHubConfigurationPacks(
      catalogOk: false,
      catalogMessage: 'Catalog failed: net',
      folders: const SkillSyncResult(ok: true, message: 'Folders ok'),
    );
    expect(result.ok, isFalse);
    expect(result.message, contains('Catalog failed: net'));
    expect(result.message, contains('Folders ok'));
  });

  test(
    'runHubConfigurationPacks still runs Folder resources after Catalog fails',
    () async {
      var foldersRan = false;
      final result = await runHubConfigurationPacks(
        catalog: () async => (ok: false, message: 'Catalog failed: net'),
        folders: () async {
          foldersRan = true;
          return const SkillSyncResult(ok: true, message: 'Folders ok');
        },
      );
      expect(foldersRan, isTrue);
      expect(result.ok, isFalse);
    },
  );

  test(
    'runHubConfigurationPacks still runs Folder resources after Catalog throws',
    () async {
      var foldersRan = false;
      final result = await runHubConfigurationPacks(
        catalog: () async => throw StateError('catalog boom'),
        folders: () async {
          foldersRan = true;
          return const SkillSyncResult(ok: true, message: 'Folders ok');
        },
      );
      expect(foldersRan, isTrue);
      expect(result.ok, isFalse);
      expect(result.message, contains('catalog boom'));
      expect(result.message, contains('Folders ok'));
    },
  );

  test(
    'runHubConfigurationPacks succeeds only when both packs succeed',
    () async {
      final result = await runHubConfigurationPacks(
        catalog: () async => (ok: true, message: 'Catalog ok'),
        folders: () async =>
            const SkillSyncResult(ok: true, message: 'Folders ok'),
      );
      expect(result.ok, isTrue);
      expect(result.message, 'Catalog ok\nFolders ok');
    },
  );
}
