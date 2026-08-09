import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_brand.dart';
import '../controllers/hub_controller.dart';
import '../features/app_update/app_update_screen.dart';
import '../features/config_backup/config_backup.dart';
import '../features/skill_sync/skill_sync.dart';
import '../models/mcp_transport.dart';
import '../services/directory_opener.dart';
import '../services/hub_mcp_constants.dart';
import '../services/mcp_client_configurator.dart';
import '../services/mcp_paths.dart';
import '../widgets/status_badge.dart';
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
                const SizedBox(height: 16),
                _HomeSummaryCard(hub: hub),
                const SizedBox(height: 24),
                const _SectionHeader('常用入口'),
                const SizedBox(height: 8),
                _FeatureCard(
                  icon: Icons.sync_alt_outlined,
                  title: 'Agent 配置下载/上传',
                  subtitle: '下载到缓存 → 更新/覆盖正式目录',
                  status: _resourceSummary(hub),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AgentConfigSyncScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _FeatureCard(
                  icon: Icons.folder_zip_outlined,
                  title: '配置备份',
                  subtitle: '导出 / 恢复本机 MCP 与 Agent 配置',
                  status: '建议定期保存到网盘或移动硬盘',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ConfigBackupScreen(),
                    ),
                  ),
                ),
                if (hub.lastMessage != null) ...[
                  const SizedBox(height: 24),
                  const _SectionHeader('最近状态'),
                  const SizedBox(height: 8),
                  _StatusMessageCard(message: hub.lastMessage!),
                ],
                const SizedBox(height: 24),
                const _SectionHeader('连接状态'),
                const SizedBox(height: 8),
                _FeatureCard(
                  icon: Icons.hub_outlined,
                  title: '客户端 MCP',
                  subtitle: '配置 Cursor / Codex 的 MCP 连接',
                  status: _clientSummary(hub),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ClientMcpScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const _SectionHeader('MCP 列表'),
                const SizedBox(height: 8),
                _FeatureCard(
                  icon: Icons.storage_outlined,
                  title: '本地 MCP',
                  subtitle: '添加、启停和更新已管理的 MCP',
                  status: '共 ${hub.servers.length} 个',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const LocalMcpScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  '数据目录：${McpPaths.hubDataRoot ?? "(不可用)"}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
    );
  }

  String _clientSummary(HubController hub) {
    final cursor = hub.cursorAlignReport;
    final codex = hub.codexAlignReport;
    if (cursor == null || codex == null) {
      return '正在检测…';
    }
    if (cursor.isAligned && codex.isAligned) {
      return 'Cursor / Codex 已对齐';
    }
    final parts = <String>[];
    if (!cursor.isAligned) parts.add(cursor.prefixedReason);
    if (!codex.isAligned) parts.add(codex.prefixedReason);
    return parts.join('；');
  }

  String _resourceSummary(HubController hub) => switch (hub.skillSync.status) {
    SkillSyncStatus.idle => '尚未下载/上传',
    SkillSyncStatus.syncing => '下载/上传中…',
    SkillSyncStatus.success => '最近下载/上传成功',
    SkillSyncStatus.error => '最近下载/上传失败',
  };
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 10,
        ),
        leading: CircleAvatar(child: Icon(icon)),
        title: Text(title),
        subtitle: Text('$subtitle\n$status'),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _HomeSummaryCard extends StatelessWidget {
  const _HomeSummaryCard({required this.hub});

  final HubController hub;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              child: const Icon(Icons.account_tree_outlined),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('当前摘要', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text('已管理 ${hub.servers.length} 个本地 MCP'),
                  Text(
                    'Agent 资源：${_resourceSummary(hub)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _resourceSummary(HubController hub) => switch (hub.skillSync.status) {
    SkillSyncStatus.idle => '尚未下载/上传',
    SkillSyncStatus.syncing => '下载/上传中…',
    SkillSyncStatus.success => '最近下载/上传成功',
    SkillSyncStatus.error => '最近下载/上传失败',
  };
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title, style: Theme.of(context).textTheme.titleSmall);
  }
}

class _StatusMessageCard extends StatelessWidget {
  const _StatusMessageCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Text(message, style: Theme.of(context).textTheme.bodySmall),
      ),
    );
  }
}

class ClientMcpScreen extends StatelessWidget {
  const ClientMcpScreen({super.key});

