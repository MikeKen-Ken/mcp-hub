import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../common/app_locale.dart';
import '../../../controllers/hub_controller.dart';
import '../../../features/skill_sync/skill_sync.dart';
import '../../../services/mcp_paths.dart';
import '../../../webdav/webdav_sync_service.dart';
import '../../../widgets/hub_notice/hub_notice.dart';
import '../../../widgets/op_status/op_status.dart';
import '../../../widgets/sync_confirm/sync_confirm.dart';
import 'directory_path_row.dart';

class HubConfigurationBulkCard extends StatelessWidget {
  const HubConfigurationBulkCard({super.key});

  Future<void> _run(
    BuildContext context,
    Future<({bool ok, String message})> Function() action,
  ) async {
    final result = await action();
    if (!context.mounted) return;
    showHubNotice(context, message: result.message, ok: result.ok);
  }

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<HubController>();
    final supported = hub.isDesktopSupported;
    final webDavReady = hub.isWebDavReady;
    final busy = hub.isSyncBusy;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr('Hub 配置', 'Hub configuration'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              tr(
                '下载、合并和上传会同时处理 MCP 清单与文件夹资源；应用和转换仅处理文件夹资源。',
                'Download, merge, and upload move Catalog and Folder resources. Apply and Convert are Folder resources only.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: !supported || !webDavReady || busy
                      ? null
                      : () async {
                          final confirmed =
                              await confirmHubConfigurationDownload(
                                context,
                                loadCatalogUploadedAt:
                                    hub.peekRemoteCatalogUploadedAt,
                                folderPackages: [
                                  for (final resource
                                      in AgentResourceKind.values)
                                    RemotePackageDateQuery(
                                      label: resource.label,
                                      load: () =>
                                          hub.peekRemoteResourceUploadedAt(
                                            resource,
                                          ),
                                    ),
                                ],
                              );
                          if (!confirmed || !context.mounted) return;
                          await _run(context, () async {
                            final result = await hub.hubConfiguration
                                .download();
                            return (ok: result.ok, message: result.message);
                          });
                        },
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: Text(tr('下载 Hub 配置', 'Download Hub configuration')),
                ),
                OutlinedButton.icon(
                  onPressed: !supported || !webDavReady || busy
                      ? null
                      : () async {
                          final confirmed = await confirmHubConfigurationMerge(
                            context,
                          );
                          if (!confirmed || !context.mounted) return;
                          await _run(context, () async {
                            final result = await hub.hubConfiguration.merge();
                            return (ok: result.ok, message: result.message);
                          });
                        },
                  icon: const Icon(Icons.merge_outlined),
                  label: Text(tr('合并 Hub 配置', 'Merge Hub configuration')),
                ),
                FilledButton.icon(
                  onPressed: !supported || busy
                      ? null
                      : () async {
                          final confirmed = await confirmFolderResourcesApply(
                            context,
                          );
                          if (!confirmed || !context.mounted) return;
                          await _run(context, () async {
                            final result = await hub
                                .applyAllResourcesFromCache();
                            return (ok: result.ok, message: result.message);
                          });
                        },
                  icon: const Icon(Icons.install_desktop_outlined),
                  label: Text(tr('应用文件夹资源', 'Apply Folder resources')),
                ),
                OutlinedButton.icon(
                  onPressed: !supported || !webDavReady || busy
                      ? null
                      : () async {
                          final confirmed = await confirmRemoteOverwrite(
                            context,
                            scope: tr(
                              'Hub 配置（MCP 清单与文件夹资源）',
                              'Hub configuration (Catalog and Folder resources)',
                            ),
                          );
                          if (!confirmed || !context.mounted) return;
                          await _run(context, () async {
                            final result = await hub.hubConfiguration.upload();
                            return (ok: result.ok, message: result.message);
                          });
                        },
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: Text(tr('上传 Hub 配置', 'Upload Hub configuration')),
                ),
                FilledButton.icon(
                  onPressed: !supported || busy
                      ? null
                      : () => _run(context, () async {
                          final result = await hub
                              .convertAllResourcesFromCursor();
                          return (ok: result.ok, message: result.message);
                        }),
                  icon: const Icon(Icons.transform_outlined),
                  label: Text(tr('转换文件夹资源', 'Convert Folder resources')),
                ),
              ],
            ),
            OpStatusBar(
              progress: hub.hubConfiguration.busy && hub.isWebDavSyncing
                  ? hub.webDavSync.progress
                  : (hub.skillSync.status == SkillSyncStatus.syncing &&
                            hub.skillSync.lastResource == null
                        ? hub.skillSync.progress
                        : null),
              errorMessage: busy
                  ? null
                  : [
                      if (hub.webDavSync.status == CatalogSyncStatus.error)
                        hub.webDavSync.lastError,
                      hub.skillSync.failureFor(null),
                    ].whereType<String>().join('\n'),
            ),
            const Divider(height: 24),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: Text(tr('查看缓存目录', 'View Cache Directories')),
              children: [
                DirectoryPathRow(
                  label: tr('Skill 缓存根目录', 'Skill cache root'),
                  displayPath: McpPaths.skillsCacheRoot,
                  directoryPath: McpPaths.skillsCacheRoot,
                  enabled: supported,
                ),
                DirectoryPathRow(
                  label: tr('其他资源缓存根目录', 'Other resource cache root'),
                  displayPath: McpPaths.agentResourcesCacheRoot,
                  directoryPath: McpPaths.agentResourcesCacheRoot,
                  enabled: supported,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<bool> confirmFolderResourcesApply(BuildContext context) async {
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(tr('确认应用文件夹资源？', 'Apply Folder resources?')),
          content: Text(
            tr(
              '这会把缓存中的文件夹资源全量镜像写入 Cursor 正式目录。\n\n'
                  '缓存中缺失的本地 Cursor 文件与目录也会被删除。\n\n'
                  '此操作不会把 MCP 清单写入客户端配置；如需写入 MCP 请使用「写入客户端」。\n\n'
                  '此操作也不会自动转换 Codex / OpenCode；如需转换请使用「转换文件夹资源」。',
              'This will mirror the cached Folder resources into the official Cursor directories.\n\n'
                  'Local Cursor files and directories missing from the cache will also be deleted.\n\n'
                  'This does not write the Catalog into Client MCP config. Use Write to Clients for MCP.\n\n'
                  'This does not convert Codex / OpenCode; use Convert Folder resources when needed.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(tr('取消', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(tr('确认应用', 'Confirm apply')),
            ),
          ],
        ),
      ) ??
      false;
}
