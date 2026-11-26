import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../common/agent_platforms.dart';
import '../../../common/app_locale.dart';
import '../../../common/app_theme.dart';
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
    final msg = hub.lastMessage ?? tr('完成', 'Complete');
    final failed = msg.contains('失败') || msg.toLowerCase().contains('failed');
    showHubNotice(context, message: msg, ok: failed ? false : null);
  }

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<HubController>();
    final counts = hub.cursorItemCounts;
    final supported = hub.isDesktopSupported;
    final webDavReady = hub.isWebDavReady;
    final busy = hub.isSyncBusy;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cloudStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 30),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    );

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
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: scheme.primary.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Icon(
                    Icons.hub_outlined,
                    size: 18,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              tr('MCP 清单', 'MCP Catalog'),
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          CursorCountChip(
                            count: counts.mcp,
                            tooltip: tr(
                              'Cursor 中已有 ${counts.mcp} 个 MCP',
                              '${counts.mcp} MCPs in Cursor',
                            ),
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
                            ? tr(
                                '当前平台不支持写入 MCP 配置',
                                'Writing MCP configuration is not supported on this platform',
                              )
                            : (webDavReady
                                  ? null
                                  : tr(
                                      'WebDAV 尚未就绪，仍可本地写入客户端配置',
                                      'WebDAV is not ready; client configuration can still be updated',
                                    )),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
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
                  icon: const Icon(Icons.install_desktop_outlined, size: 16),
                  label: Text(tr('写入客户端', 'Write to Clients')),
                ),
                OutlinedButton.icon(
                  onPressed: onOpenMcpSettings,
                  icon: const Icon(Icons.tune_outlined, size: 16),
                  label: Text(tr('管理 MCP 服务', 'Manage MCP Servers')),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.subtleBg(context),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.hairline(context)),
              ),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    tr('云端：', 'Cloud:'),
                    style: theme.textTheme.labelSmall,
                  ),
                  OutlinedButton.icon(
                    style: cloudStyle,
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
                    icon: const Icon(Icons.cloud_download_outlined, size: 15),
                    label: Text(tr('下载', 'Download')),
                  ),
                  OutlinedButton.icon(
                    style: cloudStyle,
                    onPressed: !supported || !webDavReady || busy
                        ? null
                        : () async {
                            final confirmed = await confirmCatalogMerge(
                              context,
                            );
                            if (!confirmed || !context.mounted) return;
                            await _run(context, hub, hub.mergeWebDavNow);
                          },
                    icon: const Icon(Icons.merge_outlined, size: 15),
                    label: Text(tr('合并', 'Merge')),
                  ),
                  OutlinedButton.icon(
                    style: cloudStyle,
                    onPressed: !supported || !webDavReady || busy
                        ? null
                        : () async {
                            final confirmed = await confirmRemoteOverwrite(
                              context,
                              scope: tr('MCP 清单', 'Catalog'),
                            );
                            if (!confirmed || !context.mounted) return;
                            await _run(context, hub, hub.pushWebDavNow);
                          },
                    icon: const Icon(Icons.cloud_upload_outlined, size: 15),
                    label: Text(tr('上传', 'Upload')),
                  ),
                ],
              ),
            ),
            OpStatusBar(
              progress: hub.isWebDavSyncing ? hub.webDavSync.progress : null,
              errorMessage: busy ? null : hub.webDavSync.lastError,
            ),
            const SizedBox(height: 8),
            const Divider(),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 6),
              title: Text(
                tr('查看配置目录', 'View Configuration Directories'),
                style: theme.textTheme.labelLarge,
              ),
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
          title: Text(tr('确认写入客户端？', 'Write to clients?')),
          content: Text(
            tr(
              '这会把当前全部 MCP 写入已登记的客户端配置。\n\n'
                  '同名 MCP 会被更新，客户端里其他非 Hub 管理的服务会保留。',
              'This will write all current MCPs to Cursor and Codex configuration.\n\n'
                  'MCPs with matching names will be updated; other client-managed services will be preserved.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(tr('取消', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(tr('确认写入', 'Confirm write')),
            ),
          ],
        ),
      ) ??
      false;
}
