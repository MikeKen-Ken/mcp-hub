import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
              'Hub configuration',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Download, merge, and upload move Catalog and Folder resources. Apply and Convert are Folder resources only.',
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
                  label: const Text('Download Hub configuration'),
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
                  label: const Text('Merge Hub configuration'),
                ),
                FilledButton.tonalIcon(
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
                  label: const Text('Apply Folder resources'),
                ),
                OutlinedButton.icon(
                  onPressed: !supported || !webDavReady || busy
                      ? null
                      : () async {
                          final confirmed = await confirmRemoteOverwrite(
                            context,
                            scope:
                                'Hub configuration (Catalog and Folder resources)',
                          );
                          if (!confirmed || !context.mounted) return;
                          await _run(context, () async {
                            final result = await hub.hubConfiguration.upload();
                            return (ok: result.ok, message: result.message);
                          });
                        },
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('Upload Hub configuration'),
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
                  label: const Text('Convert Folder resources'),
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
              title: const Text('View Cache Directories'),
              children: [
                DirectoryPathRow(
                  label: 'Skill cache root',
                  displayPath: McpPaths.skillsCacheRoot,
                  directoryPath: McpPaths.skillsCacheRoot,
                  enabled: supported,
                ),
                DirectoryPathRow(
                  label: 'Other resource cache root',
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
          title: const Text('Apply Folder resources?'),
          content: const Text(
            'This will mirror the cached Folder resources into the official Cursor directories.\n\n'
            'Local Cursor files and directories missing from the cache will also be deleted.\n\n'
            'This does not write the Catalog into Client MCP config. Use Write to Clients for MCP.\n\n'
            'This does not convert Codex / OpenCode; use Convert Folder resources when needed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Confirm apply'),
            ),
          ],
        ),
      ) ??
      false;
}
