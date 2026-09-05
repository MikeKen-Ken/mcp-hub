import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../services/mcp_paths.dart';
import 'cursor_item_counts.dart';

/// Counts items in Cursor's official directories (not Hub cache).
///
/// Uses synchronous directory reads so counts match files that were just
/// written by Apply / Write to Clients.
class CursorItemCounter {
  const CursorItemCounter({
    this.mcpJsonPath,
    this.skillsDir,
    this.commandsDir,
    this.rulesDir,
    this.hooksJsonPath,
    this.hooksDir,
  });

  final String? mcpJsonPath;
  final String? skillsDir;
  final String? commandsDir;
  final String? rulesDir;
  final String? hooksJsonPath;
  final String? hooksDir;

  Future<CursorItemCounts> load() async => loadSync();

  CursorItemCounts loadSync() {
    return CursorItemCounts(
      mcp: countMcpServers(mcpJsonPath ?? McpPaths.cursorMcpJsonPath),
      skills: countSkillPackages(skillsDir ?? McpPaths.cursorSkillsPath),
      commands: countNonDotFiles(commandsDir ?? McpPaths.cursorCommandsPath),
      rules: countNonDotFiles(rulesDir ?? McpPaths.cursorRulesPath),
      hooks: countHookFiles(
        jsonPath: hooksJsonPath ?? McpPaths.cursorHooksJsonPath,
        scriptsDir: hooksDir ?? McpPaths.cursorHooksPath,
      ),
    );
  }

  static int countMcpServers(String? jsonPath) {
    if (jsonPath == null || jsonPath.isEmpty) return 0;
    try {
      final file = File(jsonPath);
      if (!file.existsSync()) return 0;
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map) return 0;
      final servers = decoded['mcpServers'];
      if (servers is! Map) return 0;
      var count = 0;
      for (final key in servers.keys) {
        if (key.toString().trim().isEmpty) continue;
        count += 1;
      }
      return count;
    } catch (_) {
      return 0;
    }
  }

  static int countSkillPackages(String? dirPath) {
    if (dirPath == null || dirPath.isEmpty) return 0;
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return 0;
    var count = 0;
    for (final entity in dir.listSync(followLinks: false)) {
      if (entity is! Directory) continue;
      final name = p.basename(entity.path);
      if (name.startsWith('.')) continue;
      if (File(p.join(entity.path, 'SKILL.md')).existsSync()) count += 1;
    }
    return count;
  }

  static int countNonDotFiles(String? dirPath) {
    if (dirPath == null || dirPath.isEmpty) return 0;
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return 0;
    var count = 0;
    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relative = p.relative(entity.path, from: dir.path);
      if (p.split(relative).any((part) => part.startsWith('.'))) continue;
      count += 1;
    }
    return count;
  }

  static int countHookFiles({
    required String? jsonPath,
    required String? scriptsDir,
  }) {
    var count = 0;
    if (jsonPath != null && jsonPath.isNotEmpty) {
      final file = File(jsonPath);
      if (file.existsSync() && !p.basename(file.path).startsWith('.')) {
        count += 1;
      }
    }
    count += countNonDotFiles(scriptsDir);
    return count;
  }
}
