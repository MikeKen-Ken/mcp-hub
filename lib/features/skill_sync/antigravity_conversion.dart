import 'dart:io';

import '../../common/agent_platforms.dart';
import '../../common/app_locale.dart';
import '../../services/mcp_paths.dart';
import 'agent_resource_kind.dart';
import 'convert/cursor_to_antigravity_converter.dart';
import 'skill_sync_result.dart';
import 'skill_target.dart';

/// 以本机 Cursor 正式目录为源，转换到 Google Antigravity。
///
/// 只转换已确认的全局位置：
/// - Skill → `~/.gemini/config/skills`
/// - Rule  → `~/.gemini/GEMINI.md`
///
/// Antigravity 没有已确认的用户级 Command / Hook 文件位置，不写入任何文件。
/// 未安装（`~/.gemini` 不存在）时跳过。
class AntigravityConversion {
  const AntigravityConversion({
    this.converter = const CursorToAntigravityConverter(),
  });

  final CursorToAntigravityConverter converter;

  Future<SkillSyncResult> convert(AgentResourceKind resource) async {
    const target = SkillTarget.antigravity;
    if (!resource.canConvertTo(target)) {
      return SkillSyncResult(
        ok: false,
        target: target,
        message: tr(
          '${resource.label} 暂无已确认的 Antigravity 目录，无法转换',
          '${resource.label} has no confirmed Antigravity location and cannot be converted',
        ),
      );
    }

    final home = McpPaths.antigravityHomeDirectory;
    final source = switch (resource) {
      AgentResourceKind.skill => McpPaths.cursorSkillsPath,
      AgentResourceKind.rule => McpPaths.cursorRulesPath,
      _ => null,
    };
    final destination = AgentPlatforms.localResourcePath(resource, target);
    if (home == null || destination == null || source == null) {
      throw StateError(
        tr(
          '当前平台不支持 Antigravity 转换',
          'Antigravity conversion is not supported on this platform',
        ),
      );
    }
    if (!await Directory(home).exists()) {
      return SkillSyncResult(
        ok: true,
        target: target,
        message: tr(
          'Antigravity 未安装（未找到 $home），已跳过',
          'Antigravity is not installed ($home not found), skipped',
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
      AgentResourceKind.skill => _convertSkills(source, destination),
      _ => _convertRules(source, destination),
    };
  }

  Future<SkillSyncResult> _convertSkills(
    String source,
    String destination,
  ) async {
    final result = await converter.convertSkills(
      sourceDir: source,
      targetDir: destination,
    );
    final rewriteHint = result.rewrittenSkills == 0
        ? ''
        : tr(
            '，已规范化 ${result.rewrittenSkills} 个 SKILL.md frontmatter',
            ', normalized ${result.rewrittenSkills} SKILL.md frontmatter',
          );
    final errorHint = result.errors.isEmpty
        ? ''
        : tr(
            '；失败 ${result.errors.length} 个包（${result.errors.join('，')}）',
            '; failed ${result.errors.length} packages (${result.errors.join(', ')})',
          );
    return SkillSyncResult(
      ok: result.errors.isEmpty,
      target: SkillTarget.antigravity,
      deployedFiles: result.copiedFiles,
      packageCount: result.packages,
      message: result.packages == 0 && result.errors.isEmpty
          ? tr(
              'Cursor Skill 目录为空，未转换任何包 → $destination',
              'Cursor Skill directory is empty, nothing converted → $destination',
            )
          : tr(
              '已从 Cursor 转换 ${result.packages} 个 Skill 到 Antigravity'
                  '（${result.copiedFiles} 个文件$rewriteHint；保留目标端原有 Skill$errorHint）→ $destination',
              'Converted ${result.packages} Skills from Cursor to Antigravity '
                  '(${result.copiedFiles} files$rewriteHint; existing Antigravity Skills not in Cursor are kept$errorHint) → $destination',
            ),
    );
  }

  Future<SkillSyncResult> _convertRules(
    String source,
    String destination,
  ) async {
    final count = await converter.convertRules(
      sourceDir: source,
      geminiMdPath: destination,
    );
    return SkillSyncResult(
      ok: true,
      target: SkillTarget.antigravity,
      deployedFiles: count,
      packageCount: 0,
      message: count == 0
          ? tr(
              'Cursor Rule 目录为空，已清空 Antigravity 托管段 → $destination',
              'Cursor Rule directory is empty, Antigravity managed section cleared → $destination',
            )
          : tr(
              '已从 Cursor 转换 $count 条 Rule 到 Antigravity GEMINI.md 托管段 → $destination',
              'Converted $count Rules from Cursor into the Antigravity GEMINI.md managed section → $destination',
            ),
    );
  }
}
