import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../common/agent_platforms.dart';
import '../common/package_time.dart';
import '../app_brand.dart';
import '../controllers/hub_controller.dart';
import '../features/app_update/app_update_screen.dart';
import '../features/skill_sync/skill_sync.dart';
import '../models/mcp_runtime_phase.dart';
import '../models/mcp_transport.dart';
import '../services/directory_opener.dart';
import '../services/hub_mcp_constants.dart';
import '../services/mcp_client_configurator.dart';
import '../services/mcp_paths.dart';
import '../widgets/hub_notice/hub_notice.dart';
import '../widgets/op_status/op_status.dart';
import '../widgets/status_badge.dart';
import '../widgets/sync_confirm/sync_confirm.dart';
import 'add_server_screen.dart';
import 'webdav_settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(maybePromptAppUpdate(context));
    });
  }

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<HubController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppBrand.displayName),
        actions: [
          IconButton(
            tooltip: 'WebDAV 设置',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const WebDavSettingsScreen(),
                ),
              );
            },
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(
            tooltip: '检查软件更新',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AppUpdateScreen(),
                ),
              );
            },
            icon: const Icon(Icons.upgrade),
          ),
        ],
      ),
      body: hub.loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                Text('配置中心', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  '集中查看 Agent Hub 状态，并进入常用管理功能。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const _SectionHeader('常用入口'),
                const SizedBox(height: 8),
                _AgentConfigHomeSection(hub: hub),
                const SizedBox(height: 20),
                Text(
                  '数据目录：${McpPaths.hubDataRoot ?? "(不可用)"}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
    );
  }
}

class _AgentConfigHomeSection extends StatelessWidget {
  const _AgentConfigHomeSection({required this.hub});

  final HubController hub;

  Future<void> _run(
    BuildContext context,
    Future<SkillSyncResult> Function() action,
  ) async {
    final result = await action();
    if (!context.mounted) return;
    showHubNotice(context, message: result.message, ok: result.ok);
  }

  @override
  Widget build(BuildContext context) {
    final supported = hub.isDesktopSupported;
    final webDavReady =
        hub.webDavConfig.enabled && hub.webDavConfig.isConfigured;
    final busy = hub.skillSync.status == SkillSyncStatus.syncing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader('Agent 配置'),
        const SizedBox(height: 8),
        _BulkResourceSyncCard(
          hub: hub,
          supported: supported,
          webDavReady: webDavReady,
          busy: busy,
          run: (action) => _run(context, action),
        ),
        const SizedBox(height: 16),
        const _SectionHeader('按资源管理'),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns = constraints.maxWidth >= 820;
            final cardWidth = twoColumns
                ? (constraints.maxWidth - 12) / 2
                : constraints.maxWidth;

            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: cardWidth,
                  child: _McpResourceSyncCard(hub: hub),
                ),
                for (final resource in AgentResourceKind.values)
                  SizedBox(
                    width: cardWidth,
                    child: _ResourceSyncCard(hub: hub, resource: resource),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title, style: Theme.of(context).textTheme.titleSmall);
  }
}

