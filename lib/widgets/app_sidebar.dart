import 'package:flutter/material.dart';

import '../app_brand.dart';
import '../common/app_locale.dart';
import '../common/app_motion.dart';
import '../common/app_theme.dart';
import '../common/app_theme_mode.dart';
import '../features/app_update/app_update_screen.dart';

enum HubDestination {
  sync,
  mcp,
  logs,
  settings;

  String get label => switch (this) {
    HubDestination.sync => tr('同步中心', 'Sync Hub'),
    HubDestination.mcp => tr('MCP 服务', 'MCP Servers'),
    HubDestination.logs => tr('操作日志', 'Operation Logs'),
    HubDestination.settings => tr('设置与备份', 'Settings'),
  };

  IconData get icon => switch (this) {
    HubDestination.sync => Icons.sync_outlined,
    HubDestination.mcp => Icons.dns_outlined,
    HubDestination.logs => Icons.receipt_long_outlined,
    HubDestination.settings => Icons.tune_outlined,
  };

  IconData get activeIcon => switch (this) {
    HubDestination.sync => Icons.sync,
    HubDestination.mcp => Icons.dns,
    HubDestination.logs => Icons.receipt_long,
    HubDestination.settings => Icons.tune,
  };
}

/// 桌面端左侧常驻导航栏（窄窗口自动切换为 64px 紧凑图标栏）。
class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.compact,
    required this.serverCount,
    required this.logFailureCount,
    required this.webDavReady,
    required this.onOpenWebDavSettings,
  });

  final HubDestination selected;
  final ValueChanged<HubDestination> onSelect;
  final bool compact;
  final int serverCount;
  final int logFailureCount;
  final bool webDavReady;
  final VoidCallback onOpenWebDavSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final themePref = AppThemeMode.current;

    return Container(
      width: compact ? 64 : 224,
      color: AppTheme.sidebarBg(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 12 : 16,
              16,
              compact ? 12 : 16,
              12,
            ),
            child: compact
                ? Center(
                    child: _BrandMark(scheme: scheme),
                  )
                : Row(
                    children: [
                      _BrandMark(scheme: scheme),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppBrand.displayName,
                              style: theme.textTheme.titleSmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              tr('配置工作台', 'Agent Workbench'),
                              style: theme.textTheme.labelSmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
          const Divider(),
          const SizedBox(height: 10),
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10),
              children: [
                for (final dest in HubDestination.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: _SidebarNavItem(
                      destination: dest,
                      selected: dest == selected,
                      compact: compact,
                      badgeText: switch (dest) {
                        HubDestination.mcp => '$serverCount',
                        HubDestination.logs when logFailureCount > 0 =>
                          '$logFailureCount',
                        _ => null,
                      },
                      badgeAlert:
                          dest == HubDestination.logs && logFailureCount > 0,
                      onTap: () => onSelect(dest),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(),
          if (compact)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  IconButton(
                    tooltip: tr(
                      '主题：${themePref.label}（点击切换）',
                      'Theme: ${themePref.label}',
                    ),
                    onPressed: AppThemeMode.cycle,
                    icon: Icon(themePref.icon, size: 19),
                  ),
                  IconButton(
                    tooltip: tr('检查更新', 'Check for updates'),
                    onPressed: () =>
                        pushAppPage<void>(context, const AppUpdateScreen()),
                    icon: const Icon(Icons.upgrade, size: 19),
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: onOpenWebDavSettings,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.subtleBg(context),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.hairline(context)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: webDavReady
                                  ? AppTheme.success(context)
                                  : scheme.onSurfaceVariant.withValues(
                                      alpha: 0.45,
                                    ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              webDavReady
                                  ? tr('WebDAV 已配置', 'WebDAV Ready')
                                  : tr('WebDAV 未启用', 'WebDAV Off'),
                              style: theme.textTheme.labelSmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            size: 14,
                            color: scheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      IconButton(
                        tooltip: tr(
                          '主题：${themePref.label}（点击切换）',
                          'Theme: ${themePref.label}',
                        ),
                        visualDensity: VisualDensity.compact,
                        onPressed: AppThemeMode.cycle,
                        icon: Icon(themePref.icon, size: 18),
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () {
                          final next = AppLocale.isZh
                              ? AppLanguage.en
                              : AppLanguage.zh;
                          AppLocale.setLanguage(next);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: AppTheme.hairline(context),
                            ),
                          ),
                          child: Text(
                            AppLocale.isZh ? '中文' : 'EN',
                            style: theme.textTheme.labelSmall,
                          ),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: tr('检查更新', 'Check for updates'),
                        visualDensity: VisualDensity.compact,
                        onPressed: () =>
                            pushAppPage<void>(context, const AppUpdateScreen()),
                        icon: const Icon(Icons.upgrade, size: 18),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
      ),
      child: Icon(Icons.hub_outlined, size: 17, color: scheme.primary),
    );
  }
}

class _SidebarNavItem extends StatelessWidget {
  const _SidebarNavItem({
    required this.destination,
    required this.selected,
    required this.compact,
    required this.onTap,
    this.badgeText,
    this.badgeAlert = false,
  });

  final HubDestination destination;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;
  final String? badgeText;
  final bool badgeAlert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;
    final bg = selected ? scheme.primaryContainer : Colors.transparent;

    final item = Material(
      color: bg,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          height: 38,
          padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 10),
          alignment: Alignment.center,
          child: compact
              ? Icon(
                  selected ? destination.activeIcon : destination.icon,
                  size: 19,
                  color: selected ? scheme.primary : fg,
                )
              : Row(
                  children: [
                    Icon(
                      selected ? destination.activeIcon : destination.icon,
                      size: 18,
                      color: selected ? scheme.primary : fg,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        destination.label,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: selected ? scheme.onSurface : fg,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (badgeText != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: badgeAlert
                              ? scheme.errorContainer
                              : AppTheme.subtleBg(context),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          badgeText!,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 10.5,
                            color: badgeAlert
                                ? scheme.onErrorContainer
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );

    return compact ? Tooltip(message: destination.label, child: item) : item;
  }
}