  Future<void> _runWebDavSync(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    await action();
    if (!context.mounted) return;
    final hub = context.read<HubController>();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(hub.lastMessage ?? '完成')));
  }

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<HubController>();
    final webDavReady = hub.isWebDavReady;
    final syncing = hub.isWebDavSyncing;
    return Scaffold(
      appBar: AppBar(
        title: const Text('客户端 MCP'),
        actions: [
          IconButton(
            tooltip: webDavReady ? '从 WebDAV 下载 MCP 清单' : '需先启用并配置 WebDAV',
            onPressed: !webDavReady || syncing
                ? null
                : () => _runWebDavSync(context, hub.pullWebDavNow),
            icon: const Icon(Icons.cloud_download_outlined),
          ),
          IconButton(
            tooltip: webDavReady ? '上传 MCP 清单到 WebDAV' : '需先启用并配置 WebDAV',
            onPressed: !webDavReady || syncing
                ? null
                : () => _runWebDavSync(context, hub.pushWebDavNow),
            icon: const Icon(Icons.cloud_upload_outlined),
          ),
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
            '将已启用的 MCP 合并写入客户端配置，并查看本地 MCP 列表。',
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
            onPressed: () async {
              await hub.updateAllServers();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(hub.lastMessage ?? '更新完成')),
              );
            },
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
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
                      const SizedBox(height: 4),
                      Text(
                        '只处理某一类配置时使用；展开卡片可查看转换说明和目录位置。',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
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
                    '在设备与 WebDAV 之间管理 Agent 配置',
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
            const SizedBox(height: 6),
            Text(
              '远端以 Cursor 配置为准；Codex Skill 与 AGENTS.md 由本机 Cursor 配置转换生成。',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const _FlowLabel(index: 1, label: '下载到缓存'),
                Icon(Icons.arrow_forward, size: 16, color: scheme.outline),
                const _FlowLabel(index: 2, label: '更新到正式目录'),
                Icon(Icons.arrow_forward, size: 16, color: scheme.outline),
                const _FlowLabel(index: 3, label: '按需上传远端'),
                const SizedBox(width: 4),
                _SyncStatusPill(
                  icon: Icons.history_outlined,
                  label: status,
                  active: hub.skillSync.status == SkillSyncStatus.success,
                ),
              ],
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
  });

  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active
            ? scheme.secondaryContainer
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
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
            const SizedBox(height: 4),
            Text(
              webDavReady
                  ? '按顺序执行前三步，可让本机与远端保持一致。'
                  : '下载和上传需要先在设置中启用并配置 WebDAV。',
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
                      : () => run(hub.syncAllResourcesFromWebDav),
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: const Text('1  下载全部'),
                ),
                FilledButton.icon(
                  onPressed: !supported || busy
                      ? null
                      : () => run(hub.applyAllResourcesFromCache),
                  icon: const Icon(Icons.install_desktop_outlined),
                  label: const Text('2  更新/覆盖全部'),
                ),
                OutlinedButton.icon(
                  onPressed: !supported || !webDavReady || busy
                      ? null
                      : () => run(hub.pushAllResourcesToWebDav),
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('3  上传全部'),
                ),
                OutlinedButton.icon(
                  onPressed: !supported || busy
                      ? null
                      : () => run(hub.convertAllResourcesFromCursor),
                  icon: const Icon(Icons.transform_outlined),
                  label: const Text('仅本机转换'),
                ),
              ],
            ),
            const Divider(height: 24),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: const Text('缓存目录'),
              subtitle: const Text('下载内容会先保存在这里，不会直接覆盖正式配置'),
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
  }

  @override
  Widget build(BuildContext context) {
    final supported = hub.isDesktopSupported;
    final webDavReady =
        hub.webDavConfig.enabled && hub.webDavConfig.isConfigured;
    final busy = hub.skillSync.status == SkillSyncStatus.syncing;
    final statusText = switch (hub.skillSync.status) {
      SkillSyncStatus.idle => '空闲',
      SkillSyncStatus.syncing => '下载/上传中…',
      SkillSyncStatus.success => '成功',
      SkillSyncStatus.error => '失败',
    };
    final when = hub.skillSync.lastSyncedAt == null
        ? '尚未下载/上传'
        : '上次：${hub.skillSync.lastSyncedAt!.toLocal()}';

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
                      : () => _run(
                          context,
                          () => hub.syncResourceToAllTargets(resource),
                        ),
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: const Text('下载'),
                ),
                FilledButton.icon(
                  onPressed: !supported || busy
                      ? null
                      : () => _run(
                          context,
                          () => hub.applyResourceFromCache(resource),
                        ),
                  icon: const Icon(Icons.install_desktop_outlined),
                  label: const Text('更新/覆盖'),
                ),
                OutlinedButton.icon(
                  onPressed: !supported || !webDavReady || busy
                      ? null
                      : () => _run(
                          context,
                          () => hub.pushResourceToAllTargets(resource),
                        ),
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('上传'),
                ),
              ],
            ),
            const Divider(height: 24),
            FilledButton.tonalIcon(
              onPressed: !supported || busy || !_canConvert
                  ? null
                  : () => _run(
                      context,
                      () => hub.convertResourceFromCursor(resource),
                    ),
              icon: const Icon(Icons.transform_outlined),
              label: Text(_convertButtonLabel),
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: const Text('说明与目录'),
              subtitle: Text(_supportDescription()),
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

  bool get _canConvert => resource.canConvertToCodex;

  String get _convertButtonLabel => switch (resource) {
    AgentResourceKind.skill => '一键转换 Cursor → Codex',
    AgentResourceKind.rule => '一键转换 Cursor → AGENTS.md',
    AgentResourceKind.command => '一键转换（Codex 暂不支持）',
  };

  String? get _convertHint => switch (resource) {
    AgentResourceKind.skill =>
      '批量复制 Skill 包，并为每个包生成 agents/openai.yaml（更新/覆盖后也会自动执行）',
    AgentResourceKind.rule =>
      '批量读取 ~/.cursor/rules/**/*.mdc，覆盖写入 ~/.codex/AGENTS.md'
          '（更新/覆盖后也会自动执行）',
    AgentResourceKind.command => 'Codex 暂无与 Cursor 全局 Command 对等的目录',
  };

  String? _pathLabelFor(SkillTarget target) {
    if (resource == AgentResourceKind.rule && target == SkillTarget.codex) {
      return McpPaths.codexAgentsMdPath;
    }
    return hub.skillSync.resourceDeployPathFor(resource, target);
  }

  String? _directoryFor(SkillTarget target) {
    if (resource == AgentResourceKind.rule && target == SkillTarget.codex) {
      return McpPaths.codexConfigDirectory;
    }
    return hub.skillSync.resourceDeployPathFor(resource, target);
  }

  String _supportDescription() {
    if (resource == AgentResourceKind.command) {
      return '下载到缓存 → 更新/覆盖到正式目录 → 上传全量镜像远端；'
          'Codex 暂无对等 Command 目录';
    }
    if (resource == AgentResourceKind.rule) {
      return '下载到缓存 → 更新/覆盖到正式目录（可自动转 AGENTS.md）→ 上传全量镜像远端';
    }
    return '下载到缓存 → 更新/覆盖到正式目录（可自动转 Codex）→ 上传全量镜像远端';
  }
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
    final cursor = hub.cursorAlignReport;
    final codex = hub.codexAlignReport;
    final detailLines = <String>[];
    if (cursor == null || codex == null) {
      detailLines.add('正在检测…');
    } else {
      if (!cursor.isAligned) detailLines.add(cursor.prefixedReason);
      if (!codex.isAligned) detailLines.add(codex.prefixedReason);
      if (detailLines.isEmpty) {
        detailLines.add('Cursor / Codex 已对齐');
      }
    }

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
                supported ? '合并写入已启用的 MCP，不覆盖其他服务' : '当前平台不支持写入客户端配置',
              ),
            ),
            FilledButton.icon(
              onPressed: !supported
                  ? null
                  : () async {
                      final result = await hub.configureAllClients();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(result.message)));
                    },
              icon: const Icon(Icons.flash_on_outlined),
              label: const Text('配置 Cursor + Codex'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: !supported
                        ? null
                        : () => hub.configureClient(McpClientKind.cursor),
                    child: Text('Cursor · ${_buttonLabel(cursor)}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: !supported
                        ? null
                        : () => hub.configureClient(McpClientKind.codex),
                    child: Text('Codex · ${_buttonLabel(codex)}'),
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
            _DirectoryPathRow(
              label: 'Cursor',
              displayPath: McpPaths.cursorMcpJsonPath,
              directoryPath: McpPaths.cursorConfigDirectory,
              enabled: supported,
            ),
            _DirectoryPathRow(
              label: 'Codex',
              displayPath: McpPaths.codexConfigTomlPath,
              directoryPath: McpPaths.codexConfigDirectory,
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('打开目录失败：$error')));
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
                  if (isHub) ...[
                    const SizedBox(width: 8),
                    const StatusBadge(label: '内置', tonal: true),
                  ],
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
                trailing: null,
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
                  if (!isHub && server.canHubStartProcess) ...[
                    TextButton.icon(
                      onPressed: () => hub.startServer(server.id),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('启动'),
                    ),
                    TextButton.icon(
                      onPressed: () => hub.stopServer(server.id),
                      icon: const Icon(Icons.stop),
                      label: const Text('停止'),
                    ),
                  ],
                  if (!isHub && server.localPath != null)
                    TextButton.icon(
                      onPressed: () async {
                        try {
                          await hub.updateServer(server.id);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(hub.lastMessage ?? '已更新')),
                          );
                        } catch (error) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text('$error')));
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
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(hub.lastMessage ?? '已移除')),
                            );
                          } catch (error) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(
                              context,
                            ).showSnackBar(SnackBar(content: Text('$error')));
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
