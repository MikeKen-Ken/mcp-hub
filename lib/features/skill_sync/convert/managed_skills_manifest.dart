import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// 记录并维护某个目标 Skill 目录中“由 MCP Hub 写入”的 Skill 列表。
///
/// 清单保存在 `<targetDir>/.mcp-hub-managed.json`（点开头文件，会被常规
/// Skill 扫描器与 `SkillFolderCopy` 自动忽略）。每次转换完成后，只清理
/// “上次由本工具写入、但本次源目录已移除”的目录，绝不误删客户端自带、
/// 市场安装或用户手动放置的 Skill。
class ManagedSkillsManifest {
  const ManagedSkillsManifest();

  static const fileName = '.mcp-hub-managed.json';
  static const _currentVersion = 1;

  /// 比对上次记录的托管 Skill，删除已不在 [currentManagedNames] 中的旧包，
  /// 并写回最新托管清单。返回本次实际删除的旧包数。
  Future<int> syncAndPrune({
    required String targetDir,
    required String scope,
    required Set<String> currentManagedNames,
    Set<String> failedNames = const {},
  }) async {
    final root = Directory(targetDir);
    final manifestFile = File(p.join(targetDir, fileName));
    final rootExists = await root.exists();
    final manifestExists = await manifestFile.exists();
    if (!rootExists && currentManagedNames.isEmpty && !manifestExists) {
      return 0;
    }

    final existingScopes = await _readScopes(manifestFile);
    final previousManaged = existingScopes[scope] ?? const <String>{};

    final safeCurrent = _sanitizeNames(currentManagedNames);
    final safeFailed = _sanitizeNames(failedNames);

    var removed = 0;
    for (final oldName in previousManaged) {
      if (safeCurrent.contains(oldName) || safeFailed.contains(oldName)) {
        continue;
      }
      final staleDir = Directory(p.join(targetDir, oldName));
      if (await staleDir.exists()) {
        await staleDir.delete(recursive: true);
        removed += 1;
      }
    }

    final preservedFailed = previousManaged.intersection(safeFailed);
    final nextManaged = <String>{...safeCurrent, ...preservedFailed}.toList()
      ..sort();

    if (nextManaged.isNotEmpty || manifestExists) {
      await root.create(recursive: true);
      final updatedScopes = <String, List<String>>{};
      for (final entry in existingScopes.entries) {
        if (entry.key == scope) continue;
        final sorted = entry.value.toList()..sort();
        updatedScopes[entry.key] = sorted;
      }
      updatedScopes[scope] = nextManaged;

      final payload = <String, Object>{
        'version': _currentVersion,
        'scopes': updatedScopes,
      };
      final encoder = const JsonEncoder.withIndent('  ');
      await manifestFile.writeAsString('${encoder.convert(payload)}\n');
    }

    return removed;
  }

  Future<Map<String, Set<String>>> _readScopes(File file) async {
    if (!await file.exists()) return const {};
    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return const {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return const {};
      final scopesRaw = decoded['scopes'];
      if (scopesRaw is! Map<String, dynamic>) return const {};

      final result = <String, Set<String>>{};
      for (final entry in scopesRaw.entries) {
        final value = entry.value;
        if (value is! List) continue;
        result[entry.key] = _sanitizeNames(
          value.whereType<String>().toSet(),
        );
      }
      return result;
    } catch (_) {
      return const {};
    }
  }

  Set<String> _sanitizeNames(Set<String> names) {
    final result = <String>{};
    for (final raw in names) {
      final name = raw.trim();
      if (name.isEmpty) continue;
      if (name.startsWith('.')) continue;
      if (name.contains('/') || name.contains(r'\')) continue;
      if (p.basename(name) != name) continue;
      result.add(name);
    }
    return result;
  }
}