class ClientMcpScreen extends StatelessWidget {
  const ClientMcpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<HubController>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('客户端 MCP'),
        actions: [
          IconButton(
            tooltip: '刷新配置状态',
            onPressed: hub.refreshClientStatus,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('连接状态', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            '将全部 MCP 合并写入客户端配置，并查看本地 MCP 列表。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          _ClientConfigCard(hub: hub),
          const SizedBox(height: 24),
          const _SectionHeader('MCP 列表'),
          const SizedBox(height: 8),
          Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 10,
              ),
              leading: const Icon(Icons.storage_outlined),
              title: const Text('本地 MCP'),
              subtitle: Text('添加、启停和更新 MCP · 共 ${hub.servers.length} 个'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const LocalMcpScreen()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LocalMcpScreen extends StatelessWidget {
  const LocalMcpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<HubController>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('本地 MCP'),
        actions: [
          IconButton(
            tooltip: '全部更新',
            onPressed: hub.hasUpdatableServers
                ? () async {
                    await hub.updateAllServers();
                    if (!context.mounted) return;
                    showHubNotice(context, message: hub.lastMessage ?? '更新完成');
                  }
                : null,
            icon: const Icon(Icons.system_update_alt),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const AddServerScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('添加 MCP'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          Text(
            '开关决定该 MCP 是否写入 Cursor / Codex；内置 hubMCP 始终保留。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          ...hub.servers.map((server) => _ServerTile(serverId: server.id)),
        ],
      ),
    );
  }
}

class AgentConfigSyncScreen extends StatelessWidget {
  const AgentConfigSyncScreen({super.key});

  Future<void> _run(
    BuildContext context,
    Future<SkillSyncResult> Function() action,
  ) async {
    final result = await action();
    if (!context.mounted) return;
    showHubNotice(context, message: result.message, ok: result.ok);
  }

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<HubController>();
    final supported = hub.isDesktopSupported;
    final webDavReady =
        hub.webDavConfig.enabled && hub.webDavConfig.isConfigured;
    final busy = hub.skillSync.status == SkillSyncStatus.syncing;

    return Scaffold(
      appBar: AppBar(title: const Text('Agent 配置下载/上传')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final contentWidth = constraints.maxWidth.clamp(0, 1120).toDouble();
          final twoColumns = contentWidth >= 820;
          final cardWidth = twoColumns
              ? (contentWidth - 44) / 2
              : contentWidth - 32;

          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _AgentSyncOverview(
                        hub: hub,
                        supported: supported,
                        webDavReady: webDavReady,
                      ),
                      const SizedBox(height: 24),
                      const _SectionHeader('全部资源'),
                      const SizedBox(height: 8),
                      _BulkResourceSyncCard(
                        hub: hub,
                        supported: supported,
                        webDavReady: webDavReady,
                        busy: busy,
                        run: (action) => _run(context, action),
                      ),
                      const SizedBox(height: 24),
                      const _SectionHeader('按资源管理'),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          SizedBox(
                            width: cardWidth,
                            child: _McpResourceSyncCard(hub: hub),
                          ),
                          for (final resource in AgentResourceKind.values)
                            SizedBox(
                              width: cardWidth,
                              child: _ResourceSyncCard(
                                hub: hub,
                                resource: resource,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AgentSyncOverview extends StatelessWidget {
  const _AgentSyncOverview({
    required this.hub,
    required this.supported,
    required this.webDavReady,
  });

  final HubController hub;
  final bool supported;
  final bool webDavReady;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = switch (hub.skillSync.status) {
      SkillSyncStatus.idle => '尚未同步',
      SkillSyncStatus.syncing => '正在同步…',
      SkillSyncStatus.success => '最近同步成功',
      SkillSyncStatus.error => '最近同步失败',
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '同步流程',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                _SyncStatusPill(
                  icon: webDavReady
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_off_outlined,
                  label: supported && webDavReady ? 'WebDAV 已就绪' : 'WebDAV 未就绪',
                  active: supported && webDavReady,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const _FlowLabel(index: 1, label: '下载到缓存'),
                Icon(Icons.arrow_forward, size: 16, color: scheme.outline),
                const _FlowLabel(index: 2, label: '应用到 Cursor'),
                Icon(Icons.arrow_forward, size: 16, color: scheme.outline),
                const _FlowLabel(index: 3, label: '从 Cursor 上传'),
                const SizedBox(width: 4),
                _SyncStatusPill(
                  icon: hub.skillSync.status == SkillSyncStatus.error
                      ? Icons.error_outline
                      : Icons.history_outlined,
                  label: status,
                  active: hub.skillSync.status == SkillSyncStatus.success,
                  error: hub.skillSync.status == SkillSyncStatus.error,
                ),
              ],
            ),
            if (hub.skillSync.status == SkillSyncStatus.syncing ||
                (hub.skillSync.lastError != null &&
                    hub.skillSync.status == SkillSyncStatus.error))
              OpStatusBar(
                progress: hub.skillSync.status == SkillSyncStatus.syncing
                    ? hub.skillSync.progress
                    : null,
                errorMessage: hub.skillSync.status == SkillSyncStatus.error
                    ? hub.skillSync.lastError
                    : null,
              ),
          ],
        ),
      ),
    );
  }
}

class _FlowLabel extends StatelessWidget {
  const _FlowLabel({required this.index, required this.label});

  final int index;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 10,
            backgroundColor: scheme.primaryContainer,
            foregroundColor: scheme.onPrimaryContainer,
            child: Text(
              '$index',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
          const SizedBox(width: 7),
          Text(label),
        ],
      ),
    );
  }
}

class _SyncStatusPill extends StatelessWidget {
  const _SyncStatusPill({
    required this.icon,
    required this.label,
    required this.active,
    this.error = false,
  });

