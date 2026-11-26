import 'dart:io';

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
        message:
            '${resource.label} has no confirmed DeepSeek Harness directory and cannot be converted',
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
        'DeepSeek Harness conversion is not supported on this platform',
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
        : '; rewrote frontmatter on ${result.rewrittenSkills} Skills so DeepSeek Harness will load them';
    final errorHint = result.errors.isEmpty
        ? ''
        : '; failed ${result.errors.length} packages (${result.errors.join(', ')})';
    return SkillSyncResult(
      ok: result.errors.isEmpty,
      target: SkillTarget.deepSeekHarness,
      deployedFiles: result.copiedFiles,
      packageCount: result.packages,
      message: result.packages == 0 && result.errors.isEmpty
          ? 'Cursor Skill directory is empty, nothing converted → $destination'
          : 'Copied ${result.packages} Skills from Cursor to DeepSeek Harness '
                '(${result.copiedFiles} files; existing DeepSeek Harness Skills not in Cursor are kept$rewriteHint$errorHint) → $destination',
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
          ? 'Cursor Rule directory is empty, DeepSeek Harness AGENTS.md section cleared → $destination'
          : 'Copied $count Rules from Cursor into the DeepSeek Harness AGENTS.md section → $destination',
    );
  }
}
