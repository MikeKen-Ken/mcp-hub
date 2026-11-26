import 'package:flutter/material.dart';

import '../common/app_locale.dart';
import '../common/app_motion.dart';
import '../common/app_theme_mode.dart';
import '../features/app_update/app_update_screen.dart';
import '../features/config_backup/config_backup.dart';
import '../features/hub_configuration/widgets/directory_path_row.dart';
import '../services/mcp_paths.dart';
import 'webdav_settings_screen.dart';

/// 「设置与备份」一级视图：常规与外观、WebDAV 同步、配置备份三个清晰子页。
class SettingsHubView extends StatefulWidget {
  const SettingsHubView({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<SettingsHubView> createState() => _SettingsHubViewState();
}

class _SettingsHubViewState extends State<SettingsHubView> {
  late int _tab = widget.initialTab.clamp(0, 2);

  @override
  void didUpdateWidget(covariant SettingsHubView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab) {
      _tab = widget.initialTab.clamp(0, 2);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(28, 22, 28, 32),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('设置与备份', 'Settings & Backup'),
                        style: theme.textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tr(
                          '调整外观主题、界面语言、WebDAV 远端同步与本地配置备份。',
                          'Configure theme, language, WebDAV sync, and local configuration backups.',
                        ),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<int>(
                segments: [
                  ButtonSegment(
                    value: 0,
                    icon: const Icon(Icons.palette_outlined, size: 16),
                    label: Text(tr('常规与外观', 'General')),
                  ),
                  ButtonSegment(
                    value: 1,
                    icon: const Icon(Icons.cloud_outlined, size: 16),
                    label: Text(tr('WebDAV 同步', 'WebDAV')),
                  ),
                  ButtonSegment(
                    value: 2,
                    icon: const Icon(Icons.folder_zip_outlined, size: 16),
                    label: Text(tr('配置备份', 'Backup')),
                  ),
                ],
                selected: {_tab},
                onSelectionChanged: (sel) => setState(() => _tab = sel.first),
              ),
            ),
            const SizedBox(height: 18),
            switch (_tab) {
              0 => const _GeneralSettingsTab(),
              1 => const WebDavSettingsScreen(embedded: true),
              _ => const ConfigBackupScreen(embedded: true),
            },
          ],
        ),
      ),
    );
  }
}

class _GeneralSettingsTab extends StatelessWidget {
  const _GeneralSettingsTab();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.contrast_outlined, size: 20),
                        const SizedBox(width: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tr('外观主题', 'Appearance Theme'),
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              tr(
                                '支持跟随系统或手动固定为浅色 / 深色模式',
                                'Follow system setting or force Light / Dark mode',
                              ),
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ],
                    ),
                    SegmentedButton<AppThemePreference>(
                      segments: [
                        ButtonSegment(
                          value: AppThemePreference.system,
                          label: Text(tr('跟随系统', 'System')),
                        ),
                        ButtonSegment(
                          value: AppThemePreference.light,
                          label: Text(tr('浅色', 'Light')),
                        ),
                        ButtonSegment(
                          value: AppThemePreference.dark,
                          label: Text(tr('深色', 'Dark')),
                        ),
                      ],
                      selected: {AppThemeMode.current},
                      onSelectionChanged: (selected) {
                        AppThemeMode.setPreference(selected.first);
                      },
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Divider(),
                ),
                Row(
                  children: [
                    const Icon(Icons.translate_outlined, size: 20),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr('界面语言', 'Interface Language'),
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            tr('默认使用简体中文', 'Defaults to Simplified Chinese'),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    SegmentedButton<AppLanguage>(
                      segments: const [
                        ButtonSegment(
                          value: AppLanguage.zh,
                          label: Text('中文'),
                        ),
                        ButtonSegment(
                          value: AppLanguage.en,
                          label: Text('EN'),
                        ),
                      ],
                      selected: {AppLocale.current},
                      onSelectionChanged: (selected) {
                        AppLocale.setLanguage(selected.first);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 6,
            ),
            leading: const Icon(Icons.upgrade),
            title: Text(tr('检查应用更新', 'Check for App Updates')),
            subtitle: Text(
              tr(
                '检查 GitHub Release 新版本并一键安装',
                'Check GitHub Releases for newer builds',
              ),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => pushAppPage<void>(context, const AppUpdateScreen()),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('本机数据目录', 'Local Data Directories'),
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                DirectoryPathRow(
                  label: tr('Hub 数据根目录', 'Hub data root'),
                  displayPath: McpPaths.hubDataRoot,
                  directoryPath: McpPaths.hubDataRoot,
                  enabled: McpPaths.hubDataRoot != null,
                ),
                DirectoryPathRow(
                  label: tr('MCP 仓库根目录', 'MCP repos root'),
                  displayPath: McpPaths.serversRoot,
                  directoryPath: McpPaths.serversRoot,
                  enabled: McpPaths.serversRoot != null,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
