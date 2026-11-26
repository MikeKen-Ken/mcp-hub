import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../common/app_locale.dart';
import '../controllers/hub_controller.dart';
import '../models/mcp_transport.dart';
import '../services/repo_name.dart';
import '../widgets/hub_notice/hub_notice.dart';

class AddServerScreen extends StatefulWidget {
  const AddServerScreen({super.key});

  @override
  State<AddServerScreen> createState() => _AddServerScreenState();
}

class _AddServerScreenState extends State<AddServerScreen> {
  final _name = TextEditingController();
  final _repo = TextEditingController();
  final _command = TextEditingController();
  final _args = TextEditingController();
  final _url = TextEditingController();
  McpTransport _transport = McpTransport.stdio;
  bool _clone = true;
  bool _enabled = true;
  bool _busy = false;
  bool _nameEdited = false;

  @override
  void initState() {
    super.initState();
    _repo.addListener(_onRepoChanged);
  }

  @override
  void dispose() {
    _repo.removeListener(_onRepoChanged);
    _name.dispose();
    _repo.dispose();
    _command.dispose();
    _args.dispose();
    _url.dispose();
    super.dispose();
  }

  void _onRepoChanged() {
    if (_nameEdited) return;
    final inferred = RepoName.fromGitUrl(_repo.text);
    if (inferred == null) return;
    if (_name.text == inferred) return;
    _name.text = inferred;
    setState(() {});
  }

  String? get _inferredName => RepoName.fromGitUrl(_repo.text);

  Future<void> _submit() async {
    final hub = context.read<HubController>();
    setState(() => _busy = true);
    try {
      final args = _args.text
          .trim()
          .split(RegExp(r'\s+'))
          .where((e) => e.isNotEmpty)
          .toList();
      await hub.addServer(
        name: _name.text,
        transport: _transport,
        repoUrl: _repo.text,
        command: _command.text,
        args: args,
        url: _url.text,
        enabled: _enabled,
        cloneRepo: _clone,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      showHubNotice(context, message: '$error', ok: false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inferred = _inferredName;

    return Scaffold(
      appBar: AppBar(title: Text(tr('添加 MCP', 'Add MCP'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _repo,
            decoration: InputDecoration(
              labelText: tr('Git 仓库 URL', 'Git repository URL'),
              hintText: 'https://github.com/org/mcp-server.git',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            onChanged: (_) {
              if (!_nameEdited) setState(() => _nameEdited = true);
            },
            decoration: InputDecoration(
              labelText: tr('名称（可选）', 'Name (optional)'),
              hintText: inferred ?? tr('自动使用仓库名', 'Use repository name automatically'),
              border: const OutlineInputBorder(),
              suffixIcon: _nameEdited
                  ? IconButton(
                      tooltip: tr('恢复仓库名', 'Restore repository name'),
                      onPressed: () {
                        final value = RepoName.fromGitUrl(_repo.text);
                        _name.text = value ?? '';
                        setState(() => _nameEdited = false);
                      },
                      icon: const Icon(Icons.restart_alt),
                    )
                  : null,
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('克隆到 ~/.mcp-hub/servers', 'Clone to ~/.mcp-hub/servers')),
            value: _clone,
            onChanged: (v) => setState(() => _clone = v),
          ),
          const SizedBox(height: 8),
          SegmentedButton<McpTransport>(
            segments: const [
              ButtonSegment(
                value: McpTransport.stdio,
                label: Text('stdio'),
                icon: Icon(Icons.terminal),
              ),
              ButtonSegment(
                value: McpTransport.http,
                label: Text('HTTP'),
                icon: Icon(Icons.http),
              ),
            ],
            selected: {_transport},
            onSelectionChanged: (set) {
              setState(() => _transport = set.first);
            },
          ),
          const SizedBox(height: 16),
          if (_transport == McpTransport.stdio) ...[
            TextField(
              controller: _command,
              decoration: InputDecoration(
                labelText: tr('启动命令 (command)', 'command'),
                hintText: 'npx',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _args,
              decoration: InputDecoration(
                labelText: tr('命令参数 (args)', 'args'),
                hintText: '-y @scope/mcp-server',
                border: const OutlineInputBorder(),
              ),
            ),
          ] else ...[
            TextField(
              controller: _url,
              decoration: const InputDecoration(
                labelText: 'URL',
                hintText: 'http://127.0.0.1:18765/mcp',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _command,
              decoration: InputDecoration(
                labelText: tr('启动命令（可选）', 'Start command (optional)'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _args,
              decoration: InputDecoration(
                labelText: tr('启动参数', 'Start args'),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('启用', 'Enabled')),
            subtitle: _transport == McpTransport.http
                ? Text(
                    tr(
                      '启用后，若填写了启动命令，Hub 会自动拉起该进程',
                      'When enabled, Hub starts the process if a start command is provided',
                    ),
                  )
                : Text(
                    tr(
                      '启用后，若填写了命令，Hub 会自动拉起该进程',
                      'When enabled, Hub starts the process if a command is provided',
                    ),
                  ),
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(tr('添加', 'Add')),
          ),
        ],
      ),
    );
  }
}
