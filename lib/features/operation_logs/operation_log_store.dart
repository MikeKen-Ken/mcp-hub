import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/mcp_paths.dart';
import 'operation_log_entry.dart';

/// 持久化操作日志仓库（最新在前，默认保留最近 500 条）。
class OperationLogStore extends ChangeNotifier {
  OperationLogStore({
    this.maxEntries = 500,
    String? filePath,
    this._prefsLoader,
    bool? persistToFile,
  }) : _explicitFilePath = filePath,
       _persistToFile =
           persistToFile ??
           (filePath != null ||
               (!kIsWeb && !Platform.environment.containsKey('FLUTTER_TEST')));

  static const _prefsKey = 'mcp_hub_operation_logs';

  final int maxEntries;
  final String? _explicitFilePath;
  final Future<SharedPreferences> Function()? _prefsLoader;
  final bool _persistToFile;

  final List<OperationLogEntry> _entries = [];
  Future<void> _writeChain = Future<void>.value();
  int _seq = 0;

  List<OperationLogEntry> get entries => List.unmodifiable(_entries);

  bool get isEmpty => _entries.isEmpty;

  int get length => _entries.length;

  OperationLogEntry? get latest => _entries.isEmpty ? null : _entries.first;

  int get failureCount => _entries
      .where((entry) => entry.status != OperationLogStatus.success)
      .length;

  String nextId([DateTime? at]) {
    _seq += 1;
    final stamp = (at ?? DateTime.now()).microsecondsSinceEpoch;
    return '$stamp-$_seq';
  }

  String? get _resolvedFilePath {
    if (!_persistToFile) return null;
    return _explicitFilePath ?? McpPaths.operationLogsPath;
  }

  Future<void> load() async {
    try {
      String? raw;
      final filePath = _resolvedFilePath;
      if (filePath != null) {
        final file = File(filePath);
        if (await file.exists()) {
          raw = await file.readAsString();
        }
      } else if (_prefsLoader != null) {
        final prefs = await _prefsLoader();
        raw = prefs.getString(_prefsKey);
      }

      _entries.clear();
      if (raw != null && raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        final list = decoded is Map ? decoded['entries'] : decoded;
        if (list is List) {
          for (final item in list) {
            final entry = OperationLogEntry.fromJson(item);
            if (entry != null) _entries.add(entry);
          }
        }
      }
      if (_entries.length > maxEntries) {
        _entries.removeRange(maxEntries, _entries.length);
      }
      notifyListeners();
    } catch (error) {
      debugPrint('加载操作日志失败: $error');
    }
  }

  Future<void> append(OperationLogEntry entry) {
    _entries.insert(0, entry);
    if (_entries.length > maxEntries) {
      _entries.removeRange(maxEntries, _entries.length);
    }
    notifyListeners();
    return _enqueuePersist();
  }

  Future<void> clear() {
    _entries.clear();
    notifyListeners();
    return _enqueuePersist();
  }

  String exportText({Iterable<OperationLogEntry>? items}) {
    final list = (items ?? _entries).toList(growable: false);
    if (list.isEmpty) return '';
    return list.map((e) => e.toPlainText().trimRight()).join('\n\n---\n\n');
  }

  Future<void> _enqueuePersist() {
    final snapshot = _entries.map((e) => e.toJson()).toList(growable: false);
    _writeChain = _writeChain.then((_) => _persistSnapshot(snapshot));
    return _writeChain;
  }

  Future<void> _persistSnapshot(List<Map<String, Object?>> snapshot) async {
    try {
      final encoded = const JsonEncoder.withIndent(
        '  ',
      ).convert({'version': 1, 'entries': snapshot});
      final filePath = _resolvedFilePath;
      if (filePath != null) {
        final file = File(filePath);
        await file.parent.create(recursive: true);
        await file.writeAsString(encoded, flush: true);
      } else if (_prefsLoader != null) {
        final prefs = await _prefsLoader();
        await prefs.setString(_prefsKey, encoded);
      }
    } catch (error) {
      debugPrint('保存操作日志失败: $error');
    }
  }
}
