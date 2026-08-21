import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../controllers/hub_controller.dart';
import '../../widgets/hub_notice/hub_notice.dart';
import '../../services/directory_opener.dart';
import '../../services/mcp_paths.dart';
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
        title: const Text('Restore from backup?'),
        content: const Text(
          'The backup catalog will replace the current catalog, and Skill / Command / Rule / Hook '
          'resources will be merged into local client directories (matching items are replaced; extras are kept).\n'
          'WebDAV credentials will not be changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore'),
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
        message: 'Failed to open directory: $error',
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
      confirmButtonText: 'Choose directory',
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
        title: const Text('Automatic backup interval'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Minutes',
            helperText: 'Minimum 1 minute; default 10 minutes',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(controller.text.trim());
              Navigator.pop(ctx, value);
            },
            child: const Text('Save'),
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
        title: const Text('Automatic backup retention'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Days',
            helperText:
                'Only automatic backup zips in the current directory are cleaned; minimum 1 day, default 14 days',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(controller.text.trim());
              Navigator.pop(ctx, value);
            },
            child: const Text('Save'),
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
        message: 'Failed to open directory: $error',
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
      appBar: AppBar(title: const Text('Configuration Backup')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Periodically export the local MCP catalog and Agent configuration (Skill / Command / Rule / Hook) to a zip '
            'for recovery after an accidental download or upload. WebDAV passwords and MCP repository clones are excluded.',
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
                    title: const Text('Export / Import'),
                    subtitle: Text(
                      supported
                          ? 'Consider saving regularly to cloud storage or an external drive'
                          : 'Configuration backup is not supported on this platform',
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
                          label: const Text('Export backup'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: !supported || _busy ? null : _import,
                          icon: const Icon(Icons.download_outlined),
                          label: const Text('Restore backup'),
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
                          tooltip: 'Open containing directory',
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
                    title: const Text('Automatic Backup'),
                    subtitle: Text(
                      automatic.settings.enabled
                          ? 'Back up every ${automatic.settings.intervalMinutes} minutes; automatic files are kept for ${automatic.settings.retentionDays} days'
                          : 'No backups are created in the background when disabled',
                    ),
                    value: automatic.settings.enabled,
                    onChanged: supported && automatic.initialized
                        ? _setAutoBackupEnabled
                        : null,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.timer_outlined),
                    title: const Text('Backup interval'),
                    subtitle: Text(
                      '${automatic.settings.intervalMinutes} minutes',
                    ),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: supported ? _editAutoBackupInterval : null,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.auto_delete_outlined),
                    title: const Text('Retention'),
                    subtitle: Text(
                      '${automatic.settings.retentionDays} days (only automatic backups in the current directory are cleaned)',
                    ),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: supported ? _editAutoBackupRetention : null,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(
                      automatic.settings.directory == null
                          ? 'Backup directory (default)'
                          : 'Backup directory (custom)',
                    ),
                    subtitle: SelectableText(
                      automatic.effectiveDirectory ??
                          'Unavailable on this platform',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: supported ? _chooseAutoBackupDirectory : null,
                  ),
                  if (automatic.settings.directory != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: _useDefaultAutoBackupDirectory,
                        child: const Text('Restore default directory'),
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
                          label: const Text('Back up now'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: supported
                              ? _cleanupExpiredAutoBackups
                              : null,
                          icon: const Icon(Icons.cleaning_services_outlined),
                          label: const Text('Clean up expired'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.outlined(
                        tooltip: 'Open automatic backup directory',
                        onPressed: supported ? _openAutoBackupDirectory : null,
                        icon: const Icon(Icons.folder_open_outlined),
                      ),
                    ],
                  ),
                  if (automatic.lastBackupAt != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Last backup: ${automatic.lastBackupAt!.toLocal()}',
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
            'Data directory: ${McpPaths.hubDataRoot ?? "(unavailable)"}',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}
