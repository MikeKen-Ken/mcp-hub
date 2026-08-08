import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../controllers/hub_controller.dart';
import '../../services/directory_opener.dart';
import '../../services/mcp_paths.dart';

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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
  }

  Future<void> _openLast() async {
    final path = _lastPath;
    if (path == null) return;
    try {
      await DirectoryOpener.open(p.dirname(path));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('打开目录失败：$error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<HubController>();
    final supported = hub.isDesktopSupported;

    return Scaffold(
      appBar: AppBar(title: const Text('配置备份')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '定期导出本机 MCP 清单与 Agent 配置（Skill / Command / Rule）为 zip，'
            '用于误同步或误上传后的恢复。不含 WebDAV 密码，也不含 MCP 仓库克隆目录。',
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
                      supported
                          ? '建议定期保存到网盘或移动硬盘'
                          : '当前平台不支持配置备份',
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
          Text(
            '数据目录：${McpPaths.hubDataRoot ?? "(不可用)"}',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}
