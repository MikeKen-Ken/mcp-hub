import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_brand.dart';
import '../controllers/hub_controller.dart';
import '../features/app_update/app_update_screen.dart';
import '../models/mcp_transport.dart';
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
            tooltip: '立即同步 WebDAV',
            onPressed: () async {
              await hub.syncWebDavNow();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(hub.lastMessage ?? '同步完成')),
              );
            },
            icon: Icon(
              switch (hub.webDavSync.status) {
                CatalogSyncStatus.syncing => Icons.cloud_sync,
                CatalogSyncStatus.error => Icons.cloud_off,
                CatalogSyncStatus.success => Icons.cloud_done,
                CatalogSyncStatus.idle => Icons.cloud_outlined,
              },
            ),
          ),
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
          IconButton(
            tooltip: '全部 git pull',
            onPressed: () async {
              try {
                await hub.updateAllServers();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(hub.lastMessage ?? '更新完成')),
                );
              } catch (error) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$error')),
                );
              }
            },
            icon: const Icon(Icons.system_update_alt),
          ),
          IconButton(
            tooltip: '刷新客户端配置状态',
            onPressed: hub.refreshClientStatus,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const AddServerScreen()),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('添加 MCP'),
      ),
      body: hub.loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                _ClientConfigCard(hub: hub),
                const SizedBox(height: 12),
                _WebDavStatusCard(hub: hub),
                const SizedBox(height: 16),
                Text(
                  '本地 MCP',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  '内置 hubMCP 始终存在，可用 AI 添加仓库/开关/写配置。'
                  '其它开关控制是否写入 Cursor / Codex。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                if (hub.servers.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        '还没有 MCP。点击右下角添加仓库（git clone 到 ~/.mcp-hub/servers）。',
                      ),
                    ),
                  )
                else
                  ...hub.servers.map((server) => _ServerTile(serverId: server.id)),
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
          cfg.enabled
              ? '$statusText · $when'
              : '换电脑时可同步 MCP 清单；点右侧齿轮配置',
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
                supported
                    ? '合并写入已启用的 MCP，不覆盖其他服务'
                    : '当前平台不支持写入客户端配置',
              ),
            ),
            FilledButton.icon(
              onPressed: !supported
                  ? null
                  : () async {
                      final result = await hub.configureAllClients();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(result.message)),
                      );
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
            SelectableText(
              'Cursor: ${McpPaths.cursorMcpJsonPath}\n'
              'Codex: ${McpPaths.codexConfigTomlPath}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
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
    final transportLabel =
        server.transport == McpTransport.http ? 'HTTP' : 'stdio';

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
                title: Text(server.repoUrl!, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: server.localPath == null
                    ? null
                    : Text(server.localPath!, maxLines: 1, overflow: TextOverflow.ellipsis),
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
                  [
                    server.command ?? '(未设置 command)',
                    ...server.args,
                  ].join(' '),
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
                            SnackBar(
                              content: Text(hub.lastMessage ?? '已更新'),
                            ),
                          );
                        } catch (error) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('$error')),
                          );
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
                              SnackBar(
                                content: Text(hub.lastMessage ?? '已移除'),
                              ),
                            );
                          } catch (error) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('$error')),
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
