import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../widgets/hub_notice/hub_notice.dart';
import '../../widgets/settings_section.dart';
import 'app_update_service.dart';
import 'github_release_models.dart';

/// 检查并安装来自 GitHub Release 的更新。
class AppUpdateScreen extends StatefulWidget {
  const AppUpdateScreen({super.key, this.service});

  final AppUpdateService? service;

  @override
  State<AppUpdateScreen> createState() => _AppUpdateScreenState();
}

class _AppUpdateScreenState extends State<AppUpdateScreen> {
  late final AppUpdateService _service;
  late final bool _ownsService;
  PackageInfo? _info;
  AppUpdateCheckResult? _check;
  String? _error;
  bool _busy = false;
  double? _progress;

  @override
  void initState() {
    super.initState();
    _ownsService = widget.service == null;
    _service = widget.service ?? AppUpdateService();
    unawaited(_load());
  }

  @override
  void dispose() {
    if (_ownsService) _service.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() => _info = info);
    await _checkUpdate();
  }

  Future<void> _checkUpdate() async {
    setState(() {
      _busy = true;
      _error = null;
      _progress = null;
    });
    try {
      final result = await _service.checkForUpdate();
      if (!mounted) return;
      setState(() {
        _check = result;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  Future<void> _install() async {
    final check = _check;
    if (check == null || !check.updateAvailable) return;
    setState(() {
      _busy = true;
      _error = null;
      _progress = 0;
    });
    try {
      await _service.downloadAndInstall(
        check,
        onProgress: (p) {
          if (!mounted) return;
          setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      setState(() => _busy = false);
      showHubNotice(
        context,
        message:
            'Installer launched; follow the prompts to complete the update',
        ok: true,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final check = _check;
    final versionLabel = info == null
        ? 'Loading…'
        : '${info.version}（${info.buildNumber}）';

    return Scaffold(
      appBar: AppBar(title: const Text('Check for Updates')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          SettingsSection(
            icon: Icons.system_update_alt_outlined,
            title: 'Software Updates',
            subtitle: 'Get installers from GitHub Releases',
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Current version'),
                subtitle: Text(versionLabel),
              ),
              if (check?.release != null)
                ListTile(
                  leading: const Icon(Icons.new_releases_outlined),
                  title: Text('Latest ${check!.release!.versionLabel}'),
                  subtitle: Text(
                    check.message ??
                        (check.updateAvailable
                            ? 'An update is available'
                            : 'You are up to date'),
                  ),
                ),
              if (_progress != null) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LinearProgressIndicator(value: _progress),
                      const SizedBox(height: 6),
                      Text(
                        'Download ${((_progress ?? 0) * 100).toStringAsFixed(0)}%',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy ? null : _checkUpdate,
                        child: const Text('Check again'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed:
                            _busy ||
                                check == null ||
                                !check.updateAvailable ||
                                !_service.isSupported
                            ? null
                            : _install,
                        child: Text(
                          check?.updateAvailable == true
                              ? 'Download and install'
                              : 'No update needed',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (check?.release?.body.trim().isNotEmpty == true) ...[
            const SizedBox(height: 16),
            SettingsSection(
              icon: Icons.notes_outlined,
              title: 'Release Notes',
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: SelectableText(check!.release!.body.trim()),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 启动时若有更新则提示（可跳过该版本）。
Future<void> maybePromptAppUpdate(BuildContext context) async {
  final service = AppUpdateService();
  try {
    if (!service.isSupported) return;
    final result = await service.checkForUpdate();
    if (!result.updateAvailable || result.release == null) return;
    final skipped = await service.skippedVersion();
    if (skipped != null &&
        skipped == result.release!.versionLabel &&
        // 同版本刷新包仍提示
        result.message?.contains('同版本') != true) {
      return;
    }
    if (!context.mounted) return;
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('New version ${result.release!.versionLabel} found'),
        content: Text(result.message ?? 'Open the update page?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'skip'),
            child: const Text('Skip this version'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'later'),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'update'),
            child: const Text('Update'),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    if (action == 'skip') {
      await service.skipVersion(result.release!.versionLabel);
    } else if (action == 'update') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AppUpdateScreen(service: service),
        ),
      );
      return;
    }
  } catch (_) {
    // 启动检查失败静默忽略
  } finally {
    service.dispose();
  }
}
