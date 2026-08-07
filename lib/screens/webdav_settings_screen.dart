import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/hub_controller.dart';
import '../webdav/webdav_config.dart';

class WebDavSettingsScreen extends StatefulWidget {
  const WebDavSettingsScreen({super.key});

  @override
  State<WebDavSettingsScreen> createState() => _WebDavSettingsScreenState();
}

class _WebDavSettingsScreenState extends State<WebDavSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _urlController;
  late final TextEditingController _userController;
  late final TextEditingController _passController;
  late final TextEditingController _pathController;

  bool _enabled = false;
  bool _autoSync = true;
  bool _autoPull = true;
  int _pollSeconds = WebDavConfig.defaultPollIntervalSeconds;
  int _pushDebounceSeconds = WebDavConfig.defaultPushDebounceSeconds;
  bool _obscurePassword = true;
  bool _testing = false;
  bool _saving = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    final config = context.read<HubController>().webDavConfig;
    _enabled = config.enabled;
    _autoSync = config.autoSync;
    _autoPull = config.autoPull;
    _pollSeconds =
        WebDavConfig.clampPollIntervalSeconds(config.pollIntervalSeconds);
    _pushDebounceSeconds =
        WebDavConfig.clampPushDebounceSeconds(config.pushDebounceSeconds);
    _urlController = TextEditingController(text: config.serverUrl);
    _userController = TextEditingController(text: config.username);
    _passController = TextEditingController(text: config.password);
    _pathController = TextEditingController(text: config.remotePath);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _userController.dispose();
    _passController.dispose();
    _pathController.dispose();
    super.dispose();
  }

  WebDavConfig _buildConfig() {
    return WebDavConfig(
      enabled: _enabled,
      serverUrl: _urlController.text.trim(),
      username: _userController.text.trim(),
      password: _passController.text,
      remotePath: _pathController.text.trim().isEmpty
          ? '/McpHub'
          : _pathController.text.trim(),
      autoSync: _autoSync,
      autoPull: _autoPull,
      pollIntervalSeconds: WebDavConfig.clampPollIntervalSeconds(_pollSeconds),
      pushDebounceSeconds:
          WebDavConfig.clampPushDebounceSeconds(_pushDebounceSeconds),
    );
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final ok = await context.read<HubController>().testWebDav(_buildConfig());
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = ok ? '连接成功' : '连接失败，请检查地址与账号';
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    await context.read<HubController>().saveWebDavConfig(_buildConfig());
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          !_enabled
              ? '已保存'
              : (!_autoSync && !_autoPull)
                  ? '已保存；仅手动同步'
                  : '已保存',
        ),
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WebDAV 同步')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Card(
              child: SwitchListTile(
                title: const Text('启用 WebDAV 同步'),
                subtitle: const Text('连接配置仅保存在本机，不同步密码到远端'),
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
              ),
            ),
            if (_enabled) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: '服务器地址',
                  hintText: 'https://dav.jianguoyun.com/dav/',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (!_enabled) return null;
                  if (v == null || v.trim().isEmpty) return '请输入服务器地址';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _userController,
                decoration: const InputDecoration(
                  labelText: '用户名',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (!_enabled) return null;
                  if (v == null || v.trim().isEmpty) return '请输入用户名';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: '密码 / 应用密码',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (v) {
                  if (!_enabled) return null;
                  if (v == null || v.isEmpty) return '请输入密码';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pathController,
                decoration: const InputDecoration(
                  labelText: '远端目录',
                  hintText: '/McpHub',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('变更后自动上传'),
                value: _autoSync,
                onChanged: (v) => setState(() => _autoSync = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('启动 / 定时自动拉取'),
                value: _autoPull,
                onChanged: (v) => setState(() => _autoPull = v),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('拉取间隔：${_pollSeconds}s'),
                subtitle: Slider(
                  min: WebDavConfig.minPollIntervalSeconds.toDouble(),
                  max: WebDavConfig.maxPollIntervalSeconds.toDouble(),
                  divisions: 9,
                  value: _pollSeconds.toDouble(),
                  label: '${_pollSeconds}s',
                  onChanged: (v) => setState(() => _pollSeconds = v.round()),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('上传防抖：${_pushDebounceSeconds}s'),
                subtitle: Slider(
                  min: WebDavConfig.minPushDebounceSeconds.toDouble(),
                  max: WebDavConfig.maxPushDebounceSeconds.toDouble(),
                  divisions: 11,
                  value: _pushDebounceSeconds.toDouble(),
                  label: '${_pushDebounceSeconds}s',
                  onChanged: (v) =>
                      setState(() => _pushDebounceSeconds = v.round()),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _testing ? null : _testConnection,
                icon: _testing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_tethering),
                label: const Text('测试连接'),
              ),
              if (_testResult != null) ...[
                const SizedBox(height: 8),
                Text(_testResult!),
              ],
              const SizedBox(height: 12),
              Text(
                '同步内容：MCP 清单（仓库 URL、command/args 等）。\n'
                '不同步：WebDAV 密码、本机路径、cwd、env 密钥、MCP 开/关状态、内置 hubMCP。\n'
                '换电脑后：配置好同一 WebDAV → 拉取 → 再按需 clone / 一键写入 Cursor。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }
}
