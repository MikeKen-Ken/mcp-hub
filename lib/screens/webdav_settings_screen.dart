import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../common/app_locale.dart';
import '../common/app_motion.dart';
import '../controllers/hub_controller.dart';
import '../features/config_backup/config_backup.dart';
import '../webdav/webdav_config.dart';
import '../widgets/hub_notice/hub_notice.dart';

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
          ? tr('连接成功', 'Connection successful')
          : tr(
              '连接失败，请检查地址与账号密码',
              'Connection failed; check the URL and credentials',
            );
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
          ? tr('已保存', 'Saved')
          : (!_autoSync && !_autoPull)
          ? tr('已保存，当前仅手动下载/上传', 'Saved; manual download/upload only')
          : tr('已保存', 'Saved'),
      ok: true,
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('WebDAV 下载/上传', 'WebDAV Download/Upload'))),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Card(
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.translate_outlined),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr('界面语言', 'Interface Language'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            tr('默认使用简体中文', 'Defaults to Simplified Chinese'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
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
                      onSelectionChanged: (selected) async {
                        await AppLocale.setLanguage(selected.first);
                        if (mounted) setState(() {});
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                leading: const Icon(Icons.folder_zip_outlined),
                title: Text(tr('配置备份', 'Configuration Backup')),
                subtitle: Text(
                  tr(
                    '导出、恢复及自动备份本地 MCP 与 Agent 配置',
                    'Export, restore, and automatically back up local MCP and Agent configuration',
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () =>
                    pushAppPage<void>(context, const ConfigBackupScreen()),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: SwitchListTile(
                title: Text(tr('启用 WebDAV 下载/上传', 'Enable WebDAV Download/Upload')),
                subtitle: Text(
                  tr(
                    '连接配置仅保存在本机，密码绝不会上传',
                    'Connection settings stay on this computer; the password is never uploaded',
                  ),
                ),
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
              ),
            ),
            if (_enabled) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _urlController,
                decoration: InputDecoration(
                  labelText: tr('服务器地址', 'Server URL'),
                  hintText: 'https://dav.jianguoyun.com/dav/',
                  border: const OutlineInputBorder(),
                ),
                validator: (v) {
                  if (!_enabled) return null;
                  if (v == null || v.trim().isEmpty) {
                    return tr('请输入服务器地址', 'Enter a server URL');
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _userController,
                decoration: InputDecoration(
                  labelText: tr('用户名', 'Username'),
                  border: const OutlineInputBorder(),
                ),
                validator: (v) {
                  if (!_enabled) return null;
                  if (v == null || v.trim().isEmpty) {
                    return tr('请输入用户名', 'Enter a username');
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: tr('密码 / 应用专用密码', 'Password / App Password'),
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
                  if (v == null || v.isEmpty) {
                    return tr('请输入密码', 'Enter a password');
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pathController,
                decoration: InputDecoration(
                  labelText: tr('远端目录', 'Remote directory'),
                  hintText: WebDavConfig.defaultRemotePath,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('变更后自动上传', 'Upload changes automatically')),
                subtitle: Text(
                  tr(
                    '将 MCP 清单打包为 catalog.zip 并覆盖远端副本',
                    'Package the MCP catalog as catalog.zip and replace the remote copy',
                  ),
                ),
                value: _autoSync,
                onChanged: (v) => setState(() => _autoSync = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  tr('启动与定时自动合并', 'Merge automatically on startup / schedule'),
                ),
                subtitle: Text(
                  tr(
                    '下载 catalog.zip 并与本地合并，不整包覆盖',
                    'Download catalog.zip and merge it with local data without replacing the whole package',
                  ),
                ),
                value: _autoPull,
                onChanged: (v) => setState(() => _autoPull = v),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  tr('自动合并间隔：$_pollSeconds 秒', 'Merge interval: ${_pollSeconds}s'),
                ),
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
                title: Text(
                  tr(
                    '自动上传防抖：$_pushDebounceSeconds 秒',
                    'Upload debounce: ${_pushDebounceSeconds}s',
                  ),
                ),
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
                label: Text(tr('测试连接', 'Test connection')),
              ),
              if (_testResult != null) ...[
                const SizedBox(height: 8),
                Text(_testResult!),
              ],
              const SizedBox(height: 12),
              Text(
                tr(
                  '下载/上传对 MCP 清单与 Skill / Command / Rule / Hook 使用固定名压缩包'
                      '（catalog.zip、skills.zip、commands.zip、rules.zip、hooks.zip），不会按日期堆积。\n'
                      '上传时写入版本时间：清单取 catalog.json 的 updatedAt，资源包写入上传时间；旧压缩包回退读取 WebDAV 文件修改时间。\n'
                      '「下载」会覆盖对应缓存或清单；「合并」会与本地数据合并（清单三路合并，资源覆盖同名并保留本地多余项）。\n'
                      '永不传输：WebDAV 密码、本机路径、cwd、env 密钥、MCP 开关状态以及内置 hubMCP。\n'
                      '旧版 catalog.json 与 {skills|commands|rules|hooks}/cursor/ 目录仅在压缩包不存在时回退读取。\n'
                      '迁移新电脑步骤：配置同一 WebDAV → 下载或合并 MCP 清单 → 下载 Agent 配置到缓存 → 应用到 Cursor → 按需克隆仓库或写入客户端配置。',
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
                ),
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
                  : Text(tr('保存', 'Save')),
            ),
          ],
        ),
      ),
    );
  }
}
