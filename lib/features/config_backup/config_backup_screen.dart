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
        title: const Text('从备份恢复？'),
        content: const Text(
          '将用备份中的 MCP 清单覆盖当前清单，并把 Skill / Command / Rule '
          '合并写回本机客户端目录（同名覆盖，不删除多余文件）。\n'
          'WebDAV 账号密码不会被改动。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('恢复'),
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
      showHubNotice(context, message: '打开目录失败：$error', ok: false);
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
      confirmButtonText: '选择目录',
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
        title: const Text('自动备份间隔'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '分钟',
            helperText: '最短 1 分钟，默认 10 分钟',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(controller.text.trim());
              Navigator.pop(ctx, value);
            },
            child: const Text('保存'),
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

  Future<void> _runAutoBackupNow() async {
    final hub = context.read<HubController>();
    final result = await hub.runAutoBackupNow();
    if (!mounted) return;
    setState(() => _lastPath = result.path);
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
      showHubNotice(context, message: '打开目录失败：$error', ok: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<HubController>();
    final supported = hub.isDesktopSupported;
    final automatic = hub.autoConfigBackup;

    return Scaffold(
      appBar: AppBar(title: const Text('配置备份')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '定期导出本机 MCP 清单与 Agent 配置（Skill / Command / Rule）为 zip，'
            '用于误下载或误上传后的恢复。不含 WebDAV 密码，也不含 MCP 仓库克隆目录。',
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
                    title: const Text('导出 / 导入'),
                    subtitle: Text(
                      supported ? '建议定期保存到网盘或移动硬盘' : '当前平台不支持配置备份',
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
                          label: const Text('导出备份'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: !supported || _busy ? null : _import,
                          icon: const Icon(Icons.download_outlined),
                          label: const Text('从备份恢复'),
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
                          tooltip: '打开所在目录',
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
                    title: const Text('自动备份'),
                    subtitle: Text(
                      automatic.settings.enabled
                          ? '每 ${automatic.settings.intervalMinutes} 分钟备份一次，自动文件保留 7 天'
                          : '关闭时不会在后台生成备份',
                    ),
                    value: automatic.settings.enabled,
                    onChanged: supported && automatic.initialized
                        ? _setAutoBackupEnabled
                        : null,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.timer_outlined),
                    title: const Text('备份间隔'),
                    subtitle: Text('${automatic.settings.intervalMinutes} 分钟'),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: supported ? _editAutoBackupInterval : null,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(
                      automatic.settings.directory == null
                          ? '备份目录（默认）'
                          : '备份目录（自定义）',
                    ),
                    subtitle: SelectableText(
                      automatic.effectiveDirectory ?? '当前平台不可用',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: supported ? _chooseAutoBackupDirectory : null,
                  ),
                  if (automatic.settings.directory != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: _useDefaultAutoBackupDirectory,
                        child: const Text('恢复默认目录'),
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
                          label: const Text('立即备份'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.outlined(
                        tooltip: '打开自动备份目录',
                        onPressed: supported ? _openAutoBackupDirectory : null,
                        icon: const Icon(Icons.folder_open_outlined),
                      ),
                    ],
                  ),
                  if (automatic.lastBackupAt != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '最近备份：${automatic.lastBackupAt!.toLocal()}',
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
            '数据目录：${McpPaths.hubDataRoot ?? "(不可用)"}',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}
