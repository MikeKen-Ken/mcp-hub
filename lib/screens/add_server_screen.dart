import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/hub_controller.dart';
import '../models/mcp_transport.dart';

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
  bool _autoStart = false;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _repo.dispose();
    _command.dispose();
    _args.dispose();
    _url.dispose();
    super.dispose();
  }

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
        autoStart: _autoStart,
        cloneRepo: _clone,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('添加 MCP')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: '名称',
              hintText: '例如 tavily / filesystem',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _repo,
            decoration: const InputDecoration(
              labelText: 'Git 仓库 URL',
              hintText: 'https://github.com/org/mcp-server.git',
              border: OutlineInputBorder(),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Clone 到 ~/.mcp-hub/servers'),
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
              decoration: const InputDecoration(
                labelText: 'command',
                hintText: 'npx / python / node',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _args,
              decoration: const InputDecoration(
                labelText: 'args（空格分隔）',
                hintText: '-y @modelcontextprotocol/server-filesystem .',
                border: OutlineInputBorder(),
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
              decoration: const InputDecoration(
                labelText: '启动命令（可选，Hub 启停用）',
                hintText: 'npm / python / 可执行文件',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _args,
              decoration: const InputDecoration(
                labelText: '启动 args（空格分隔）',
                border: OutlineInputBorder(),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Hub 启动时自动拉起'),
              value: _autoStart,
              onChanged: (v) => setState(() => _autoStart = v),
            ),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('启用（写入客户端配置）'),
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
                : const Text('添加'),
          ),
        ],
      ),
    );
  }
}
