import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../common/agent_platforms.dart';
import '../../../common/package_time.dart';
import '../../../controllers/hub_controller.dart';
import '../../../features/sync_status/sync_status.dart';
import '../../../widgets/hub_notice/hub_notice.dart';
import '../../../widgets/op_status/op_status.dart';
import '../../../widgets/sync_confirm/sync_confirm.dart';
import 'directory_path_row.dart';

class CatalogSyncCard extends StatelessWidget {
  const CatalogSyncCard({super.key, required this.onOpenMcpSettings});

  final VoidCallback onOpenMcpSettings;

  Future<void> _run(
    BuildContext context,
    HubController hub,
    Future<void> Function() action,
  ) async {
    await action();
    if (!context.mounted) return;
    showHubNotice(
      context,
      message: hub.lastMessage ?? 'Complete',
      ok: hub.lastMessage?.contains('failed') == true ? false : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<HubController>();
    final counts = hub.cursorItemCounts;
    final supported = hub.isDesktopSupported;
    final webDavReady = hub.isWebDavReady;
    final busy = hub.isSyncBusy;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CircleAvatar(child: Icon(Icons.hub_outlined)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'MCP',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          CursorCountChip(
                            count: counts.mcp,
                            tooltip: '${counts.mcp} MCPs in Cursor',
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      SyncAttemptStatus(
                        attempt: hub.syncAttempts.get(
                          LastSyncAttemptKeys.catalog,
                        ),
                        versionLabel: supported && webDavReady
                            ? currentPackageVersionLabel(
                                hub.webDavSync.catalogUploadedAt,
                              )
                            : null,
                        syncing: busy && hub.isWebDavSyncing,
                        unavailableLabel: !supported
                            ? 'Writing MCP configuration is not supported on this platform'
                            : (webDavReady
                                  ? null
                                  : 'WebDAV is not ready; client configuration can still be updated'),
                      ),
                    ],
                  ),
                ),
              ],
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
                          final confirmed = await confirmCatalogReplace(
                            context,
                            loadRemoteUploadedAt:
                                hub.peekRemoteCatalogUploadedAt,
                          );
                          if (!confirmed || !context.mounted) return;
                          await _run(context, hub, hub.pullWebDavNow);
                        },
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: const Text('Download'),
                ),
                OutlinedButton.icon(
                  onPressed: !supported || !webDavReady || busy
                      ? null
                      : () async {
                          final confirmed = await confirmCatalogMerge(context);
                          if (!confirmed || !context.mounted) return;
                          await _run(context, hub, hub.mergeWebDavNow);
                        },
                  icon: const Icon(Icons.merge_outlined),
                  label: const Text('Merge'),
                ),
                FilledButton.tonalIcon(
                  onPressed: !supported || busy
                      ? null
                      : () async {
                          final confirmed = await confirmWriteToClients(
                            context,
                          );
                          if (!confirmed || !context.mounted) return;
                          final result = await hub.configureAllClients();
                          if (!context.mounted) return;
                          showHubNotice(
                            context,
                            message: result.message,
                            ok: result.ok,
                          );
                        },
                  icon: const Icon(Icons.install_desktop_outlined),
                  label: const Text('Write to Clients'),
                ),
                OutlinedButton.icon(
                  onPressed: !supported || !webDavReady || busy
                      ? null
                      : () async {
                          final confirmed = await confirmRemoteOverwrite(
                            context,
                            scope: 'Catalog',
                          );
                          if (!confirmed || !context.mounted) return;
                          await _run(context, hub, hub.pushWebDavNow);
                        },
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('Upload'),
                ),
              ],
            ),
            OpStatusBar(
              progress: hub.isWebDavSyncing ? hub.webDavSync.progress : null,
              errorMessage: busy ? null : hub.webDavSync.lastError,
            ),
            const Divider(height: 24),
            FilledButton.tonalIcon(
              onPressed: onOpenMcpSettings,
              icon: const Icon(Icons.tune_outlined),
              label: const Text('Open MCP Settings'),
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: const Text('View Configuration Directories'),
              children: [
                for (final platform in AgentPlatforms.mcpConfigurable)
                  DirectoryPathRow(
                    label: platform.label,
                    displayPath: platform.mcpConfigFilePath,
                    directoryPath: platform.mcpConfigDirectoryPath,
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

Future<bool> confirmWriteToClients(BuildContext context) async {
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Write to clients?'),
          content: const Text(
            'This will write all current MCPs to Cursor and Codex configuration.\n\n'
            'MCPs with matching names will be updated; other client-managed services will be preserved.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Confirm write'),
            ),
          ],
        ),
      ) ??
      false;
}
