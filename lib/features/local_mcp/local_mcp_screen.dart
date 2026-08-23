import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';

import '../../common/app_motion.dart';
import '../../controllers/hub_controller.dart';
import '../../screens/add_server_screen.dart';
import '../../widgets/hub_notice/hub_notice.dart';
import 'server_tile.dart';

class LocalMcpScreen extends StatelessWidget {
  const LocalMcpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<HubController, _ServerListSnapshot>(
      selector: (_, hub) => _ServerListSnapshot(
        serverIds: hub.servers.map((server) => server.id).toList(),
        hasUpdatableServers: hub.hasUpdatableServers,
      ),
      builder: (context, snapshot, _) {
        final hub = context.read<HubController>();
        return Scaffold(
          appBar: AppBar(
            title: const Text('Local MCP'),
            actions: [
              IconButton(
                tooltip: 'Update all',
                onPressed: snapshot.hasUpdatableServers
                    ? () async {
                        await hub.updateAllServers();
                        if (!context.mounted) return;
                        showHubNotice(
                          context,
                          message: hub.lastMessage ?? 'Update complete',
                        );
                      }
                    : null,
                icon: const Icon(Icons.system_update_alt),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () =>
                pushAppPage<void>(context, const AddServerScreen()),
            icon: const Icon(Icons.add),
            label: const Text('Add MCP'),
          ),
          body: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            itemCount: snapshot.serverIds.length + 1,
            separatorBuilder: (_, index) =>
                SizedBox(height: index == 0 ? 12 : 10),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Text(
                  'The switch controls whether this MCP is written to Cursor / Codex; built-in hubMCP is always retained.',
                  style: Theme.of(context).textTheme.bodySmall,
                );
              }
              final serverId = snapshot.serverIds[index - 1];
              return ServerTile(key: ValueKey(serverId), serverId: serverId);
            },
          ),
        );
      },
    );
  }
}

class _ServerListSnapshot {
  const _ServerListSnapshot({
    required this.serverIds,
    required this.hasUpdatableServers,
  });

  final List<String> serverIds;
  final bool hasUpdatableServers;

  @override
  bool operator ==(Object other) {
    return other is _ServerListSnapshot &&
        other.hasUpdatableServers == hasUpdatableServers &&
        listEquals(other.serverIds, serverIds);
  }

  @override
  int get hashCode =>
      Object.hash(hasUpdatableServers, Object.hashAll(serverIds));
}