  final IconData icon;
  final String label;
  final bool active;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = error
        ? scheme.errorContainer
        : active
        ? scheme.secondaryContainer
        : scheme.surfaceContainerHighest;
    final fg = error ? scheme.onErrorContainer : null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg),
          ),
        ],
      ),
    );
  }
}

class _BulkResourceSyncCard extends StatelessWidget {
  const _BulkResourceSyncCard({
    required this.hub,
    required this.supported,
    required this.webDavReady,
    required this.busy,
    required this.run,
  });

  final HubController hub;
  final bool supported;
  final bool webDavReady;
  final bool busy;
  final Future<void> Function(Future<SkillSyncResult> Function() action) run;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('推荐流程', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: !supported || !webDavReady || busy
                      ? null
                      : () async {
                          final confirmed = await confirmRemoteDownload(
                            context,
                            title: '确认下载全部 Agent 配置？',
                            body:
                                '即将下载远端 Skill / Command / Rule / Hook 压缩包并覆盖本机缓存。\n\n'
                                '不会写入 Cursor 正式目录。',
                            packages: [
                              for (final resource in AgentResourceKind.values)
                                RemotePackageDateQuery(
                                  label: resource.label,
                                  load: () => hub.peekRemoteResourceUploadedAt(
                                    resource,
                                  ),
                                ),
                            ],
                          );
                          if (!confirmed || !context.mounted) return;
                          await run(hub.syncAllResourcesFromWebDav);
                        },
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: const Text('1  下载全部'),
                ),
                OutlinedButton.icon(
                  onPressed: !supported || !webDavReady || busy
                      ? null
                      : () => run(hub.mergeAllResourcesFromWebDav),
                  icon: const Icon(Icons.merge_outlined),
                  label: const Text('合并全部'),
                ),
                FilledButton.tonalIcon(
                  onPressed: !supported || busy
                      ? null
                      : () async {
                          final confirmed = await _confirmLocalOverwrite(
                            context,
                            scope: '全部 Agent 配置',
                          );
                          if (!confirmed || !context.mounted) return;
                          await run(hub.applyAllResourcesFromCache);
                        },
                  icon: const Icon(Icons.install_desktop_outlined),
                  label: const Text('2  应用到 Cursor'),
                ),
                OutlinedButton.icon(
                  onPressed: !supported || !webDavReady || busy
                      ? null
                      : () async {
                          final confirmed = await confirmRemoteOverwrite(
                            context,
                            scope: '全部 Agent 配置',
                          );
                          if (!confirmed || !context.mounted) return;
                          await run(hub.pushAllResourcesToWebDav);
                        },
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('3  上传全部'),
                ),
                FilledButton.icon(
                  onPressed: !supported || busy
                      ? null
                      : () => run(hub.convertAllResourcesFromCursor),
                  icon: const Icon(Icons.transform_outlined),
                  label: const Text('一键转换到全部目标'),
                ),
              ],
            ),
            OpStatusBar(
              progress: busy && hub.skillSync.lastResource == null
                  ? hub.skillSync.progress
                  : null,
              errorMessage: busy ? null : hub.skillSync.failureFor(null),
            ),
            const Divider(height: 24),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: const Text('查看缓存目录'),
              children: [
                _DirectoryPathRow(
                  label: 'Skill 缓存根目录',
                  displayPath: McpPaths.skillsCacheRoot,
                  directoryPath: McpPaths.skillsCacheRoot,
                  enabled: supported,
                ),
                _DirectoryPathRow(
                  label: '其他资源缓存根目录',
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

class _McpResourceSyncCard extends StatelessWidget {
  const _McpResourceSyncCard({required this.hub});

  final HubController hub;

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    final result = await action();
    if (!context.mounted) return;
    showHubNotice(
      context,
      message: hub.lastMessage ?? '完成',
      ok: hub.lastMessage?.contains('失败') == true ? false : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final supported = hub.isDesktopSupported;
    final webDavReady = hub.isWebDavReady;
    final busy = hub.isWebDavSyncing;

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
                      Text(
                        'MCP',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        supported
                            ? (webDavReady
                                  ? '${currentPackageVersionLabel(hub.webDavSync.catalogUploadedAt)} · 共 ${hub.servers.length} 个 MCP'
                                  : 'WebDAV 未就绪，仍可更新客户端配置')
                            : '当前平台不支持 MCP 配置写入',
                        style: Theme.of(context).textTheme.bodySmall,
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
                          await _run(context, hub.pullWebDavNow);
                        },
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: const Text('下载'),
                ),
                OutlinedButton.icon(
                  onPressed: !supported || !webDavReady || busy
                      ? null
                      : () => _run(context, hub.mergeWebDavNow),
                  icon: const Icon(Icons.merge_outlined),
                  label: const Text('合并'),
                ),
                FilledButton.tonalIcon(
                  onPressed: !supported
                      ? null
                      : () async {
                          final confirmed = await _confirmMcpConfigUpdate(
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
                  label: const Text('写入客户端'),
                ),
                OutlinedButton.icon(
                  onPressed: !supported || !webDavReady || busy
                      ? null
                      : () async {
                          final confirmed = await confirmRemoteOverwrite(
                            context,
                            scope: 'MCP 清单',
                          );
                          if (!confirmed || !context.mounted) return;
                          await _run(context, hub.pushWebDavNow);
                        },
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('上传'),
                ),
              ],
            ),
            OpStatusBar(
              progress: busy ? hub.webDavSync.progress : null,
              errorMessage: busy ? null : hub.webDavSync.lastError,
            ),
            const Divider(height: 24),
            FilledButton.tonalIcon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ClientMcpScreen(),
                ),
              ),
              icon: const Icon(Icons.tune_outlined),
              label: const Text('打开 MCP 设置'),
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: const Text('查看配置目录'),
              children: [
                for (final platform in AgentPlatforms.mcpConfigurable)
                  _DirectoryPathRow(
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

Future<bool> _confirmMcpConfigUpdate(BuildContext context) async {
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('确认写入客户端？'),
          content: const Text(
            '即将把当前全部 MCP 写入 Cursor 和 Codex 配置。\n\n'
            '会更新同名 MCP，但会保留客户端配置中不由 Agent Hub 管理的服务。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('确认写入'),
            ),
          ],
        ),
      ) ??
      false;
}

