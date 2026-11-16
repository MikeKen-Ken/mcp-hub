import 'dart:io';

import '../../common/agent_platforms.dart';
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
        message:
            '${resource.label} has no confirmed Antigravity location and cannot be converted',
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
        'Antigravity conversion is not supported on this platform',
      );
    }
    if (!await Directory(home).exists()) {
      return SkillSyncResult(
        ok: true,
        target: target,
        message: 'Antigravity is not installed ($home not found), skipped',
      );
    }
    if (!await Directory(source).exists()) {
      return SkillSyncResult(
        ok: true,
        target: target,
        message:
            'Cursor ${resource.label} directory not found, skipped → $source',
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
        : ', normalized ${result.rewrittenSkills} SKILL.md frontmatter';
    return SkillSyncResult(
      ok: true,
      target: SkillTarget.antigravity,
      deployedFiles: result.copiedFiles,
      packageCount: result.packages,
      message: result.packages == 0
          ? 'Cursor Skill directory is empty, nothing converted → $destination'
          : 'Converted ${result.packages} Skills from Cursor to Antigravity '
                '(${result.copiedFiles} files$rewriteHint; existing Antigravity Skills not in Cursor are kept) → $destination',
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
          ? 'Cursor Rule directory is empty, Antigravity managed section cleared → $destination'
          : 'Converted $count Rules from Cursor into the Antigravity GEMINI.md managed section → $destination',
    );
  }
}
