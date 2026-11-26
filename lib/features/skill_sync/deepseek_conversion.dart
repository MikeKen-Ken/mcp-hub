import 'dart:io';

import '../../common/app_locale.dart';
import '../../services/mcp_paths.dart';
import 'agent_resource_kind.dart';
import 'convert/cursor_to_deepseek_converter.dart';
import 'skill_sync_result.dart';
import 'skill_target.dart';

/// 以本机 Cursor 正式目录为源，转换到 DeepSeek Harness。
///
/// 仅支持 Skill 与 Rule。Command 没有已确认的用户目录。Hook 不会被
/// Harness 自动发现，因此这两类不写任何文件。
class DeepSeekConversion {
  const DeepSeekConversion({
    this.converter = const CursorToDeepSeekConverter(),
  });

  final CursorToDeepSeekConverter converter;

  Future<SkillSyncResult> convert(AgentResourceKind resource) async {
    const target = SkillTarget.deepSeekHarness;
    if (!resource.canConvertTo(target)) {
      return SkillSyncResult(
        ok: false,
        target: target,
        message: tr(
          '${resource.label} 暂无已确认的 DeepSeek Harness 目录，无法转换',
          '${resource.label} has no confirmed DeepSeek Harness directory and cannot be converted',
        ),
      );
    }

    final source = switch (resource) {
      AgentResourceKind.skill => McpPaths.cursorSkillsPath,
      AgentResourceKind.rule => McpPaths.cursorRulesPath,
      _ => null,
    };
    final destination = switch (resource) {
      AgentResourceKind.skill => McpPaths.deepSeekSkillsPath,
      AgentResourceKind.rule => McpPaths.deepSeekAgentsMdPath,
      _ => null,
    };
    if (source == null || destination == null) {
      throw StateError(
        tr(
          '当前平台不支持 DeepSeek Harness 转换',
          'DeepSeek Harness conversion is not supported on this platform',
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
      AgentResourceKind.skill => await _convertSkills(source, destination),
      _ => await _convertRules(source, destination),
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
            '；已补全 ${result.rewrittenSkills} 个 Skill 的 frontmatter',
            '; rewrote frontmatter on ${result.rewrittenSkills} Skills so DeepSeek Harness will load them',
          );
    final errorHint = result.errors.isEmpty
        ? ''
        : tr(
            '；失败 ${result.errors.length} 个包（${result.errors.join('，')}）',
            '; failed ${result.errors.length} packages (${result.errors.join(', ')})',
          );
    return SkillSyncResult(
      ok: result.errors.isEmpty,
      target: SkillTarget.deepSeekHarness,
      deployedFiles: result.copiedFiles,
      packageCount: result.packages,
      message: result.packages == 0 && result.errors.isEmpty
          ? tr(
              'Cursor Skill 目录为空，未转换任何包 → $destination',
              'Cursor Skill directory is empty, nothing converted → $destination',
            )
          : tr(
              '已从 Cursor 复制 ${result.packages} 个 Skill 到 DeepSeek Harness'
                  '（${result.copiedFiles} 个文件；保留目标端原有 Skill$rewriteHint$errorHint）→ $destination',
              'Copied ${result.packages} Skills from Cursor to DeepSeek Harness '
                  '(${result.copiedFiles} files; existing DeepSeek Harness Skills not in Cursor are kept$rewriteHint$errorHint) → $destination',
            ),
    );
  }

  Future<SkillSyncResult> _convertRules(
    String source,
    String destination,
  ) async {
    final count = await converter.convertRules(
      sourceDir: source,
      agentsMdPath: destination,
    );
    return SkillSyncResult(
      ok: true,
      target: SkillTarget.deepSeekHarness,
      deployedFiles: count,
      packageCount: 0,
      message: count == 0
          ? tr(
              'Cursor Rule 目录为空，已清空 DeepSeek Harness AGENTS.md 托管段 → $destination',
              'Cursor Rule directory is empty, DeepSeek Harness AGENTS.md section cleared → $destination',
            )
          : tr(
              '已从 Cursor 复制 $count 条 Rule 到 DeepSeek Harness AGENTS.md 托管段 → $destination',
              'Copied $count Rules from Cursor into the DeepSeek Harness AGENTS.md section → $destination',
            ),
    );
  }
}
