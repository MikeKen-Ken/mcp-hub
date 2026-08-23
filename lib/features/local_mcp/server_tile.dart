import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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

    return Card(
      margin: EdgeInsets.zero,
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
                    const StatusBadge(label: 'Auto'),
                  ],
                ],
              ),
              subtitle: Text(
                isHub
                    ? '$transportLabel · ${server.id} · ${snapshot.hubEndpointUrl}'
                    : '$transportLabel · ${server.id}',
              ),
              value: server.enabled,
              onChanged: (value) => hub.setEnabled(server.id, value),
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
                title: Text(server.url ?? '(URL not set)'),
                subtitle: isHub && snapshot.hubHostError != null
                    ? Text(snapshot.hubHostError!)
                    : null,
              )
            else
              ListTile(
                dense: true,
                leading: const Icon(Icons.terminal, size: 20),
                title: Text(
                  [
                    server.command ?? '(command not set)',
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
                  if (runtime.canStart)
                    TextButton.icon(
                      onPressed: () => hub.startServer(server.id),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start'),
                    ),
                  if (runtime.canStop)
                    TextButton.icon(
                      onPressed: () => hub.stopServer(server.id),
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop'),
                    ),
                  if (runtime.canUpdate)
                    TextButton.icon(
                      onPressed: () => _update(context, hub, server),
                      icon: const Icon(Icons.cloud_download_outlined),
                      label: const Text('Update'),
                    ),
                  if (!isHub)
                    TextButton.icon(
                      onPressed: () => _remove(context, hub, server),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Remove'),
                    ),
                ],
              ),
            ),
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
      showHubNotice(context, message: hub.lastMessage ?? 'Updated', ok: true);
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
        title: const Text('Remove MCP?'),
        content: Text(
          'This will remove the MCP from Hub and delete its local clone directory.\n${server.name}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await hub.removeServer(server.id);
      if (!context.mounted) return;
      showHubNotice(context, message: hub.lastMessage ?? 'Removed', ok: true);
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
