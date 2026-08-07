import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/hub_controller.dart';
import '../models/mcp_transport.dart';
import '../services/mcp_client_configurator.dart';
import '../services/mcp_paths.dart';
import '../services/mcp_process_manager.dart';
import 'add_server_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<HubController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('MCP Hub'),
        actions: [
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
                const SizedBox(height: 16),
                Text(
                  '本地 MCP',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  '开关控制是否写入 Cursor / Codex；HTTP 型可在此启停进程。',
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
    final proc = hub.processState(server.id);
    final transportLabel =
        server.transport == McpTransport.http ? 'HTTP' : 'stdio';
    final procLabel = switch (proc.status) {
      McpProcessStatus.stopped => '已停止',
      McpProcessStatus.starting => '启动中',
      McpProcessStatus.running => '运行中${proc.pid == null ? '' : ' · ${proc.pid}'}',
      McpProcessStatus.error => '错误',
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Column(
          children: [
            SwitchListTile(
              title: Text(server.name),
              subtitle: Text('$transportLabel · ${server.id}'),
              value: server.enabled,
              onChanged: (v) => hub.setEnabled(server.id, v),
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
                subtitle: Text(procLabel),
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
                subtitle: const Text('由 Cursor / Codex 按需拉起'),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('移除 MCP？'),
                      content: Text('仅从 Hub 目录移除条目，不会删除本地 clone。\n${server.name}'),
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
                  if (ok == true) await hub.removeServer(server.id);
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('移除'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
