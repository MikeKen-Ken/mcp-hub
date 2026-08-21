import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/hub_controller.dart';
import '../widgets/hub_notice/hub_notice.dart';
import '../features/config_backup/config_backup.dart';
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
    _pollSeconds = WebDavConfig.clampPollIntervalSeconds(
      config.pollIntervalSeconds,
    );
    _pushDebounceSeconds = WebDavConfig.clampPushDebounceSeconds(
      config.pushDebounceSeconds,
    );
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
          ? WebDavConfig.defaultRemotePath
          : _pathController.text.trim(),
      autoSync: _autoSync,
      autoPull: _autoPull,
      pollIntervalSeconds: WebDavConfig.clampPollIntervalSeconds(_pollSeconds),
      pushDebounceSeconds: WebDavConfig.clampPushDebounceSeconds(
        _pushDebounceSeconds,
      ),
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
      _testResult = ok
          ? 'Connection successful'
          : 'Connection failed; check the URL and credentials';
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    await context.read<HubController>().saveWebDavConfig(_buildConfig());
    if (!mounted) return;
    setState(() => _saving = false);
    showHubNotice(
      context,
      message: !_enabled
          ? 'Saved'
          : (!_autoSync && !_autoPull)
          ? 'Saved; manual download/upload only'
          : 'Saved',
      ok: true,
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WebDAV Download/Upload')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                leading: const Icon(Icons.folder_zip_outlined),
                title: const Text('Configuration Backup'),
                subtitle: const Text(
                  'Export, restore, and automatically back up local MCP and Agent configuration',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ConfigBackupScreen(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: SwitchListTile(
                title: const Text('Enable WebDAV Download/Upload'),
                subtitle: const Text(
                  'Connection settings stay on this computer; the password is never uploaded',
                ),
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
              ),
            ),
            if (_enabled) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'Server URL',
                  hintText: 'https://dav.jianguoyun.com/dav/',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (!_enabled) return null;
                  if (v == null || v.trim().isEmpty)
                    return 'Enter a server URL';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _userController,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (!_enabled) return null;
                  if (v == null || v.trim().isEmpty) return 'Enter a username';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Password / App Password',
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
                  if (v == null || v.isEmpty) return 'Enter a password';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pathController,
                decoration: const InputDecoration(
                  labelText: 'Remote directory',
                  hintText: WebDavConfig.defaultRemotePath,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Upload changes automatically'),
                subtitle: const Text(
                  'Package the MCP catalog as catalog.zip and replace the remote copy',
                ),
                value: _autoSync,
                onChanged: (v) => setState(() => _autoSync = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Merge automatically on startup / schedule'),
                subtitle: const Text(
                  'Download catalog.zip and merge it with local data without replacing the whole package',
                ),
                value: _autoPull,
                onChanged: (v) => setState(() => _autoPull = v),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Merge interval: ${_pollSeconds}s'),
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
                title: Text('Upload debounce: ${_pushDebounceSeconds}s'),
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
                label: const Text('Test connection'),
              ),
              if (_testResult != null) ...[
                const SizedBox(height: 8),
                Text(_testResult!),
              ],
              const SizedBox(height: 12),
              Text(
                'Downloads/uploads use fixed-name packages for the MCP catalog and Skill / Command / Rule / Hook resources '
                '(catalog.zip, skills.zip, commands.zip, rules.zip, hooks.zip); files do not accumulate by date.\n'
                'Uploads include version timestamps: the catalog uses catalog.json updatedAt; resource packages include '
                'their upload time. Older packages fall back to the WebDAV file modification time.\n'
                'Download replaces the corresponding cache or catalog; Merge combines it with local data '
                '(catalogs use a three-way merge; resources replace matching items and keep local extras).\n'
                'Never transferred: WebDAV password, local paths, cwd, environment secrets, MCP enabled state, or built-in hubMCP.\n'
                'Legacy catalog.json and {skills|commands|rules|hooks}/cursor/ directories are read only when packages are absent.\n'
                'To move to another computer: configure the same WebDAV → download or merge the catalog → '
                'download Agent configuration to the cache → apply it to Cursor → clone repositories or write client configuration as needed.',
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
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
