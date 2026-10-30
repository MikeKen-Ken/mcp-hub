import 'dart:io';

import '../../common/agent_platforms.dart';
import '../../services/mcp_paths.dart';
import 'agent_resource_kind.dart';
import 'convert/cursor_to_workbuddy_converter.dart';
import 'skill_sync_result.dart';
import 'skill_target.dart';

/// 以本机 Cursor 正式目录为源，转换到 WorkBuddy / WorkBuddy AI。
///
/// 仅支持 Skill 与 Rule。Command / Hook 在 WorkBuddy 桌面版的位置尚未确认，
/// 不写入任何文件。客户端未安装（配置目录不存在）时跳过。
class WorkBuddyConversion {
  const WorkBuddyConversion({
    this.converter = const CursorToWorkBuddyConverter(),
  });

  final CursorToWorkBuddyConverter converter;

  static const targets = [SkillTarget.workBuddy, SkillTarget.workBuddyAi];

  Future<SkillSyncResult> convert(
    AgentResourceKind resource,
    SkillTarget target,
  ) async {
    final label = target.label;
    if (!resource.canConvertTo(target)) {
      return SkillSyncResult(
        ok: false,
        target: target,
        message:
            '${resource.label} has no confirmed $label directory and cannot be converted',
      );
    }

    final configDir = AgentPlatforms.of(target).mcpConfigDirectoryPath;
    final destination = AgentPlatforms.localResourcePath(resource, target);
    final source = switch (resource) {
      AgentResourceKind.skill => McpPaths.cursorSkillsPath,
      AgentResourceKind.rule => McpPaths.cursorRulesPath,
      _ => null,
    };
    if (configDir == null || destination == null || source == null) {
      throw StateError('$label conversion is not supported on this platform');
    }
    if (!await Directory(configDir).exists()) {
      return SkillSyncResult(
        ok: true,
        target: target,
        message: '$label is not installed ($configDir not found), skipped',
      );
    }
    if (!await Directory(source).exists()) {
      return SkillSyncResult(
        ok: true,
        target: target,
        message: 'Cursor ${resource.label} directory not found, skipped → $source',
      );
    }

    return switch (resource) {
      AgentResourceKind.skill => await _convertSkills(source, destination, target),
      _ => await _convertRules(source, destination, target),
    };
  }

  Future<SkillSyncResult> _convertSkills(
    String source,
    String destination,
    SkillTarget target,
  ) async {
    final result = await converter.convertSkills(
      sourceDir: source,
      targetDir: destination,
    );
    return SkillSyncResult(
      ok: true,
      target: target,
      deployedFiles: result.copiedFiles,
      packageCount: result.packages,
      message: result.packages == 0
          ? 'Cursor Skill directory is empty, nothing converted → $destination'
          : 'Copied ${result.packages} Skills from Cursor to ${target.label} '
                '(${result.copiedFiles} files; existing ${target.label} Skills not in Cursor are kept) → $destination',
    );
  }

  Future<SkillSyncResult> _convertRules(
    String source,
    String destination,
    SkillTarget target,
  ) async {
    final count = await converter.convertRules(
      sourceDir: source,
      rulesDir: destination,
    );
    return SkillSyncResult(
      ok: true,
      target: target,
      deployedFiles: count,
      packageCount: 0,
      message: count == 0
          ? 'Cursor Rule directory is empty, ${target.label} cursor-sync folder cleared → $destination'
          : 'Copied $count Rules from Cursor to ${target.label} '
                '(${CursorToWorkBuddyConverter.managedRulesFolder}/ folder) → $destination',
    );
  }
}
