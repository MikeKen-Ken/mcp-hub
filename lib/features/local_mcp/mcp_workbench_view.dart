import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../common/agent_platforms.dart';
import '../../common/app_locale.dart';
import '../../common/app_motion.dart';
import '../../common/app_theme.dart';
import '../../controllers/hub_controller.dart';
import '../../features/hub_configuration/widgets/directory_path_row.dart';
import '../../features/hub_configuration/widgets/section_header.dart';
import '../../models/mcp_runtime_phase.dart';
import '../../models/mcp_server_entry.dart';
import '../../screens/add_server_screen.dart';
import '../../widgets/hub_notice/hub_notice.dart';
import 'server_tile.dart';

enum _McpFilter { all, enabled, running, error }

/// 合并「客户端对齐」与「本地 MCP 列表」的一体化工作台视图。
class McpWorkbenchView extends StatefulWidget {
  const McpWorkbenchView({super.key});

  @override
  State<McpWorkbenchView> createState() => _McpWorkbenchViewState();
}

class _McpWorkbenchViewState extends State<McpWorkbenchView> {
  final _searchController = TextEditingController();
  _McpFilter _filter = _McpFilter.all;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<McpServerEntry> _filteredServers(HubController hub) {
    final q = _query.trim().toLowerCase();
    return hub.servers
        .where((server) {
          final runtime = hub.runtimeInfoFor(server);
          switch (_filter) {
            case _McpFilter.all:
              break;
            case _McpFilter.enabled:
              if (!server.enabled) return false;
            case _McpFilter.running:
              if (!runtime.phase.isActive) return false;
            case _McpFilter.error:
              if (runtime.phase != McpRuntimePhase.error) return false;
          }
          if (q.isEmpty) return true;
          return server.name.toLowerCase().contains(q) ||
              server.id.toLowerCase().contains(q) ||
              (server.command?.toLowerCase().contains(q) ?? false) ||
              (server.url?.toLowerCase().contains(q) ?? false);
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<HubController>();
    final supported = hub.isDesktopSupported;
    final platforms = AgentPlatforms.mcpConfigurable;
    final filtered = _filteredServers(hub);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final unalignedReasons = <String>[];
    var checking = false;
    for (final platform in platforms) {
      final report = hub.clientAlignReport(platform.id);
      if (report == null) {
        checking = true;
      } else if (!report.isAligned) {
        unalignedReasons.add(report.prefixedReason);
      }
    }

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(28, 22, 28, 32),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('MCP 服务', 'MCP Servers'),
                        style: theme.textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tr(
                          '管理本机 MCP 启停与版本更新，并将已启用的服务一键写入全部客户端。',
                          'Manage local MCP servers and align enabled entries across all configured clients.',
                        ),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    IconButton(
                      tooltip: tr('刷新客户端对齐状态', 'Refresh client status'),
                      onPressed: hub.refreshClientStatus,
                      icon: const Icon(Icons.refresh, size: 19),
                    ),
                    OutlinedButton.icon(
                      onPressed: hub.hasUpdatableServers
                          ? () async {
                              await hub.updateAllServers();
                              if (!context.mounted) return;
                              showHubNotice(
                                context,
                                message:
                                    hub.lastMessage ??
                                    tr('更新完成', 'Update complete'),
                              );
                            }
                          : null,
                      icon: const Icon(Icons.system_update_alt, size: 16),
                      label: Text(tr('全部更新', 'Update all')),
                    ),
                    FilledButton.icon(
                      onPressed: () =>
                          pushAppPage<void>(context, const AddServerScreen()),
                      icon: const Icon(Icons.add, size: 17),
                      label: Text(tr('添加 MCP', 'Add MCP')),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tr('客户端配置对齐', 'Client Configuration Alignment'),
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                checking
                                    ? tr('正在检测各客户端配置…', 'Checking client configs…')
                                    : unalignedReasons.isEmpty
                                    ? tr(
                                        '全部 ${platforms.length} 个客户端已与 Hub 对齐',
                                        'All ${platforms.length} clients aligned with Hub',
                                      )
                                    : unalignedReasons.join(' · '),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: unalignedReasons.isNotEmpty
                                      ? AppTheme.warning(context)
                                      : null,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: !supported
                                  ? null
                                  : () async {
                                      final result = await hub
                                          .importMissingFromClients();
                                      if (!context.mounted) return;
                                      showHubNotice(
                                        context,
                                        message: result.message,
                                        ok: result.ok,
                                      );
                                    },
                              icon: const Icon(
                                Icons.download_outlined,
                                size: 16,
                              ),
                              label: Text(tr('从客户端导入', 'Import missing')),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: !supported
                                  ? null
                                  : () async {
                                      final result = await hub
                                          .configureAllClients();
                                      if (!context.mounted) return;
                                      showHubNotice(
                                        context,
                                        message: result.message,
                                        ok: result.ok,
                                      );
                                    },
                              icon: const Icon(
                                Icons.flash_on_outlined,
                                size: 16,
                              ),
                              label: Text(tr('一键写入全部', 'Write all')),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final platform in platforms)
                          _ClientChip(
                            label: platform.label,
                            report: hub.clientAlignReport(platform.id),
                            onTap: !supported
                                ? null
                                : () => hub.configureClient(platform.id),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Divider(),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: const EdgeInsets.only(bottom: 6),
                      title: Text(
                        tr('查看客户端配置文件路径', 'View Client Config Paths'),
                        style: theme.textTheme.labelLarge,
                      ),
                      children: [
                        for (final platform in platforms)
                          DirectoryPathRow(
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
            ),
            const SizedBox(height: 20),
            SectionHeader(
              tr(
                '本地 MCP 列表（共 ${hub.servers.length} 个）',
                'Local MCP List (${hub.servers.length})',
              ),
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final searchField = TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search, size: 18),
                    hintText: tr(
                      '搜索名称、ID、命令或 URL…',
                      'Search name, ID, command, or URL…',
                    ),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: tr('清除搜索', 'Clear'),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                            icon: const Icon(Icons.clear, size: 16),
                          ),
                  ),
                );
                final chips = Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ChoiceChip(
                      label: Text(tr('全部', 'All')),
                      selected: _filter == _McpFilter.all,
                      onSelected: (_) =>
                          setState(() => _filter = _McpFilter.all),
                    ),
                    ChoiceChip(
                      label: Text(tr('已启用', 'Enabled')),
                      selected: _filter == _McpFilter.enabled,
                      onSelected: (_) =>
                          setState(() => _filter = _McpFilter.enabled),
                    ),
                    ChoiceChip(
                      label: Text(tr('运行中', 'Running')),
                      selected: _filter == _McpFilter.running,
                      onSelected: (_) =>
                          setState(() => _filter = _McpFilter.running),
                    ),
                    ChoiceChip(
                      label: Text(tr('异常', 'Errors')),
                      selected: _filter == _McpFilter.error,
                      onSelected: (_) =>
                          setState(() => _filter = _McpFilter.error),
                    ),
                  ],
                );
                if (constraints.maxWidth >= 720) {
                  return Row(
                    children: [
                      Expanded(child: searchField),
                      const SizedBox(width: 12),
                      chips,
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [searchField, const SizedBox(height: 10), chips],
                );
              },
            ),
            const SizedBox(height: 12),
            if (filtered.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 28,
                    horizontal: 16,
                  ),
                  child: Center(
                    child: Text(
                      hub.servers.isEmpty
                          ? tr(
                              '暂无 MCP 服务，点击右上角「添加 MCP」开始。',
                              'No MCP servers yet. Click Add MCP to get started.',
                            )
                          : tr('没有符合当前筛选条件的 MCP 服务', 'No matching MCP servers'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              )
            else
              for (var i = 0; i < filtered.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                ServerTile(
                  key: ValueKey(filtered[i].id),
                  serverId: filtered[i].id,
                ),
              ],
          ],
        ),
      ),
    );
  }
}

class _ClientChip extends StatelessWidget {
  const _ClientChip({
    required this.label,
    required this.report,
    required this.onTap,
  });

  final String label;
  final dynamic report;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final aligned = report?.isAligned == true;
    final checking = report == null;
    final dotColor = checking
        ? scheme.onSurfaceVariant
        : aligned
        ? AppTheme.success(context)
        : AppTheme.warning(context);
    final statusText = checking
        ? tr('检测中…', 'Checking…')
        : report.shortLabel as String;

    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      onPressed: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
          ),
          const SizedBox(width: 7),
          Text('$label · $statusText'),
        ],
      ),
    );
  }
}
