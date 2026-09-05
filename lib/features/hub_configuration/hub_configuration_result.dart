import '../skill_sync/skill_sync_result.dart';

/// One Download / Merge / Upload of Hub configuration (Catalog plus Folder resources).
class HubConfigurationResult {
  const HubConfigurationResult({required this.ok, required this.message});

  final bool ok;
  final String message;
}

({bool ok, String message}) catalogPackOutcome({
  required bool ok,
  required String successMessage,
  required String? error,
}) {
  if (ok) return (ok: true, message: successMessage);
  return (ok: false, message: 'Catalog failed: ${error ?? 'Unknown error'}');
}

HubConfigurationResult combineHubConfigurationPacks({
  required bool catalogOk,
  required String catalogMessage,
  required SkillSyncResult folders,
}) {
  return HubConfigurationResult(
    ok: catalogOk && folders.ok,
    message: '$catalogMessage\n${folders.message}',
  );
}

/// Run Catalog then Folder resources. Continue after a Catalog error. No rollback.
Future<HubConfigurationResult> runHubConfigurationPacks({
  required Future<({bool ok, String message})> Function() catalog,
  required Future<SkillSyncResult> Function() folders,
}) async {
  var catalogOk = false;
  var catalogMessage = 'Catalog did not run';
  try {
    final outcome = await catalog();
    catalogOk = outcome.ok;
    catalogMessage = outcome.message;
  } catch (error) {
    catalogMessage = 'Catalog failed: $error';
  }

  late final SkillSyncResult folderResult;
  try {
    folderResult = await folders();
  } catch (error) {
    folderResult = SkillSyncResult(
      ok: false,
      message: 'Folder resources failed: $error',
    );
  }

  return combineHubConfigurationPacks(
    catalogOk: catalogOk,
    catalogMessage: catalogMessage,
    folders: folderResult,
  );
}
