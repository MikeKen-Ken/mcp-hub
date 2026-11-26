import '../../common/app_locale.dart';
import '../../common/package_time.dart';
import '../../webdav/webdav_sync_service.dart';
import '../skill_sync/skill_sync_service.dart';
import 'hub_configuration_result.dart';

Future<HubConfigurationResult> downloadHubConfigurationPacks({
  required WebDavSyncService webDav,
  required SkillSyncService skillSync,
}) {
  return runHubConfigurationPacks(
    catalog: () async {
      await webDav.pullNow();
      return catalogPackOutcome(
        ok: webDav.status == CatalogSyncStatus.success,
        successMessage: webDav.catalogUploadedAt == null
            ? tr('已下载并替换 MCP 清单', 'Downloaded and replaced the Catalog')
            : tr(
                '已下载并替换 MCP 清单（远端版本 ${formatPackageTime(webDav.catalogUploadedAt)}）',
                'Downloaded and replaced the Catalog (remote version ${formatPackageTime(webDav.catalogUploadedAt)})',
              ),
        error: webDav.lastError,
      );
    },
    folders: skillSync.syncAllResourcesFromWebDav,
  );
}

Future<HubConfigurationResult> mergeHubConfigurationPacks({
  required WebDavSyncService webDav,
  required SkillSyncService skillSync,
}) {
  return runHubConfigurationPacks(
    catalog: () async {
      await webDav.mergeNow();
      return catalogPackOutcome(
        ok: webDav.status == CatalogSyncStatus.success,
        successMessage: tr('已合并 MCP 清单', 'Merged the Catalog'),
        error: webDav.lastError,
      );
    },
    folders: skillSync.mergeAllResourcesFromWebDav,
  );
}

Future<HubConfigurationResult> uploadHubConfigurationPacks({
  required WebDavSyncService webDav,
  required SkillSyncService skillSync,
}) {
  return runHubConfigurationPacks(
    catalog: () async {
      await webDav.pushNow();
      return catalogPackOutcome(
        ok: webDav.status == CatalogSyncStatus.success,
        successMessage: tr('已上传 MCP 清单', 'Uploaded the Catalog'),
        error: webDav.lastError,
      );
    },
    folders: skillSync.pushAllResourcesToWebDav,
  );
}
