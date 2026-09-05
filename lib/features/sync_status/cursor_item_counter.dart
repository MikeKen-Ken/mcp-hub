import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../services/mcp_paths.dart';
import '../skill_sync/skill_folder_copy.dart';
import 'cursor_item_counts.dart';

/// Counts items in Cursor's official directories (not Hub cache).
class CursorItemCounter {
  const CursorItemCounter({
    this.mcpJsonPath,
    this.skillsDir,
    this.commandsDir,
    this.rulesDir,
    this.hooksJsonPath,
    this.hooksDir,
    this.folderCopy = const SkillFolderCopy(),
  });

  final String? mcpJsonPath;
  final String? skillsDir;
  final String? commandsDir;
  final String? rulesDir;
  final String? hooksJsonPath;
  final String? hooksDir;
  final SkillFolderCopy folderCopy;

  Future<CursorItemCounts> load() async {
    return CursorItemCounts(
      mcp: await countMcpServers(mcpJsonPath ?? McpPaths.cursorMcpJsonPath),
      skills: await _countIfPresent(
        skillsDir ?? McpPaths.cursorSkillsPath,
        folderCopy.countSkillPackages,
      ),
      commands: await countNonDotFiles(
        commandsDir ?? McpPaths.cursorCommandsPath,
      ),
      rules: await countNonDotFiles(rulesDir ?? McpPaths.cursorRulesPath),
      hooks: await countHookFiles(
        jsonPath: hooksJsonPath ?? McpPaths.cursorHooksJsonPath,
        scriptsDir: hooksDir ?? McpPaths.cursorHooksPath,
      ),
    );
  }

  static Future<int> _countIfPresent(
    String? path,
    Future<int> Function(String path) count,
  ) async {
    if (path == null || path.isEmpty) return 0;
    return count(path);
  }

  static Future<int> countMcpServers(String? jsonPath) async {
    if (jsonPath == null || jsonPath.isEmpty) return 0;
    try {
      final file = File(jsonPath);
      if (!await file.exists()) return 0;
      final decoded = jsonDecode(await file.readAsString());
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

  static Future<int> countNonDotFiles(String? dirPath) async {
    if (dirPath == null || dirPath.isEmpty) return 0;
    final dir = Directory(dirPath);
    if (!await dir.exists()) return 0;
    var count = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relative = p.relative(entity.path, from: dir.path);
      if (p.split(relative).any((part) => part.startsWith('.'))) continue;
      count += 1;
    }
    return count;
  }

  static Future<int> countHookFiles({
    required String? jsonPath,
    required String? scriptsDir,
  }) async {
    var count = 0;
    if (jsonPath != null && jsonPath.isNotEmpty) {
      final file = File(jsonPath);
      if (await file.exists() && !p.basename(file.path).startsWith('.')) {
        count += 1;
      }
    }
    count += await countNonDotFiles(scriptsDir);
    return count;
  }
}
