import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../common/app_motion.dart';
import '../controllers/hub_controller.dart';
import '../features/app_update/app_update_screen.dart';
import '../features/hub_configuration/widgets/sync_hub_view.dart';
import '../features/local_mcp/mcp_workbench_view.dart';
import '../features/operation_logs/operation_logs.dart';
import '../features/sync_status/sync_status.dart';
import '../widgets/app_sidebar.dart';
import 'settings_hub_view.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  HubDestination _selected = HubDestination.sync;
  int _settingsInitialTab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(maybePromptAppUpdate(context));
    });
  }

  void _selectDestination(HubDestination dest, {int settingsTab = 0}) {
    setState(() {
      _selected = dest;
      if (dest == HubDestination.settings) {
        _settingsInitialTab = settingsTab;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final loading = context.select<HubController, bool>((hub) => hub.loading);
    final serverCount = context.select<HubController, int>(
      (hub) => hub.servers.length,
    );
    final failureCount = context.select<HubController, int>(
      (hub) => hub.operationLogs.failureCount,
    );
    final webDavReady = context.select<HubController, bool>(
      (hub) => hub.isWebDavReady,
    );
    final refreshCounts = context.read<HubController>().refreshCursorItemCounts;

    return Scaffold(
      body: AnimatedSwitcher(
        duration: AppMotion.durationOf(context, AppMotion.standard),
        switchInCurve: AppMotion.emphasized,
        switchOutCurve: Curves.easeInCubic,
        child: loading
            ? const Center(
                key: ValueKey('loading'),
                child: CircularProgressIndicator(),
              )
            : LayoutBuilder(
                key: const ValueKey('workbench'),
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 780;
                  return Row(
                    children: [
                      AppSidebar(
                        selected: _selected,
                        onSelect: (dest) => _selectDestination(dest),
                        compact: compact,
                        serverCount: serverCount,
                        logFailureCount: failureCount,
                        webDavReady: webDavReady,
                        onOpenWebDavSettings: () => _selectDestination(
                          HubDestination.settings,
                          settingsTab: 1,
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: CursorCountRefreshScope(
                          refresh: refreshCounts,
                          child: switch (_selected) {
                            HubDestination.sync => SyncHubView(
                              onOpenMcp: () =>
                                  _selectDestination(HubDestination.mcp),
                              onOpenLogs: () =>
                                  _selectDestination(HubDestination.logs),
                              onOpenWebDavSettings: () => _selectDestination(
                                HubDestination.settings,
                                settingsTab: 1,
                              ),
                            ),
                            HubDestination.mcp => const McpWorkbenchView(),
                            HubDestination.logs =>
                              const OperationLogsScreen(embedded: true),
                            HubDestination.settings => SettingsHubView(
                              initialTab: _settingsInitialTab,
                            ),
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}