class _ResourceSyncCard extends StatelessWidget {
  const _ResourceSyncCard({required this.hub, required this.resource});

  final HubController hub;
  final AgentResourceKind resource;

  Future<void> _run(
    BuildContext context,
    Future<SkillSyncResult> Function() action,
  ) async {
    final result = await action();
    if (!context.mounted) return;
    showHubNotice(context, message: result.message, ok: result.ok);
  }

  @override
  Widget build(BuildContext context) {
    final supported = hub.isDesktopSupported;
    final webDavReady =
        hub.webDavConfig.enabled && hub.webDavConfig.isConfigured;
    final busy = hub.skillSync.status == SkillSyncStatus.syncing;
    final ownError = hub.skillSync.failureFor(resource);
    final thisBusy = busy && hub.skillSync.lastResource == resource;
    final statusText = thisBusy
        ? '进行中'
        : ownError != null
        ? '上次失败'
        : switch (hub.skillSync.status) {
            SkillSyncStatus.idle => '空闲',
            SkillSyncStatus.syncing => '空闲',
            SkillSyncStatus.success => '成功',
            SkillSyncStatus.error => '空闲',
          };
    final when = currentPackageVersionLabel(
      hub.skillSync.uploadedAtFor(resource),
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
                CircleAvatar(
                  child: Icon(switch (resource) {
                    AgentResourceKind.skill => Icons.auto_awesome_outlined,
                    AgentResourceKind.command => Icons.terminal_outlined,
                    AgentResourceKind.rule => Icons.rule_outlined,
                    AgentResourceKind.hook => Icons.account_tree_outlined,
                  }),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        resource.label,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        supported
                            ? (webDavReady
                                  ? '$statusText · $when'
                                  : 'WebDAV 未就绪，可使用本机转换')
                            : '当前平台不支持目录下载/上传',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (_canConvert)
                  const _SyncStatusPill(
                    icon: Icons.transform_outlined,
                    label: '支持转换',
                    active: true,
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
                          final confirmed = await confirmRemoteDownload(
                            context,
                            title: '确认下载远端 ${resource.label}？',
                            body:
                                '即将下载远端 ${resource.label} 压缩包并覆盖本机缓存。\n\n'
                                '不会写入 Cursor 正式目录。',
                            packages: [
                              RemotePackageDateQuery(
                                label: resource.label,
                                load: () =>
                                    hub.peekRemoteResourceUploadedAt(resource),
                              ),
                            ],
                          );
                          if (!confirmed || !context.mounted) return;
                          await _run(
                            context,
                            () => hub.syncResourceToAllTargets(resource),
                          );
                        },
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: const Text('下载'),
                ),
                OutlinedButton.icon(
                  onPressed: !supported || !webDavReady || busy
                      ? null
                      : () => _run(
                          context,
                          () => hub.mergeResourceToAllTargets(resource),
                        ),
                  icon: const Icon(Icons.merge_outlined),
                  label: const Text('合并'),
                ),
                FilledButton.tonalIcon(
                  onPressed: !supported || busy
                      ? null
                      : () async {
                          final confirmed = await _confirmLocalOverwrite(
                            context,
                            scope: resource.label,
                          );
                          if (!confirmed || !context.mounted) return;
                          await _run(
                            context,
                            () => hub.applyResourceFromCache(resource),
                          );
                        },
                  icon: const Icon(Icons.install_desktop_outlined),
                  label: const Text('应用到 Cursor'),
                ),
                OutlinedButton.icon(
                  onPressed: !supported || !webDavReady || busy
                      ? null
                      : () async {
                          final confirmed = await confirmRemoteOverwrite(
                            context,
                            scope: resource.label,
                          );
                          if (!confirmed || !context.mounted) return;
                          await _run(
                            context,
                            () => hub.pushResourceToAllTargets(resource),
                          );
                        },
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('上传'),
                ),
                if (_canConvert)
                  FilledButton.icon(
                    onPressed: !supported || busy
                        ? null
                        : () => _run(
                            context,
                            () => hub.convertResourceToAllTargets(resource),
                          ),
                    icon: const Icon(Icons.transform_outlined),
                    label: const Text('一键转换'),
                  ),
              ],
            ),
            OpStatusBar(
              progress: busy && hub.skillSync.lastResource == resource
                  ? hub.skillSync.progress
                  : null,
              errorMessage: busy ? null : hub.skillSync.failureFor(resource),
            ),
            const Divider(height: 24),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: const Text('查看目录与转换规则'),
              children: [
                if (_convertHint != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _convertHint!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                for (final target in SkillTarget.values)
                  _DirectoryPathRow(
                    label: target == SkillTarget.cursor
                        ? '${target.label}（正式目录）'
                        : '${target.label}（本机转换）',
                    displayPath: _pathLabelFor(target),
                    directoryPath: _directoryFor(target),
                    enabled: supported && resource.supportsLocalPath(target),
                  ),
                _DirectoryPathRow(
                  label: '缓存（Cursor）',
                  displayPath: McpPaths.resourceCachePath(
                    resource.wireName,
                    SkillTarget.cursor.wireName,
                  ),
                  directoryPath: McpPaths.resourceCachePath(
                    resource.wireName,
                    SkillTarget.cursor.wireName,
                  ),
                  enabled: supported,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String? get _convertHint => switch (resource) {
    AgentResourceKind.skill =>
      '一键转换：整包镜像后按格式转换（Codex：openai.yaml；Open Code：SKILL.md frontmatter）',
    AgentResourceKind.rule =>
      '一键转换：从 Cursor rules 生成 Codex / Open Code 的 AGENTS.md',
    AgentResourceKind.command =>
      '一键转换：从 Cursor commands 镜像写入 Open Code commands/<name>.md（多余命令会删除；Codex 无对等目录）',
    AgentResourceKind.hook =>
      '一键转换：从 Cursor hooks.json 与 hooks/ 生成 Codex hooks.json 与 hooks/（事件名与 matcher 按 Codex 结构调整；Open Code 无对等 hooks.json）',
  };

  bool get _canConvert =>
      resource.canConvertTo(SkillTarget.codex) ||
      resource.canConvertTo(SkillTarget.openCode);

  String? _pathLabelFor(SkillTarget target) {
    if (resource == AgentResourceKind.rule && target == SkillTarget.codex) {
      return McpPaths.codexAgentsMdPath;
    }
    if (resource == AgentResourceKind.hook && target == SkillTarget.cursor) {
      return '${McpPaths.cursorHooksJsonPath}  +  ${McpPaths.cursorHooksPath}';
    }
    if (resource == AgentResourceKind.hook && target == SkillTarget.codex) {
      return '${McpPaths.codexHooksJsonPath}  +  ${McpPaths.codexHooksPath}';
    }
    return hub.skillSync.resourceDeployPathFor(resource, target);
  }

  String? _directoryFor(SkillTarget target) {
    if (resource == AgentResourceKind.rule && target == SkillTarget.codex) {
      return McpPaths.codexConfigDirectory;
    }
    if (resource == AgentResourceKind.hook && target == SkillTarget.cursor) {
      return McpPaths.cursorConfigDirectory;
    }
    if (resource == AgentResourceKind.hook && target == SkillTarget.codex) {
      return McpPaths.codexConfigDirectory;
    }
    return hub.skillSync.resourceDeployPathFor(resource, target);
  }
}

Future<bool> _confirmLocalOverwrite(
  BuildContext context, {
  required String scope,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('确认应用到 Cursor？'),
          content: Text(
            '即将把缓存中的$scope镜像到 Cursor 正式目录。\n\n'
            '缓存中不存在的本地 Cursor 文件和目录也会被删除。\n\n'
            '本操作不会转换 Codex / Open Code；需要时请再点「一键转换」。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('确认应用'),
            ),
          ],
        ),
      ) ??
      false;
}

class _ClientConfigCard extends StatelessWidget {
  const _ClientConfigCard({required this.hub});

