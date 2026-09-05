import 'package:flutter/foundation.dart';

import '../../webdav/webdav_sync_service.dart';
import '../skill_sync/skill_sync_service.dart';
import 'hub_configuration_ops.dart';
import 'hub_configuration_result.dart';

/// Manual Hub configuration Download / Merge / Upload. Owns the combined busy flag.
class HubConfigurationSession extends ChangeNotifier {
  HubConfigurationSession({
    required WebDavSyncService webDav,
    required SkillSyncService skillSync,
    required bool Function() ensureReady,
    required String? Function() currentMessage,
    required void Function(String message) setMessage,
  }) : _webDav = webDav,
       _skillSync = skillSync,
       _ensureReady = ensureReady,
       _currentMessage = currentMessage,
       _setMessage = setMessage;

  final WebDavSyncService _webDav;
  final SkillSyncService _skillSync;
  final bool Function() _ensureReady;
  final String? Function() _currentMessage;
  final void Function(String message) _setMessage;

  bool busy = false;

  Future<HubConfigurationResult> download() {
    return _run(
      () =>
          downloadHubConfigurationPacks(webDav: _webDav, skillSync: _skillSync),
    );
  }

  Future<HubConfigurationResult> merge() {
    return _run(
      () => mergeHubConfigurationPacks(webDav: _webDav, skillSync: _skillSync),
    );
  }

  Future<HubConfigurationResult> upload() {
    return _run(
      () => uploadHubConfigurationPacks(webDav: _webDav, skillSync: _skillSync),
    );
  }

  Future<HubConfigurationResult> _run(
    Future<HubConfigurationResult> Function() action,
  ) async {
    if (!_ensureReady()) {
      return HubConfigurationResult(
        ok: false,
        message: _currentMessage() ?? 'Enable and configure WebDAV first',
      );
    }
    busy = true;
    notifyListeners();
    try {
      final result = await action();
      _setMessage(result.message);
      return result;
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
