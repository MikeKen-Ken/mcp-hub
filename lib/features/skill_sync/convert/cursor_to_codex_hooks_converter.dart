import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../cursor_hooks_bundle.dart';
import '../skill_folder_copy.dart';

/// Cursor Hook 转换到 Codex `hooks.json` + `hooks/` 的结果。
class CodexHooksConvertResult {
  const CodexHooksConvertResult({
    required this.copiedFiles,
    required this.convertedHooks,
    required this.skippedEvents,
    this.deletedEntries = 0,
    this.enabledFeatureFlag = false,
  });

  final int copiedFiles;
  final int convertedHooks;
  final List<String> skippedEvents;
  final int deletedEntries;
  final bool enabledFeatureFlag;
}

/// 把 Cursor 用户级 Hook 转成 Codex 的三层结构（事件 → matcher 组 → handler）。
///
/// Open Code 使用 TypeScript 插件而非 `hooks.json`，本转换器不写入 Open Code。
class CursorToCodexHooksConverter {
  const CursorToCodexHooksConverter({
    this.folderCopy = const SkillFolderCopy(),
    this.bundle = const CursorHooksBundle(),
  });

  final SkillFolderCopy folderCopy;
  final CursorHooksBundle bundle;

  static const _shellEvents = {'beforeShellExecution', 'afterShellExecution'};

  static const _eventMap = <String, String>{
    'sessionStart': 'SessionStart',
    'sessionEnd': 'SessionEnd',
    'preToolUse': 'PreToolUse',
    'postToolUse': 'PostToolUse',
    'postToolUseFailure': 'PostToolUse',
    'beforeShellExecution': 'PreToolUse',
    'afterShellExecution': 'PostToolUse',
    'beforeMCPExecution': 'PreToolUse',
    'afterMCPExecution': 'PostToolUse',
    'beforeReadFile': 'PreToolUse',
    'afterFileEdit': 'PostToolUse',
    'beforeSubmitPrompt': 'UserPromptSubmit',
    'preCompact': 'PreCompact',
    'stop': 'Stop',
    'subagentStart': 'SubagentStart',
    'subagentStop': 'SubagentStop',
  };

  static const _defaultMatcher = <String, String>{
    'beforeShellExecution': 'Bash',
    'afterShellExecution': 'Bash',
    'beforeReadFile': 'Read',
    'afterFileEdit': 'Write',
  };

  Future<CodexHooksConvertResult> convertAll({
    required CursorHooksLayout cursor,
    required CursorHooksLayout codex,
    String? codexConfigTomlPath,
  }) async {
    final SkillFolderCopyResult scripts;
    final cursorHooksDir = Directory(cursor.hooksDirectoryPath);
    if (await cursorHooksDir.exists()) {
      scripts = await folderCopy.mirrorContents(
        sourceDir: cursor.hooksDirectoryPath,
        targetDir: codex.hooksDirectoryPath,
      );
    } else {
      await Directory(codex.hooksDirectoryPath).create(recursive: true);
      scripts = SkillFolderCopyResult(
        copiedFiles: 0,
        copiedDirs: 0,
        sourcePath: cursor.hooksDirectoryPath,
        targetPath: codex.hooksDirectoryPath,
      );
    }

    final cursorJsonFile = File(cursor.hooksJsonPath);
    final skipped = <String>{};
    var converted = 0;
    final grouped = <String, List<Map<String, Object?>>>{};

    if (await cursorJsonFile.exists()) {
      final decoded = jsonDecode(await cursorJsonFile.readAsString());
      if (decoded is! Map) {
        throw const FormatException('Cursor hooks.json 根节点必须是对象');
      }
      final hooksNode = decoded['hooks'];
      if (hooksNode is Map) {
        for (final entry in hooksNode.entries) {
          final cursorEvent = '${entry.key}';
          final codexEvent = _eventMap[cursorEvent];
          if (codexEvent == null) {
            skipped.add(cursorEvent);
            continue;
          }
          final items = entry.value;
          if (items is! List) continue;
          for (final item in items) {
            if (item is! Map) continue;
            final group = _toCodexGroup(
              cursorEvent: cursorEvent,
              item: Map<String, dynamic>.from(item),
            );
            grouped.putIfAbsent(codexEvent, () => []).add(group);
            converted += 1;
          }
        }
      }
    }

    final payload = <String, Object?>{
      'description': '由 Cursor ~/.cursor/hooks.json 一键转换生成',
      'hooks': grouped,
    };
    final destJson = File(codex.hooksJsonPath);
    await destJson.parent.create(recursive: true);
    await destJson.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
    );

