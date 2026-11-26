import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../common/app_locale.dart';
import '../../../common/app_theme.dart';
import '../../../controllers/hub_controller.dart';
import '../../../features/skill_sync/skill_sync.dart';
import '../../../services/mcp_paths.dart';
import '../../../webdav/webdav_sync_service.dart';
import '../../../widgets/hub_notice/hub_notice.dart';
import '../../../widgets/op_status/op_status.dart';
import '../../../widgets/sync_confirm/sync_confirm.dart';
import 'directory_path_row.dart';

/// 同步中心顶部的三步可视化工作流卡片：云端同步 → 应用到本地（Cursor）→ 分发全平台。
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

    final step1 = _PipelineStage(
      stepNumber: '1',
      title: tr('云端同步（WebDAV）', 'Cloud Sync (WebDAV)'),
      subtitle: tr('云端 ↔ 本地缓存', 'Remote ↔ Local cache'),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          FilledButton.tonalIcon(
            onPressed: !supported || !webDavReady || busy
                ? null
                : () async {
                    final confirmed = await confirmHubConfigurationDownload(
                      context,
                      loadCatalogUploadedAt: hub.peekRemoteCatalogUploadedAt,
                      folderPackages: [
                        for (final resource in AgentResourceKind.values)
                          RemotePackageDateQuery(
                            label: resource.label,
                            load: () =>
                                hub.peekRemoteResourceUploadedAt(resource),
                          ),
                      ],
                    );
                    if (!confirmed || !context.mounted) return;
                    await _run(context, () async {
                      final result = await hub.hubConfiguration.download();
                      return (ok: result.ok, message: result.message);
                    });
                  },
            icon: const Icon(Icons.cloud_download_outlined, size: 16),
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
            icon: const Icon(Icons.merge_outlined, size: 16),
            label: Text(tr('合并 Hub 配置', 'Merge Hub configuration')),
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
            icon: const Icon(Icons.cloud_upload_outlined, size: 16),
            label: Text(tr('上传 Hub 配置', 'Upload Hub configuration')),
          ),
        ],
      ),
    );

    final step2 = _PipelineStage(
      stepNumber: '2',
      title: tr('应用到本地（Cursor）', 'Apply Locally (Cursor)'),
      subtitle: tr('本地缓存 → Cursor 正式目录', 'Cache → Official Cursor'),
      child: FilledButton.icon(
        onPressed: !supported || busy
            ? null
            : () async {
                final confirmed = await confirmFolderResourcesApply(context);
                if (!confirmed || !context.mounted) return;
                await _run(context, () async {
                  final result = await hub.applyAllResourcesFromCache();
                  return (ok: result.ok, message: result.message);
                });
              },
        icon: const Icon(Icons.install_desktop_outlined, size: 16),
        label: Text(tr('应用文件夹资源', 'Apply Folder resources')),
      ),
    );

    final step3 = _PipelineStage(
      stepNumber: '3',
      title: tr('分发全平台', 'Distribute to Clients'),
      subtitle: tr(
        'Cursor → Codex / OpenCode / Antigravity 等',
        'Cursor → Codex / OpenCode / Antigravity',
      ),
      child: FilledButton.icon(
        onPressed: !supported || busy
            ? null
            : () => _run(context, () async {
                final result = await hub.convertAllResourcesFromCursor();
                return (ok: result.ok, message: result.message);
              }),
        icon: const Icon(Icons.transform_outlined, size: 16),
        label: Text(tr('转换文件夹资源', 'Convert Folder resources')),
      ),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('三步批量同步流程', 'Three-Step Sync Pipeline'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        tr(
                          '第 1 步同步 MCP 清单与文件夹资源缓存；第 2、3 步将文件夹资源落地到 Cursor 并分发给其他客户端。',
                          'Step 1 syncs Catalog & Folder caches; Steps 2–3 apply Folder resources to Cursor and distribute across clients.',
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 780) {
                  return IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 5, child: step1),
                        const _PipelineArrow(horizontal: true),
                        Expanded(flex: 3, child: step2),
                        const _PipelineArrow(horizontal: true),
                        Expanded(flex: 3, child: step3),
                      ],
                    ),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    step1,
                    const _PipelineArrow(horizontal: false),
                    step2,
                    const _PipelineArrow(horizontal: false),
                    step3,
                  ],
                );
              },
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
            const SizedBox(height: 10),
            const Divider(),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 6),
              title: Text(
                tr('查看缓存目录', 'View Cache Directories'),
                style: Theme.of(context).textTheme.labelLarge,
              ),
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

class _PipelineStage extends StatelessWidget {
  const _PipelineStage({
    required this.stepNumber,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String stepNumber;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.subtleBg(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.hairline(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  stepNumber,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: theme.textTheme.bodySmall),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _PipelineArrow extends StatelessWidget {
  const _PipelineArrow({required this.horizontal});

  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant.withValues(
      alpha: 0.45,
    );
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: horizontal ? 4 : 0,
        vertical: horizontal ? 0 : 4,
      ),
      child: Center(
        child: Icon(
          horizontal ? Icons.arrow_forward : Icons.arrow_downward,
          size: 16,
          color: color,
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