  final HubController hub;

  String _buttonLabel(McpClientAlignReport? report) {
    if (report == null) return '正在检测…';
    return report.shortLabel;
  }

  @override
  Widget build(BuildContext context) {
    final supported = hub.isDesktopSupported;
    final platforms = AgentPlatforms.mcpConfigurable;
    final detailLines = <String>[];
    final reports = platforms.map((p) => hub.clientAlignReport(p.id)).toList();
    if (reports.any((r) => r == null)) {
      detailLines.add('正在检测…');
    } else {
      for (final platform in platforms) {
        final report = hub.clientAlignReport(platform.id);
        if (report != null && !report.isAligned) {
          detailLines.add(report.prefixedReason);
        }
      }
      if (detailLines.isEmpty) {
        detailLines.add('${platforms.map((p) => p.label).join(' / ')} 已对齐');
      }
    }

    final configureAllLabel = '配置 ${platforms.map((p) => p.label).join(' + ')}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.psychology_outlined),
              title: const Text('一键配置客户端'),
              subtitle: Text(
                supported
                    ? '把 Hub 中的全部 MCP 写入各客户端，并移除 Hub 已删除的条目'
                    : '当前平台不支持写入客户端配置',
              ),
            ),
            FilledButton.icon(
              onPressed: !supported
                  ? null
                  : () async {
                      final result = await hub.configureAllClients();
                      if (!context.mounted) return;
                      showHubNotice(
                        context,
                        message: result.message,
                        ok: result.ok,
                      );
                    },
              icon: const Icon(Icons.flash_on_outlined),
              label: Text(configureAllLabel),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: !supported
                  ? null
                  : () async {
                      final result = await hub.importMissingFromClients();
                      if (!context.mounted) return;
                      showHubNotice(
                        context,
                        message: result.message,
                        ok: result.ok,
                      );
                    },
              icon: const Icon(Icons.download_outlined),
              label: const Text('从客户端导入未登记 MCP'),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final platform in platforms)
                  OutlinedButton(
                    onPressed: !supported
                        ? null
                        : () => hub.configureClient(platform.id),
                    child: Text(
                      '${platform.label} · ${_buttonLabel(hub.clientAlignReport(platform.id))}',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              detailLines.join('\n'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            for (final platform in platforms)
              _DirectoryPathRow(
                label: platform.label,
                displayPath: platform.mcpConfigFilePath,
                directoryPath: platform.mcpConfigDirectoryPath,
                enabled: supported,
              ),
          ],
        ),
      ),
    );
  }
}

