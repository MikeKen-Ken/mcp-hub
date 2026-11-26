import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../common/app_locale.dart';
import '../../webdav/webdav_sync_service.dart';
import '../operation_logs/operation_log_entry.dart';
import '../operation_logs/operation_log_recorder.dart';
import '../skill_sync/skill_sync_service.dart';
import 'hub_configuration_ops.dart';
import 'hub_configuration_result.dart';

/// Manual Hub configuration Download / Merge / Upload. Owns the combined busy flag.
class HubConfigurationSession extends ChangeNotifier {
  HubConfigurationSession({
    required this._webDav,
    required this._skillSync,
    required this._ensureReady,
    required this._currentMessage,
    required this._setMessage,
    this._logRecorder,
  });

  final WebDavSyncService _webDav;
  final SkillSyncService _skillSync;
  final bool Function() _ensureReady;
  final String? Function() _currentMessage;
  final void Function(String message) _setMessage;
  final OperationLogRecorder? _logRecorder;

  bool busy = false;

  Future<HubConfigurationResult> download() {
    return _run(
      actionName: tr('下载 Hub 配置', 'Download Hub configuration'),
      action: () =>
          downloadHubConfigurationPacks(webDav: _webDav, skillSync: _skillSync),
    );
  }

  Future<HubConfigurationResult> merge() {
    return _run(
      actionName: tr('合并 Hub 配置', 'Merge Hub configuration'),
      action: () =>
          mergeHubConfigurationPacks(webDav: _webDav, skillSync: _skillSync),
    );
  }

  Future<HubConfigurationResult> upload() {
    return _run(
      actionName: tr('上传 Hub 配置', 'Upload Hub configuration'),
      action: () =>
          uploadHubConfigurationPacks(webDav: _webDav, skillSync: _skillSync),
    );
  }

  Future<HubConfigurationResult> _run({
    required String actionName,
    required Future<HubConfigurationResult> Function() action,
  }) async {
    if (!_ensureReady()) {
      final msg =
          _currentMessage() ?? tr('请先配置并启用 WebDAV', 'Enable and configure WebDAV first');
      final result = HubConfigurationResult(ok: false, message: msg);
      unawaited(
        _logRecorder?.record(
          category: OperationLogCategory.sync,
          action: actionName,
          target: tr('Hub 配置（MCP 清单 + 文件夹资源）', 'Hub configuration (Catalog + Folders)'),
          ok: false,
          message: msg,
        ) ??
            Future<void>.value(),
      );
      return result;
    }
    busy = true;
    notifyListeners();
    final sw = Stopwatch()..start();
    try {
      final result = await action();
      sw.stop();
      _setMessage(result.message);
      await _logRecorder?.record(
        category: OperationLogCategory.sync,
        action: actionName,
        target: tr('Hub 配置（MCP 清单 + 文件夹资源）', 'Hub configuration (Catalog + Folders)'),
        ok: result.ok,
        partial: result.partial,
        message: result.message,
        durationMs: sw.elapsedMilliseconds,
      );
      return result;
    } catch (error) {
      sw.stop();
      final msg = '$error';
      _setMessage(msg);
      await _logRecorder?.record(
        category: OperationLogCategory.sync,
        action: actionName,
        target: tr('Hub 配置（MCP 清单 + 文件夹资源）', 'Hub configuration (Catalog + Folders)'),
        ok: false,
        message: msg,
        durationMs: sw.elapsedMilliseconds,
      );
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
