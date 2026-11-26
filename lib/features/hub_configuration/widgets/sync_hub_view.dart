import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../common/app_locale.dart';
import '../../../common/app_theme.dart';
import '../../../controllers/hub_controller.dart';
import '../../../features/operation_logs/operation_logs.dart';
import '../../../features/skill_sync/skill_sync.dart';
import '../../../services/mcp_paths.dart';
import 'catalog_sync_card.dart';
import 'folder_resource_sync_card.dart';
import 'hub_configuration_bulk_card.dart';
import 'section_header.dart';

/// 「同步中心」主视图：顶部 KPI 概览 + 三步同步流程 + 清单与文件夹资源矩阵 + 最近日志。
class SyncHubView extends StatelessWidget {
  const SyncHubView({
    super.key,
    required this.onOpenMcp,
    required this.onOpenLogs,
    required this.onOpenWebDavSettings,
  });

  final VoidCallback onOpenMcp;
  final VoidCallback onOpenLogs;
  final VoidCallback onOpenWebDavSettings;

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<HubController>();
    final counts = hub.cursorItemCounts;
    final latestLog = hub.operationLogs.latest;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final kpis = [
      _KpiTile(
        icon: Icons.dns_outlined,
        label: tr('MCP 服务', 'MCP Servers'),
        value: tr('${hub.servers.length} 个', '${hub.servers.length}'),
        subtitle: tr('Cursor 已写入 ${counts.mcp}', '${counts.mcp} in Cursor'),
        accentColor: scheme.primary,
        onTap: onOpenMcp,
      ),
      _KpiTile(
        icon: Icons.layers_outlined,
        label: tr('Cursor 文件夹资源', 'Folder Resources'),
        value:
            '${counts.forResource(AgentResourceKind.skill)} / ${counts.forResource(AgentResourceKind.command)} / ${counts.forResource(AgentResourceKind.rule)} / ${counts.forResource(AgentResourceKind.hook)}',
        subtitle: 'Skill · Cmd · Rule · Hook',
        accentColor: scheme.primary,
      ),
      _KpiTile(
        icon: Icons.cloud_done_outlined,
        label: tr('WebDAV 云端', 'WebDAV Sync'),
        value: hub.isWebDavReady
            ? tr('已就绪', 'Ready')
            : tr('未启用', 'Not set'),
        subtitle: hub.isWebDavReady
            ? tr('支持下载 / 合并 / 上传', 'Download · Merge · Upload')
            : tr('点击配置服务器', 'Click to configure'),
        accentColor: hub.isWebDavReady
            ? AppTheme.success(context)
            : scheme.onSurfaceVariant,
        onTap: onOpenWebDavSettings,
      ),
      _KpiTile(
        icon: Icons.history,
        label: tr('最近操作', 'Latest Activity'),
        value: latestLog == null ? tr('暂无记录', 'No activity') : latestLog.status.label,
        subtitle: latestLog == null
            ? tr('点击打开日志中心', 'Click to open logs')
            : '${latestLog.action} · ${latestLog.formattedTime.substring(5, 16)}',
        accentColor: latestLog == null
            ? scheme.onSurfaceVariant
            : switch (latestLog.status) {
                OperationLogStatus.success => AppTheme.success(context),
                OperationLogStatus.partial => AppTheme.warning(context),
                OperationLogStatus.failure => scheme.error,
              },
        onTap: onOpenLogs,
      ),
    ];

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(28, 22, 28, 32),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('同步中心', 'Sync Hub'),
                        style: theme.textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tr(
                          '管理 MCP 清单与 Skill / Command / Rule / Hook 的云端同步、本地应用及跨客户端转换。',
                          'Manage cloud sync, local apply, and cross-client conversion for Catalog and Folder resources.',
                        ),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: hub.refreshCursorItemCounts,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text(tr('刷新计数', 'Refresh')),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 820 ? 4 : 2;
                final width =
                    (constraints.maxWidth - 12 * (columns - 1)) / columns;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final tile in kpis)
                      SizedBox(width: width, child: tile),
                  ],
                );
              },
            ),
            const SizedBox(height: 18),
            const HubConfigurationBulkCard(),
            const SizedBox(height: 20),
            SectionHeader(tr('配置与资源明细', 'Catalog & Folder Resources')),
            const SizedBox(height: 10),
            CatalogSyncCard(onOpenMcpSettings: onOpenMcp),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final twoColumns = constraints.maxWidth >= 780;
                final cardWidth = twoColumns
                    ? (constraints.maxWidth - 12) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final resource in AgentResourceKind.values)
                      SizedBox(
                        width: cardWidth,
                        child: FolderResourceSyncCard(resource: resource),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            SectionHeader(tr('最近动态', 'Recent Activity')),
            const SizedBox(height: 10),
            RecentOperationLogsCard(onViewAll: onOpenLogs),
            const SizedBox(height: 16),
            Text(
              tr(
                '数据目录：${McpPaths.hubDataRoot ?? "(不可用)"}',
                'Data directory: ${McpPaths.hubDataRoot ?? "(unavailable)"}',
              ),
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.subtitle,
    required this.accentColor,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final String subtitle;
  final Color accentColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 15, color: accentColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      label,
                      style: theme.textTheme.labelSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: theme.textTheme.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
