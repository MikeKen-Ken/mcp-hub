import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_brand.dart';
import '../controllers/hub_controller.dart';
import '../features/app_update/app_update_screen.dart';
import '../features/skill_sync/skill_sync.dart';
import '../models/mcp_transport.dart';
import '../services/directory_opener.dart';
import '../services/hub_mcp_constants.dart';
import '../services/mcp_client_configurator.dart';
import '../services/mcp_paths.dart';
import '../webdav/webdav_sync_service.dart';
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
                  '按用途进入管理，首页只保留状态和入口。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                _FeatureCard(
                  icon: Icons.hub_outlined,
                  title: '客户端 MCP',
                  subtitle: '一键配置 Cursor / Codex，并管理 ${hub.servers.length} 个本地 MCP',
                  status: _clientSummary(hub),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ClientMcpScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _FeatureCard(
                  icon: Icons.sync_alt_outlined,
                  title: 'Agent 配置同步',
                  subtitle: '统一同步 Skill、Command 和 Rule',
                  status: _resourceSummary(hub),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AgentConfigSyncScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _WebDavStatusCard(hub: hub),
                if (hub.lastMessage != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    hub.lastMessage!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  '数据目录：${McpPaths.hubDataRoot ?? "(不可用)"}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
    );
  }

  String _clientSummary(HubController hub) {
    if (hub.cursorConfigured == true && hub.codexConfigured == true) {
      return 'Cursor / Codex 已对齐';
    }
    return '有客户端尚未对齐';
  }

  String _resourceSummary(HubController hub) => switch (hub.skillSync.status) {
        SkillSyncStatus.idle => '尚未同步',
        SkillSyncStatus.syncing => '同步中…',
        SkillSyncStatus.success => '最近同步成功',
        SkillSyncStatus.error => '最近同步失败',
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
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

class ClientMcpScreen extends StatelessWidget {
  const ClientMcpScreen({super.key});

  Future<void> _runWebDavSync(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    await action();
    if (!context.mounted) return;
    final hub = context.read<HubController>();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(hub.lastMessage ?? '完成')),
    );
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
            tooltip: webDavReady
                ? '从 WebDAV 同步 MCP 清单'
                : '需先启用并配置 WebDAV',
            onPressed: !webDavReady || syncing
                ? null
                : () => _runWebDavSync(context, hub.pullWebDavNow),
            icon: const Icon(Icons.cloud_download_outlined),
          ),
          IconButton(
            tooltip: webDavReady
                ? '上传 MCP 清单到 WebDAV'
                : '需先启用并配置 WebDAV',
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
          _ClientConfigCard(hub: hub),
          const SizedBox(height: 12),
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

class _WebDavStatusCard extends StatelessWidget {
  const _WebDavStatusCard({required this.hub});

  final HubController hub;

  @override
  Widget build(BuildContext context) {
    final cfg = hub.webDavConfig;
    final sync = hub.webDavSync;
    final statusText = !cfg.enabled
        ? '未启用'
        : switch (sync.status) {
            CatalogSyncStatus.idle => '空闲',
            CatalogSyncStatus.syncing => '同步中…',
            CatalogSyncStatus.success => '成功',
            CatalogSyncStatus.error => '失败',
          };
    final when = sync.lastSyncedAt == null
        ? '尚未同步'
        : '上次：${sync.lastSyncedAt!.toLocal()}';

    return Card(
      child: ListTile(
        leading: const Icon(Icons.cloud_outlined),
        title: const Text('WebDAV 配置同步'),
        subtitle: Text(
          cfg.enabled ? '$statusText · $when' : '换电脑时可同步 MCP 清单；点右侧齿轮配置',
        ),
        trailing: IconButton(
          tooltip: '设置',
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const WebDavSettingsScreen(),
              ),
            );
          },
          icon: const Icon(Icons.chevron_right),
        ),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const WebDavSettingsScreen(),
            ),
          );
        },
      ),
    );
  }
}

class AgentConfigSyncScreen extends StatelessWidget {
  const AgentConfigSyncScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<HubController>();
    return Scaffold(
      appBar: AppBar(title: const Text('Agent 配置同步')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '每种资源一键同步/上传，覆盖该类型支持的全部客户端。'
            '从 WebDAV 拉取并部署到本机，或把本机配置上传到 WebDAV。'
            '同步采用合并覆盖，不删除目标中的额外文件。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          for (final resource in AgentResourceKind.values) ...[
            _ResourceSyncCard(hub: hub, resource: resource),
            const SizedBox(height: 12),
          ],
        ],
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
      SkillSyncStatus.syncing => '同步中…',
      SkillSyncStatus.success => '成功',
      SkillSyncStatus.error => '失败',
    };
    final when = hub.skillSync.lastSyncedAt == null
        ? '尚未同步'
        : '上次：${hub.skillSync.lastSyncedAt!.toLocal()}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(switch (resource) {
                AgentResourceKind.skill => Icons.auto_awesome_outlined,
                AgentResourceKind.command => Icons.terminal_outlined,
                AgentResourceKind.rule => Icons.rule_outlined,
              }),
              title: Text('${resource.label} 同步'),
              subtitle: Text(
                supported
                    ? (webDavReady
                          ? '$statusText · $when\n'
                                '${_supportDescription()}'
                          : '需先启用并配置 WebDAV')
                    : '当前平台不支持目录同步',
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: !supported || !webDavReady || busy
                        ? null
                        : () => _run(
                            context,
                            () => hub.syncResourceToAllTargets(resource),
                          ),
                    icon: const Icon(Icons.cloud_download_outlined),
                    label: const Text('同步'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: !supported || !webDavReady || busy
                        ? null
                        : () => _run(
                            context,
                            () => hub.pushResourceToAllTargets(resource),
                          ),
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: const Text('上传'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final target in SkillTarget.values)
              _DirectoryPathRow(
                label: target.label,
                displayPath: hub.skillSync.resourceDeployPathFor(
                  resource,
                  target,
                ),
                directoryPath: hub.skillSync.resourceDeployPathFor(
                  resource,
                  target,
                ),
                enabled: supported && resource.supports(target),
              ),
            _DirectoryPathRow(
              label: '缓存',
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
      ),
    );
  }

  String _supportDescription() {
    final labels =
        resource.supportedTargets.map((t) => t.label).join('、');
    if (resource == AgentResourceKind.command &&
        !resource.supports(SkillTarget.codex)) {
      return '将同步/上传：$labels（Codex 暂无对等的全局 Command 目录）';
    }
    return '将同步/上传：$labels';
  }
}

class _ClientConfigCard extends StatelessWidget {
  const _ClientConfigCard({required this.hub});

  final HubController hub;

  String _status(bool? value) => switch (value) {
    true => '已对齐',
    false => '未对齐 / 部分缺失',
    null => '检测中…',
  };

  @override
  Widget build(BuildContext context) {
    final supported = hub.isDesktopSupported;
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
                    child: Text('Cursor · ${_status(hub.cursorConfigured)}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: !supported
                        ? null
                        : () => hub.configureClient(McpClientKind.codex),
                    child: Text('Codex · ${_status(hub.codexConfigured)}'),
                  ),
                ),
              ],
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
                  if (server.autoStart) ...[
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
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    IconButton(
                      tooltip: '启动',
                      onPressed: () => hub.startServer(server.id),
                      icon: const Icon(Icons.play_arrow),
                    ),
                    IconButton(
                      tooltip: '停止',
                      onPressed: () => hub.stopServer(server.id),
                      icon: const Icon(Icons.stop),
                    ),
                  ],
                ),
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
