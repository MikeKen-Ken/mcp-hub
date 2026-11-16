import 'dart:io';

import '../../common/agent_platforms.dart';
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
            ? 'Skill cannot be converted to Doubao on this platform'
            : '${resource.label} has no Doubao equivalent directory and cannot be converted '
                  '(Doubao connectors are configured in the app, not in a local file)',
      );
    }

    final workspace = McpPaths.doubaoWorkspacePath;
    final source = McpPaths.cursorSkillsPath;
    final destination = AgentPlatforms.localResourcePath(resource, target);
    if (workspace == null || destination == null || source == null) {
      throw StateError('Doubao conversion is not supported on this platform');
    }
    if (!await Directory(workspace).exists()) {
      return SkillSyncResult(
        ok: true,
        target: target,
        message: 'Doubao is not installed ($workspace not found), skipped',
      );
    }
    if (!await Directory(source).exists()) {
      return SkillSyncResult(
        ok: true,
        target: target,
        message: 'Cursor Skill directory not found, skipped → $source',
      );
    }

    final result = await converter.convertSkills(
      sourceDir: source,
      targetDir: destination,
    );
    final rewriteHint = result.rewrittenSkills == 0
        ? ''
        : ', normalized ${result.rewrittenSkills} SKILL.md frontmatter';
    return SkillSyncResult(
      ok: true,
      target: target,
      deployedFiles: result.copiedFiles,
      packageCount: result.packages,
      message: result.packages == 0
          ? 'Cursor Skill directory is empty, nothing converted → $destination'
          : 'Converted ${result.packages} Skills from Cursor to Doubao '
                '(${result.copiedFiles} files$rewriteHint; existing Doubao Skills not in Cursor are kept) → $destination',
    );
  }
}