    var enabledFlag = false;
    if (codexConfigTomlPath != null) {
      enabledFlag = await _ensureCodexHooksFeature(codexConfigTomlPath);
    }

    return CodexHooksConvertResult(
      copiedFiles: scripts.copiedFiles + 1,
      convertedHooks: converted,
      skippedEvents: (skipped.toList()..sort()),
      deletedEntries: scripts.deletedEntries,
      enabledFeatureFlag: enabledFlag,
    );
  }

  Map<String, Object?> _toCodexGroup({
    required String cursorEvent,
    required Map<String, dynamic> item,
  }) {
    final matcher = _mapMatcher(cursorEvent, item['matcher']?.toString());
    final type = (item['type']?.toString() ?? 'command').trim();
    final command = item['command']?.toString();
    final prompt = item['prompt']?.toString();
    final timeout = item['timeout'];
    final handler = <String, Object?>{'type': type.isEmpty ? 'command' : type};
    if (command != null && command.trim().isNotEmpty) {
      final relocated = relocateHookCommand(command.trim());
      handler['command'] = relocated.unix;
      handler['commandWindows'] = relocated.windows;
      handler['statusMessage'] = p.basename(relocated.unix);
    }
    if (prompt != null && prompt.trim().isNotEmpty) {
      handler['prompt'] = prompt.trim();
    }
    if (timeout is num) {
      handler['timeout'] = timeout.toInt();
    }

    final group = <String, Object?>{
      'hooks': [handler],
    };
    if (matcher != null && matcher.isNotEmpty) {
      group['matcher'] = matcher;
    }
    return group;
  }

  String? _mapMatcher(String cursorEvent, String? matcher) {
    if (_shellEvents.contains(cursorEvent)) {
      return _defaultMatcher[cursorEvent];
    }
    final fallback = _defaultMatcher[cursorEvent];
    final raw = matcher?.trim() ?? '';
    if (raw.isEmpty) return fallback;
    if (raw == 'Shell') return 'Bash';
    return raw;
  }

  /// 把指向 Cursor `hooks/` 的相对路径改写成 Codex 用户目录。
  static ({String unix, String windows}) relocateHookCommand(String command) {
    var unix = command.replaceAll(r'\', '/');
    unix = unix.replaceAll('.cursor/hooks/', '~/.codex/hooks/');
    unix = unix.replaceAll('./hooks/', '~/.codex/hooks/');
    unix = unix.replaceAllMapped(
      RegExp(r'''(^|[\s"'])hooks/'''),
      (m) => '${m[1]}~/.codex/hooks/',
    );
    final windows = unix.replaceAll(
      '~/.codex/hooks/',
      r'%USERPROFILE%\.codex\hooks\',
    );
    return (unix: unix, windows: windows);
  }

  Future<bool> _ensureCodexHooksFeature(String configTomlPath) async {
    final file = File(configTomlPath);
    var source = await file.exists() ? await file.readAsString() : '';
    if (RegExp(
      r'^\s*codex_hooks\s*=\s*true\s*$',
      multiLine: true,
    ).hasMatch(source)) {
      return false;
    }

    final featuresHeader = RegExp(r'^\[features\]\s*$', multiLine: true);
    final match = featuresHeader.firstMatch(source);
    String next;
    if (match == null) {
      final trimmed = source.trimRight();
      const block = '[features]\ncodex_hooks = true\n';
      next = trimmed.isEmpty ? block : '$trimmed\n\n$block';
    } else {
      next =
          '${source.substring(0, match.end)}\n'
          'codex_hooks = true'
          '${source.substring(match.end)}';
    }
    await file.parent.create(recursive: true);
    await file.writeAsString(next);
    return true;
  }
}
