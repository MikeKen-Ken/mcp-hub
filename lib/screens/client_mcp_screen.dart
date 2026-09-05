import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../common/agent_platforms.dart';
import '../common/app_motion.dart';
import '../controllers/hub_controller.dart';
import '../features/hub_configuration/widgets/directory_path_row.dart';
import '../features/hub_configuration/widgets/section_header.dart';
import '../features/local_mcp/local_mcp_screen.dart';
import '../services/mcp_client_configurator.dart';
import '../widgets/hub_notice/hub_notice.dart';

class ClientMcpScreen extends StatelessWidget {
  const ClientMcpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<HubController>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Client MCP'),
        actions: [
          IconButton(
            tooltip: 'Refresh configuration status',
            onPressed: hub.refreshClientStatus,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Connection Status',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            'Write all MCPs to client configuration and view the local MCP list.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          _ClientConfigCard(hub: hub),
          const SizedBox(height: 24),
          const SectionHeader('MCP List'),
          const SizedBox(height: 8),
          Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 10,
              ),
              leading: const Icon(Icons.storage_outlined),
              title: const Text('Local MCP'),
              subtitle: Text(
                'Add, start, stop, and update MCPs · ${hub.servers.length} total',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => pushAppPage<void>(context, const LocalMcpScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClientConfigCard extends StatelessWidget {
  const _ClientConfigCard({required this.hub});

  final HubController hub;

  String _buttonLabel(McpClientAlignReport? report) {
    if (report == null) return 'Checking…';
    return report.shortLabel;
  }

  @override
  Widget build(BuildContext context) {
    final supported = hub.isDesktopSupported;
    final platforms = AgentPlatforms.mcpConfigurable;
    final detailLines = <String>[];
    final reports = platforms.map((p) => hub.clientAlignReport(p.id)).toList();
    if (reports.any((r) => r == null)) {
      detailLines.add('Checking…');
    } else {
      for (final platform in platforms) {
        final report = hub.clientAlignReport(platform.id);
        if (report != null && !report.isAligned) {
          detailLines.add(report.prefixedReason);
        }
      }
      if (detailLines.isEmpty) {
        detailLines.add('${platforms.map((p) => p.label).join(' / ')} aligned');
      }
    }

    final configureAllLabel =
        'Configure ${platforms.map((p) => p.label).join(' + ')}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.psychology_outlined),
              title: const Text('Configure Clients'),
              subtitle: Text(
                supported
                    ? 'Write all Hub MCPs to the clients and remove entries deleted from Hub'
                    : 'Writing client configuration is not supported on this platform',
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
              label: const Text('Import unregistered MCPs from clients'),
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
              DirectoryPathRow(
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
