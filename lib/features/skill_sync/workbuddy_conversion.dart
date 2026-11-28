import 'dart:io';

import '../../common/agent_platforms.dart';
import '../../common/app_locale.dart';
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
        message: tr(
          '${resource.label} 暂无已确认的 $label 目录，无法转换',
          '${resource.label} has no confirmed $label directory and cannot be converted',
        ),
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
      throw StateError(
        tr('当前平台不支持 $label 转换', '$label conversion is not supported on this platform'),
      );
    }
    if (!await Directory(configDir).exists()) {
      return SkillSyncResult(
        ok: true,
        target: target,
        message: tr(
          '$label 未安装（未找到 $configDir），已跳过',
          '$label is not installed ($configDir not found), skipped',
        ),
      );
    }
    if (!await Directory(source).exists()) {
      return SkillSyncResult(
        ok: true,
        target: target,
        message: tr(
          'Cursor ${resource.label} 目录不存在，跳过转换 → $source',
          'Cursor ${resource.label} directory not found, skipped → $source',
        ),
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
    final removedHint = result.removedPackages == 0
        ? ''
        : tr(
            '；已清理 ${result.removedPackages} 个已移除的旧 Skill',
            '; removed ${result.removedPackages} stale managed Skills',
          );
    final errorHint = result.errors.isEmpty
        ? ''
        : tr(
            '；失败 ${result.errors.length} 个包（${result.errors.join('，')}）',
            '; failed ${result.errors.length} packages (${result.errors.join(', ')})',
          );
    return SkillSyncResult(
      ok: result.errors.isEmpty,
      target: target,
      deployedFiles: result.copiedFiles,
      packageCount: result.packages,
      message: result.packages == 0 &&
              result.removedPackages == 0 &&
              result.errors.isEmpty
          ? tr(
              'Cursor Skill 目录为空，未转换任何包 → $destination',
              'Cursor Skill directory is empty, nothing converted → $destination',
            )
          : tr(
              '已从 Cursor 复制 ${result.packages} 个 Skill 到 ${target.label}'
                  '（${result.copiedFiles} 个文件；保留目标端非托管 Skill$removedHint$errorHint）→ $destination',
              'Copied ${result.packages} Skills from Cursor to ${target.label} '
                  '(${result.copiedFiles} files; unmanaged ${target.label} Skills are kept$removedHint$errorHint) → $destination',
            ),
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
          ? tr(
              'Cursor Rule 目录为空，已清理 ${target.label} cursor-sync 目录 → $destination',
              'Cursor Rule directory is empty, ${target.label} cursor-sync folder cleared → $destination',
            )
          : tr(
              '已从 Cursor 复制 $count 条 Rule 到 ${target.label}'
                  '（${CursorToWorkBuddyConverter.managedRulesFolder}/ 目录）→ $destination',
              'Copied $count Rules from Cursor to ${target.label} '
                  '(${CursorToWorkBuddyConverter.managedRulesFolder}/ folder) → $destination',
            ),
    );
  }
}
