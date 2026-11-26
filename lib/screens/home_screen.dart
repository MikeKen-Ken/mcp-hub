import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_brand.dart';
import '../common/app_locale.dart';
import '../common/app_motion.dart';
import '../controllers/hub_controller.dart';
import '../features/app_update/app_update_screen.dart';
import '../features/hub_configuration/widgets/hub_configuration_home_section.dart';
import '../features/hub_configuration/widgets/section_header.dart';
import '../features/operation_logs/operation_logs.dart';
import '../features/sync_status/sync_status.dart';
import '../services/mcp_paths.dart';
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
    final loading = context.select<HubController, bool>((hub) => hub.loading);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppBrand.displayName),
        actions: [
          IconButton(
            tooltip: tr('操作日志', 'Operation Logs'),
            onPressed: () {
              pushAppPage<void>(context, const OperationLogsScreen());
            },
            icon: const Icon(Icons.receipt_long_outlined),
          ),
          IconButton(
            tooltip: tr('WebDAV 设置', 'WebDAV settings'),
            onPressed: () {
              pushAppPage<void>(context, const WebDavSettingsScreen());
            },
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(
            tooltip: tr('检查更新', 'Check for updates'),
            onPressed: () {
              pushAppPage<void>(context, const AppUpdateScreen());
            },
            icon: const Icon(Icons.upgrade),
          ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: AppMotion.durationOf(context, AppMotion.standard),
        switchInCurve: AppMotion.emphasized,
        switchOutCurve: Curves.easeInCubic,
        child: loading
            ? const Center(
                key: ValueKey('loading'),
                child: CircularProgressIndicator(),
              )
            : ListView(
                key: const ValueKey('content'),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  Text(
                    tr('配置中心', 'Configuration Center'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tr(
                      '查看 Agent Hub 状态并使用常用管理功能。',
                      'View Agent Hub status and access common management features.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  SectionHeader(tr('快捷入口', 'Quick Access')),
                  const SizedBox(height: 8),
                  Consumer<HubController>(
                    builder: (_, hub, _) => CursorCountRefreshScope(
                      refresh: hub.refreshCursorItemCounts,
                      child: const HubConfigurationHomeSection(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SectionHeader(tr('操作日志', 'Operation Logs')),
                  const SizedBox(height: 8),
                  const RecentOperationLogsCard(),
                  const SizedBox(height: 20),
                  Text(
                    tr(
                      '数据目录：${McpPaths.hubDataRoot ?? "(不可用)"}',
                      'Data directory: ${McpPaths.hubDataRoot ?? "(unavailable)"}',
                    ),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
      ),
    );
  }
}