class _DirectoryPathRow extends StatelessWidget {
  const _DirectoryPathRow({
    required this.label,
    required this.displayPath,
    required this.directoryPath,
    required this.enabled,
  });

  final String label;
  final String? displayPath;
  final String? directoryPath;
  final bool enabled;

  Future<void> _open(BuildContext context) async {
    try {
      await DirectoryOpener.open(directoryPath);
    } catch (error) {
      if (!context.mounted) return;
      showHubNotice(context, message: '打开目录失败：$error', ok: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SelectableText(
            '$label: ${displayPath ?? "(不可用)"}',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
        IconButton(
          tooltip: '打开 $label 目录',
          onPressed: enabled && directoryPath != null
              ? () => _open(context)
              : null,
          icon: const Icon(Icons.folder_open_outlined),
        ),
      ],
    );
  }
}

class _ServerTile extends StatelessWidget {
  const _ServerTile({required this.serverId});

  final String serverId;

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<HubController>();
    final server = hub.servers.firstWhere((s) => s.id == serverId);
    final isHub = server.builtIn || server.id == HubMcpConstants.serverKey;
    final runtime = hub.runtimeInfoFor(server);
    final transportLabel = server.transport == McpTransport.http
        ? 'HTTP'
        : 'stdio';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Column(
          children: [
            SwitchListTile(
              title: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      server.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusBadge(label: runtime.kindLabel, tonal: true),
                  const SizedBox(width: 6),
                  StatusBadge(
                    label: runtime.phaseBadgeLabel,
                    active: runtime.phase.isActive,
                  ),
                  if (server.shouldAutoStartByHub) ...[
                    const SizedBox(width: 6),
                    const StatusBadge(label: '自动'),
                  ],
                ],
              ),
              subtitle: Text(
                isHub
                    ? '$transportLabel · ${server.id} · ${hub.hubEndpointUrl}'
                    : '$transportLabel · ${server.id}',
              ),
              value: server.enabled,
              onChanged: (v) => hub.setEnabled(server.id, v),
            ),
            if (runtime.lastError != null &&
                runtime.phase == McpRuntimePhase.error)
              ListTile(
                dense: true,
                leading: const Icon(Icons.error_outline, size: 20),
                title: Text(runtime.lastError!),
              ),
            if (server.notes != null)
              ListTile(
                dense: true,
                leading: const Icon(Icons.info_outline, size: 20),
                title: Text(server.notes!),
              ),
            if (server.repoUrl != null)
              ListTile(
                dense: true,
                leading: const Icon(Icons.cloud_outlined, size: 20),
                title: Text(
                  server.repoUrl!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: server.localPath == null
                    ? null
                    : Text(
                        server.localPath!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
            if (server.transport == McpTransport.http)
              ListTile(
                dense: true,
                leading: const Icon(Icons.link, size: 20),
                title: Text(server.url ?? '(未设置 URL)'),
                subtitle: isHub && hub.hubMcpHost.lastError != null
                    ? Text(hub.hubMcpHost.lastError!)
                    : null,
              )
            else
              ListTile(
                dense: true,
                leading: const Icon(Icons.terminal, size: 20),
                title: Text(
                  [server.command ?? '(未设置 command)', ...server.args].join(' '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 4,
                children: [
                  if (runtime.canStart)
                    TextButton.icon(
                      onPressed: () => hub.startServer(server.id),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('启动'),
                    ),
                  if (runtime.canStop)
                    TextButton.icon(
                      onPressed: () => hub.stopServer(server.id),
                      icon: const Icon(Icons.stop),
                      label: const Text('停止'),
                    ),
                  if (runtime.canUpdate)
                    TextButton.icon(
                      onPressed: () async {
                        try {
                          await hub.updateServer(server.id);
                          if (!context.mounted) return;
                          showHubNotice(
                            context,
                            message: hub.lastMessage ?? '已更新',
                            ok: true,
                          );
                        } catch (error) {
                          if (!context.mounted) return;
                          showHubNotice(context, message: '$error', ok: false);
                        }
                      },
                      icon: const Icon(Icons.cloud_download_outlined),
                      label: const Text('更新'),
                    ),
                  if (!isHub)
                    TextButton.icon(
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('移除 MCP？'),
                            content: Text(
                              '将从 Hub 目录移除，并删除本地 clone 目录。\n${server.name}',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('取消'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('移除'),
                              ),
                            ],
                          ),
                        );
                        if (ok == true) {
                          try {
                            await hub.removeServer(server.id);
                            if (!context.mounted) return;
                            showHubNotice(
                              context,
                              message: hub.lastMessage ?? '已移除',
                              ok: true,
                            );
                          } catch (error) {
                            if (!context.mounted) return;
                            showHubNotice(
                              context,
                              message: '$error',
                              ok: false,
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('移除'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
