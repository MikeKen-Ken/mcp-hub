import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../common/app_locale.dart';
import '../../common/app_theme.dart';
import '../../controllers/hub_controller.dart';
import '../../models/mcp_runtime_phase.dart';
import '../../models/mcp_server_entry.dart';
import '../../models/mcp_server_runtime_info.dart';
import '../../models/mcp_transport.dart';
import '../../services/hub_mcp_constants.dart';
import '../../widgets/hub_notice/hub_notice.dart';
import '../../widgets/status_badge.dart';

class ServerTile extends StatelessWidget {
  const ServerTile({super.key, required this.serverId});

  final String serverId;

  @override
  Widget build(BuildContext context) {
    return Selector<HubController, _ServerTileSnapshot?>(
      selector: (_, hub) {
        final server = hub.serverById(serverId);
        if (server == null) return null;
        return _ServerTileSnapshot(
          server: server,
          runtime: hub.runtimeInfoFor(server),
          hubEndpointUrl: hub.hubEndpointUrl,
          hubHostError: hub.hubMcpHost.lastError,
        );
      },
      builder: (context, snapshot, _) {
        if (snapshot == null) return const SizedBox.shrink();
        return _ServerTileContent(snapshot: snapshot);
      },
    );
  }
}

class _ServerTileContent extends StatelessWidget {
  const _ServerTileContent({required this.snapshot});

  final _ServerTileSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final hub = context.read<HubController>();
    final server = snapshot.server;
    final runtime = snapshot.runtime;
    final isHub = server.builtIn || server.id == HubMcpConstants.serverKey;
    final transportLabel = server.transport == McpTransport.http
        ? 'HTTP'
        : 'stdio';
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dotColor = runtime.phase == McpRuntimePhase.error
        ? scheme.error
        : runtime.phase.isActive
        ? AppTheme.success(context)
        : scheme.onSurfaceVariant.withValues(alpha: 0.45);

    final endpointOrCmd = server.transport == McpTransport.http
        ? (server.url ?? tr('(未设置 URL)', '(URL not set)'))
        : [
            server.command ?? tr('(未设置命令)', '(command not set)'),
            ...server.args,
          ].join(' ');

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dotColor,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              server.name,
                              style: theme.textTheme.titleSmall,
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
                            error: runtime.phase == McpRuntimePhase.error,
                          ),
                          if (server.shouldAutoStartByHub) ...[
                            const SizedBox(width: 6),
                            StatusBadge(label: tr('自动', 'Auto')),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isHub
                            ? '$transportLabel · ${server.id} · ${snapshot.hubEndpointUrl}'
                            : '$transportLabel · ${server.id}',
                        style: theme.textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: server.enabled,
                  onChanged: (value) => hub.setEnabled(server.id, value),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: AppTheme.subtleBg(context),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTheme.hairline(context)),
              ),
              child: Row(
                children: [
                  Icon(
                    server.transport == McpTransport.http
                        ? Icons.link
                        : Icons.terminal,
                    size: 15,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SelectableText(
                      endpointOrCmd,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontFamily: 'Consolas',
                        color: scheme.onSurface,
                      ),
                      maxLines: 2,
                    ),
                  ),
                ],
              ),
            ),
            if (runtime.lastError != null &&
                runtime.phase == McpRuntimePhase.error) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.error_outline, size: 15, color: scheme.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      runtime.lastError!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (isHub && snapshot.hubHostError != null) ...[
              const SizedBox(height: 6),
              Text(
                snapshot.hubHostError!,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
            ],
            if (server.notes != null) ...[
              const SizedBox(height: 6),
              Text(server.notes!, style: theme.textTheme.bodySmall),
            ],
            if (server.repoUrl != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.cloud_outlined,
                    size: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      server.localPath == null
                          ? server.repoUrl!
                          : '${server.repoUrl!}  ·  ${server.localPath!}',
                      style: theme.textTheme.labelSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            if (runtime.canStart ||
                runtime.canStop ||
                runtime.canUpdate ||
                !isHub) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 4,
                  children: [
                    if (runtime.canStart)
                      TextButton.icon(
                        onPressed: () => hub.startServer(server.id),
                        icon: const Icon(Icons.play_arrow, size: 16),
                        label: Text(tr('启动', 'Start')),
                      ),
                    if (runtime.canStop)
                      TextButton.icon(
                        onPressed: () => hub.stopServer(server.id),
                        icon: const Icon(Icons.stop, size: 16),
                        label: Text(tr('停止', 'Stop')),
                      ),
                    if (runtime.canUpdate)
                      TextButton.icon(
                        onPressed: () => _update(context, hub, server),
                        icon: const Icon(Icons.cloud_download_outlined, size: 16),
                        label: Text(tr('更新', 'Update')),
                      ),
                    if (!isHub)
                      TextButton.icon(
                        onPressed: () => _remove(context, hub, server),
                        icon: const Icon(Icons.delete_outline, size: 16),
                        label: Text(tr('移除', 'Remove')),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _update(
    BuildContext context,
    HubController hub,
    McpServerEntry server,
  ) async {
    try {
      await hub.updateServer(server.id);
      if (!context.mounted) return;
      showHubNotice(
        context,
        message: hub.lastMessage ?? tr('已更新', 'Updated'),
        ok: true,
      );
    } catch (error) {
      if (!context.mounted) return;
      showHubNotice(context, message: '$error', ok: false);
    }
  }

  Future<void> _remove(
    BuildContext context,
    HubController hub,
    McpServerEntry server,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr('确认移除 MCP？', 'Remove MCP?')),
        content: Text(
          tr(
            '这会从 Hub 移除该 MCP，并删除本机克隆目录。\n${server.name}',
            'This will remove the MCP from Hub and delete its local clone directory.\n${server.name}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tr('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(tr('移除', 'Remove')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await hub.removeServer(server.id);
      if (!context.mounted) return;
      showHubNotice(
        context,
        message: hub.lastMessage ?? tr('已移除', 'Removed'),
        ok: true,
      );
    } catch (error) {
      if (!context.mounted) return;
      showHubNotice(context, message: '$error', ok: false);
    }
  }
}

class _ServerTileSnapshot {
  const _ServerTileSnapshot({
    required this.server,
    required this.runtime,
    required this.hubEndpointUrl,
    required this.hubHostError,
  });

  final McpServerEntry server;
  final McpServerRuntimeInfo runtime;
  final String hubEndpointUrl;
  final String? hubHostError;

  @override
  bool operator ==(Object other) {
    return other is _ServerTileSnapshot &&
        identical(other.server, server) &&
        other.runtime == runtime &&
        other.hubEndpointUrl == hubEndpointUrl &&
        other.hubHostError == hubHostError;
  }

  @override
  int get hashCode =>
      Object.hash(server, runtime, hubEndpointUrl, hubHostError);
}
