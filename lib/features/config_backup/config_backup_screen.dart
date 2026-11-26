import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../common/app_locale.dart';
import '../../controllers/hub_controller.dart';
import '../../services/directory_opener.dart';
import '../../services/mcp_paths.dart';
import '../../widgets/hub_notice/hub_notice.dart';
import 'auto_config_backup_service.dart';

/// 配置备份：导出 zip / 从 zip 恢复。
class ConfigBackupScreen extends StatefulWidget {
  const ConfigBackupScreen({super.key});

  @override
  State<ConfigBackupScreen> createState() => _ConfigBackupScreenState();
}

class _ConfigBackupScreenState extends State<ConfigBackupScreen> {
  bool _busy = false;
  String? _lastPath;

  Future<void> _export() async {
    final hub = context.read<HubController>();
    if (!hub.isDesktopSupported) return;

    final location = await getSaveLocation(
      suggestedName: hub.configBackup.suggestedFileName(),
      acceptedTypeGroups: [
        const XTypeGroup(label: 'zip', extensions: ['zip']),
      ],
    );
    if (location == null) return;
    if (!mounted) return;

    setState(() => _busy = true);
    final result = await hub.exportConfigBackup(location.path);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _lastPath = result.path;
    });
    showHubNotice(context, message: result.message, ok: result.ok);
  }

  Future<void> _import() async {
    final hub = context.read<HubController>();
    if (!hub.isDesktopSupported) return;

    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'zip', extensions: ['zip']),
      ],
    );
    if (file == null) return;
    if (!mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('确认从备份恢复？', 'Restore from backup?')),
        content: Text(
          tr(
            '备份中的 MCP 清单会替换当前清单，Skill / Command / Rule / Hook 资源会合并到本地客户端目录'
                '（覆盖同名项，保留多余项）。\n'
                'WebDAV 账号密码不会被修改。',
            'The backup catalog will replace the current catalog, and Skill / Command / Rule / Hook '
                'resources will be merged into local client directories (matching items are replaced; extras are kept).\n'
                'WebDAV credentials will not be changed.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('确认恢复', 'Restore')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    final result = await hub.importConfigBackup(file.path);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _lastPath = result.path;
    });
    showHubNotice(context, message: result.message, ok: result.ok);
  }

  Future<void> _openLast() async {
    final path = _lastPath;
    if (path == null) return;
    try {
      await DirectoryOpener.open(p.dirname(path));
    } catch (error) {
      if (!mounted) return;
      showHubNotice(
        context,
        message: tr('打开目录失败：$error', 'Failed to open directory: $error'),
        ok: false,
      );
    }
  }

  Future<void> _setAutoBackupEnabled(bool enabled) async {
    final hub = context.read<HubController>();
    await hub.saveAutoBackupSettings(
      hub.autoConfigBackup.settings.copyWith(enabled: enabled),
    );
  }

  Future<void> _chooseAutoBackupDirectory() async {
    final hub = context.read<HubController>();
    final selected = await getDirectoryPath(
      initialDirectory: hub.autoConfigBackup.effectiveDirectory,
      confirmButtonText: tr('选择目录', 'Choose directory'),
    );
    if (selected == null || !mounted) return;
    await hub.saveAutoBackupSettings(
      hub.autoConfigBackup.settings.copyWith(directory: selected),
    );
  }

  Future<void> _useDefaultAutoBackupDirectory() async {
    final hub = context.read<HubController>();
    await hub.saveAutoBackupSettings(
      hub.autoConfigBackup.settings.copyWith(clearDirectory: true),
    );
  }

  Future<void> _editAutoBackupInterval() async {
    final hub = context.read<HubController>();
    final controller = TextEditingController(
      text: '${hub.autoConfigBackup.settings.intervalMinutes}',
    );
    final minutes = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('自动备份间隔', 'Automatic backup interval')),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: tr('分钟', 'Minutes'),
            helperText: tr('最少 1 分钟，默认 10 分钟', 'Minimum 1 minute; default 10 minutes'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(controller.text.trim());
              Navigator.pop(ctx, value);
            },
            child: Text(tr('保存', 'Save')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (minutes == null || !mounted) return;
    await hub.saveAutoBackupSettings(
      hub.autoConfigBackup.settings.copyWith(intervalMinutes: minutes),
    );
  }

  Future<void> _editAutoBackupRetention() async {
    final hub = context.read<HubController>();
    final controller = TextEditingController(
      text: '${hub.autoConfigBackup.settings.retentionDays}',
    );
    final days = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('自动备份保留天数', 'Automatic backup retention')),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: tr('天数', 'Days'),
            helperText: tr(
              '仅清理当前目录中自动备份产生的压缩包；最少 1 天，默认 14 天',
              'Only automatic backup zips in the current directory are cleaned; minimum 1 day, default 14 days',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(controller.text.trim());
              Navigator.pop(ctx, value);
            },
            child: Text(tr('保存', 'Save')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (days == null || !mounted) return;
    await hub.saveAutoBackupSettings(
      hub.autoConfigBackup.settings.copyWith(retentionDays: days),
    );
  }

  Future<void> _runAutoBackupNow() async {
    final hub = context.read<HubController>();
    final result = await hub.runAutoBackupNow();
    if (!mounted) return;
    setState(() => _lastPath = result.path);
    showHubNotice(context, message: result.message, ok: result.ok);
  }

  Future<void> _cleanupExpiredAutoBackups() async {
    final hub = context.read<HubController>();
    final result = await hub.cleanupExpiredAutoBackups();
    if (!mounted) return;
    showHubNotice(context, message: result.message, ok: result.ok);
  }

  Future<void> _openAutoBackupDirectory() async {
    final path = context
        .read<HubController>()
        .autoConfigBackup
        .effectiveDirectory;
    if (path == null) return;
    try {
      await DirectoryOpener.open(path);
    } catch (error) {
      if (!mounted) return;
      showHubNotice(
        context,
        message: tr('打开目录失败：$error', 'Failed to open directory: $error'),
        ok: false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<HubController>();
    final supported = hub.isDesktopSupported;
    final automatic = hub.autoConfigBackup;

    return Scaffold(
      appBar: AppBar(title: Text(tr('配置备份', 'Configuration Backup'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            tr(
              '定期把本地 MCP 清单与 Agent 配置（Skill / Command / Rule / Hook）导出为 zip，'
                  '以便在误下载或误上传后恢复。导出包不包含 WebDAV 密码及 MCP 仓库克隆。',
              'Periodically export the local MCP catalog and Agent configuration (Skill / Command / Rule / Hook) to a zip '
                  'for recovery after an accidental download or upload. WebDAV passwords and MCP repository clones are excluded.',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.folder_zip_outlined),
                    title: Text(tr('导出 / 导入', 'Export / Import')),
                    subtitle: Text(
                      supported
                          ? tr(
                              '建议定期备份到网盘或外置硬盘',
                              'Consider saving regularly to cloud storage or an external drive',
                            )
                          : tr(
                              '当前平台不支持配置备份',
                              'Configuration backup is not supported on this platform',
                            ),
                    ),
                  ),
                  if (_busy) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: !supported || _busy ? null : _export,
                          icon: const Icon(Icons.upload_file_outlined),
                          label: Text(tr('导出备份', 'Export backup')),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: !supported || _busy ? null : _import,
                          icon: const Icon(Icons.download_outlined),
                          label: Text(tr('从备份恢复', 'Restore backup')),
                        ),
                      ),
                    ],
                  ),
                  if (_lastPath != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            _lastPath!,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                        IconButton(
                          tooltip: tr('打开所在目录', 'Open containing directory'),
                          onPressed: _openLast,
                          icon: const Icon(Icons.folder_open_outlined),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.schedule_outlined),
                    title: Text(tr('自动备份', 'Automatic Backup')),
                    subtitle: Text(
                      automatic.settings.enabled
                          ? tr(
                              '每 ${automatic.settings.intervalMinutes} 分钟检查并备份；自动备份保留 ${automatic.settings.retentionDays} 天',
                              'Back up every ${automatic.settings.intervalMinutes} minutes; automatic files are kept for ${automatic.settings.retentionDays} days',
                            )
                          : tr(
                              '关闭后不会在后台自动创建备份',
                              'No backups are created in the background when disabled',
                            ),
                    ),
                    value: automatic.settings.enabled,
                    onChanged: supported && automatic.initialized
                        ? _setAutoBackupEnabled
                        : null,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.timer_outlined),
                    title: Text(tr('备份间隔', 'Backup interval')),
                    subtitle: Text(
                      tr(
                        '${automatic.settings.intervalMinutes} 分钟',
                        '${automatic.settings.intervalMinutes} minutes',
                      ),
                    ),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: supported ? _editAutoBackupInterval : null,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.auto_delete_outlined),
                    title: Text(tr('保留天数', 'Retention')),
                    subtitle: Text(
                      tr(
                        '${automatic.settings.retentionDays} 天（仅清理当前目录的自动备份）',
                        '${automatic.settings.retentionDays} days (only automatic backups in the current directory are cleaned)',
                      ),
                    ),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: supported ? _editAutoBackupRetention : null,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(
                      automatic.settings.directory == null
                          ? tr('备份目录（默认）', 'Backup directory (default)')
                          : tr('备份目录（自定义）', 'Backup directory (custom)'),
                    ),
                    subtitle: SelectableText(
                      automatic.effectiveDirectory ??
                          tr('当前平台不可用', 'Unavailable on this platform'),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: supported ? _chooseAutoBackupDirectory : null,
                  ),
                  if (automatic.settings.directory != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: _useDefaultAutoBackupDirectory,
                        child: Text(tr('恢复默认目录', 'Restore default directory')),
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed:
                              !supported ||
                                  automatic.status == AutoBackupStatus.backingUp
                              ? null
                              : _runAutoBackupNow,
                          icon: const Icon(Icons.backup_outlined),
                          label: Text(tr('立即备份', 'Back up now')),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: supported
                              ? _cleanupExpiredAutoBackups
                              : null,
                          icon: const Icon(Icons.cleaning_services_outlined),
                          label: Text(tr('清理过期', 'Clean up expired')),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.outlined(
                        tooltip: tr('打开自动备份目录', 'Open automatic backup directory'),
                        onPressed: supported ? _openAutoBackupDirectory : null,
                        icon: const Icon(Icons.folder_open_outlined),
                      ),
                    ],
                  ),
                  if (automatic.lastBackupAt != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      tr(
                        '最近备份：${automatic.lastBackupAt!.toLocal()}',
                        'Last backup: ${automatic.lastBackupAt!.toLocal()}',
                      ),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                  if (automatic.lastError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      automatic.lastError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            tr(
              '数据目录：${McpPaths.hubDataRoot ?? "(不可用)"}',
              'Data directory: ${McpPaths.hubDataRoot ?? "(unavailable)"}',
            ),
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}
