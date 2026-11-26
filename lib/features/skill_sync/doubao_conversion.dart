import 'dart:io';

import '../../common/agent_platforms.dart';
import '../../common/app_locale.dart';
import '../../services/mcp_paths.dart';
import 'agent_resource_kind.dart';
import 'convert/cursor_to_doubao_converter.dart';
import 'skill_sync_result.dart';
import 'skill_target.dart';

/// 以本机 Cursor 正式目录为源，转换到豆包（Doubao）。
///
/// 豆包电脑版只提供本地技能目录（`.user_skills`）；MCP 连接器在客户端
/// 界面里配置，没有用户可写的本地 MCP 文件，因此这里只转换 Skill。
/// Rule / Command / Hook 无对等目录，不写入任何文件。未安装时跳过。
class DoubaoConversion {
  const DoubaoConversion({this.converter = const CursorToDoubaoConverter()});

  final CursorToDoubaoConverter converter;

  Future<SkillSyncResult> convert(AgentResourceKind resource) async {
    const target = SkillTarget.doubao;
    if (!resource.canConvertTo(target)) {
      return SkillSyncResult(
        ok: false,
        target: target,
        message: resource == AgentResourceKind.skill
            ? tr(
                '当前平台不支持将 Skill 转换到豆包',
                'Skill cannot be converted to Doubao on this platform',
              )
            : tr(
                '${resource.label} 暂无豆包对等目录，无法转换（豆包连接器在客户端内配置）',
                '${resource.label} has no Doubao equivalent directory and cannot be converted '
                    '(Doubao connectors are configured in the app, not in a local file)',
              ),
      );
    }

    final workspace = McpPaths.doubaoWorkspacePath;
    final source = McpPaths.cursorSkillsPath;
    final destination = AgentPlatforms.localResourcePath(resource, target);
    if (workspace == null || destination == null || source == null) {
      throw StateError(
        tr('当前平台不支持豆包转换', 'Doubao conversion is not supported on this platform'),
      );
    }
    if (!await Directory(workspace).exists()) {
      return SkillSyncResult(
        ok: true,
        target: target,
        message: tr(
          '豆包未安装（未找到 $workspace），已跳过',
          'Doubao is not installed ($workspace not found), skipped',
        ),
      );
    }
    if (!await Directory(source).exists()) {
      return SkillSyncResult(
        ok: true,
        target: target,
        message: tr(
          'Cursor Skill 目录不存在，跳过转换 → $source',
          'Cursor Skill directory not found, skipped → $source',
        ),
      );
    }

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
      target: target,
      deployedFiles: result.copiedFiles,
      packageCount: result.packages,
      message: result.packages == 0 && result.errors.isEmpty
          ? tr(
              'Cursor Skill 目录为空，未转换任何包 → $destination',
              'Cursor Skill directory is empty, nothing converted → $destination',
            )
          : tr(
              '已从 Cursor 转换 ${result.packages} 个 Skill 到豆包'
                  '（${result.copiedFiles} 个文件$rewriteHint；保留目标端原有 Skill$errorHint）→ $destination',
              'Converted ${result.packages} Skills from Cursor to Doubao '
                  '(${result.copiedFiles} files$rewriteHint; existing Doubao Skills not in Cursor are kept$errorHint) → $destination',
            ),
    );
  }
}
