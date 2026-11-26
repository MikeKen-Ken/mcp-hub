import '../../common/app_locale.dart';
import '../skill_sync/skill_sync_result.dart';

/// One Download / Merge / Upload of Hub configuration (Catalog plus Folder resources).
class HubConfigurationResult {
  const HubConfigurationResult({
    required this.ok,
    required this.message,
    this.partial = false,
  });

  final bool ok;
  final String message;
  final bool partial;
}

({bool ok, String message}) catalogPackOutcome({
  required bool ok,
  required String successMessage,
  required String? error,
}) {
  if (ok) return (ok: true, message: successMessage);
  return (
    ok: false,
    message: tr(
      'MCP 清单失败：${error ?? tr('未知错误', 'Unknown error')}',
      'Catalog failed: ${error ?? 'Unknown error'}',
    ),
  );
}

HubConfigurationResult combineHubConfigurationPacks({
  required bool catalogOk,
  required String catalogMessage,
  required SkillSyncResult folders,
}) {
  final allOk = catalogOk && folders.ok;
  return HubConfigurationResult(
    ok: allOk,
    partial: !allOk && (catalogOk || folders.ok),
    message: '$catalogMessage\n${folders.message}',
  );
}

/// Run Catalog then Folder resources. Continue after a Catalog error. No rollback.
Future<HubConfigurationResult> runHubConfigurationPacks({
  required Future<({bool ok, String message})> Function() catalog,
  required Future<SkillSyncResult> Function() folders,
}) async {
  var catalogOk = false;
  var catalogMessage = tr('MCP 清单未执行', 'Catalog did not run');
  try {
    final outcome = await catalog();
    catalogOk = outcome.ok;
    catalogMessage = outcome.message;
  } catch (error) {
    catalogMessage = tr('MCP 清单失败：$error', 'Catalog failed: $error');
  }

  late final SkillSyncResult folderResult;
  try {
    folderResult = await folders();
  } catch (error) {
    folderResult = SkillSyncResult(
      ok: false,
      message: tr('文件夹资源失败：$error', 'Folder resources failed: $error'),
    );
  }

  return combineHubConfigurationPacks(
    catalogOk: catalogOk,
    catalogMessage: catalogMessage,
    folders: folderResult,
  );
}
