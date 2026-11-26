import 'dart:io';

import '../../common/app_locale.dart';
import '../../services/mcp_paths.dart';
import 'agent_resource_kind.dart';
import 'convert/cursor_to_codex_agents_converter.dart';
import 'convert/cursor_to_codex_hooks_converter.dart';
import 'convert/cursor_to_codex_skill_converter.dart';
import 'convert/cursor_to_opencode_converter.dart';
import 'cursor_hooks_bundle.dart';
import 'skill_sync_result.dart';
import 'skill_target.dart';

/// 以本机 Cursor 正式目录为源，转换到 Codex / Open Code。
class ResourceConversion {
  const ResourceConversion({
    required this.skillConverter,
    required this.agentsConverter,
    required this.openCodeConverter,
    required this.hooksConverter,
  });

  final CursorToCodexSkillConverter skillConverter;
  final CursorToCodexAgentsConverter agentsConverter;
  final CursorToOpenCodeConverter openCodeConverter;
  final CursorToCodexHooksConverter hooksConverter;

  Future<SkillSyncResult> convertCodex(AgentResourceKind resource) {
    return switch (resource) {
      AgentResourceKind.skill => _convertSkillsFromCursor(),
      AgentResourceKind.rule => _convertRulesFromCursor(),
      AgentResourceKind.hook => _convertHooksFromCursor(),
      AgentResourceKind.command => Future.value(
        SkillSyncResult(
          ok: false,
          target: SkillTarget.codex,
          message: tr(
            'Command 暂无 Codex 对等目录，无法转换',
            'Command has no Codex equivalent directory and cannot be converted',
          ),
        ),
      ),
    };
  }

  Future<SkillSyncResult> convertOpenCode(AgentResourceKind resource) async {
    final openCodeSkillsPath = McpPaths.openCodeSkillsPath;
    final openCodeRulesPath = McpPaths.openCodeRulesPath;
    final openCodeCommandsPath = McpPaths.openCodeCommandsPath;
    if (openCodeSkillsPath == null ||
        openCodeRulesPath == null ||
        openCodeCommandsPath == null) {
      throw StateError(
        tr('当前平台不支持 OpenCode 转换', 'OpenCode conversion is not supported on this platform'),
      );
    }
    final cursorSkillsPath = McpPaths.cursorSkillsPath;
    final cursorRulesPath = McpPaths.cursorRulesPath;
    final cursorCommandsPath = McpPaths.cursorCommandsPath;
    if (cursorSkillsPath == null ||
        cursorRulesPath == null ||
        cursorCommandsPath == null) {
      throw StateError(
        tr('当前平台不支持 Cursor 转换', 'Cursor conversion is not supported on this platform'),
      );
    }

    return switch (resource) {
      AgentResourceKind.skill => await _convertOpenCodeSkills(
        cursorSkillsPath,
        openCodeSkillsPath,
      ),
      AgentResourceKind.rule => await _convertOpenCodeRules(
        cursorRulesPath,
        openCodeRulesPath,
      ),
      AgentResourceKind.command => await _convertOpenCodeCommands(
        cursorCommandsPath,
        openCodeCommandsPath,
      ),
      AgentResourceKind.hook => SkillSyncResult(
        ok: false,
        target: SkillTarget.openCode,
        message: tr(
          'Hook 暂无 Open Code 对等 hooks.json，无法转换',
          'Hook has no OpenCode equivalent hooks.json and cannot be converted',
        ),
      ),
    };
  }

  Future<SkillSyncResult> _convertHooksFromCursor() async {
    final cursor = CursorHooksLayout.cursorUser();
    final codex = CursorHooksLayout.codexUser();
    if (cursor == null || codex == null) {
      throw StateError(
        tr('当前平台不支持 Hook 转换', 'Hook conversion is not supported on this platform'),
      );
    }
    final converted = await hooksConverter.convertAll(
      cursor: cursor,
      codex: codex,
      codexConfigTomlPath: McpPaths.codexConfigTomlPath,
    );
    final skipHint = converted.skippedEvents.isEmpty
        ? ''
        : tr(
            '；已跳过无 Codex 对应事件：${converted.skippedEvents.join("、")}',
            '; skipped unsupported Codex events: ${converted.skippedEvents.join(", ")}',
          );
    final flagHint = converted.enabledFeatureFlag
        ? tr('；已写入 features.hooks = true', '; wrote features.hooks = true')
        : '';
    return SkillSyncResult(
      ok: true,
      target: SkillTarget.codex,
      deployedFiles: converted.copiedFiles,
      packageCount: converted.convertedHooks,
      message: converted.convertedHooks == 0
          ? tr(
              'Cursor Hook 为空或无可映射事件，已写入 Codex hooks.json'
                  '$skipHint$flagHint → ${codex.hooksJsonPath}',
              'Cursor Hooks empty or unmapped; wrote Codex hooks.json'
                  '$skipHint$flagHint → ${codex.hooksJsonPath}',
            )
          : tr(
              '已从 Cursor 转换 ${converted.convertedHooks} 条 Hook 到 Codex'
                  '（复制 ${converted.copiedFiles} 个文件$skipHint$flagHint）'
                  ' → ${codex.hooksJsonPath}',
              'Converted ${converted.convertedHooks} Hooks from Cursor to Codex'
                  ' (${converted.copiedFiles} files$skipHint$flagHint)'
                  ' → ${codex.hooksJsonPath}',
            ),
    );
  }

  Future<SkillSyncResult> _convertOpenCodeSkills(
    String source,
    String target,
  ) async {
    final sourceDir = Directory(source);
    if (!await sourceDir.exists()) {
      return SkillSyncResult(
        ok: true,
        target: SkillTarget.openCode,
        message: tr(
          'Cursor Skill 目录不存在，跳过转换 → $source',
          'Cursor Skill directory not found, skipped → $source',
        ),
      );
    }
    final skills = await openCodeConverter.convertSkills(
      sourceDir: source,
      targetDir: target,
    );
    final removeHint = skills.removedPackages == 0
        ? ''
        : tr(
            '，并删除多余 ${skills.removedPackages} 个包',
            ', removed ${skills.removedPackages} extra packages',
          );
    final extraHint = skills.deletedEntries == 0
        ? ''
        : tr(
            '，包内删除 ${skills.deletedEntries} 项',
            ', removed ${skills.deletedEntries} extra items inside packages',
          );
    final errorHint = skills.errors.isEmpty
        ? ''
        : tr(
            '；失败 ${skills.errors.length} 个包（${skills.errors.join('，')}）',
            '; failed ${skills.errors.length} packages (${skills.errors.join(', ')})',
          );
    return SkillSyncResult(
      ok: skills.errors.isEmpty,
      target: SkillTarget.openCode,
      deployedFiles: skills.copiedFiles,
      packageCount: skills.packages,
      message: skills.packages == 0 && skills.errors.isEmpty
          ? tr(
              'Cursor Skill 目录为空，未转换任何包$removeHint → $target',
              'Cursor Skill directory is empty, nothing converted$removeHint → $target',
            )
          : tr(
              '已从 Cursor 批量转换 ${skills.packages} 个 Skill 到 Open Code'
                  '（复制 ${skills.copiedFiles} 个文件$extraHint$removeHint$errorHint）→ $target',
              'Converted ${skills.packages} Skills from Cursor to Open Code'
                  ' (${skills.copiedFiles} files$extraHint$removeHint$errorHint) → $target',
            ),
    );
  }

  Future<SkillSyncResult> _convertOpenCodeRules(
    String source,
    String target,
  ) async {
    final sourceDir = Directory(source);
    if (!await sourceDir.exists()) {
      return SkillSyncResult(
        ok: true,
        target: SkillTarget.openCode,
        message: tr(
          'Cursor Rule 目录不存在，跳过转换 → $source',
          'Cursor Rule directory not found, skipped → $source',
        ),
      );
    }
    final count = await openCodeConverter.convertRules(
      sourceDir: source,
      targetPath: target,
    );
    return SkillSyncResult(
      ok: true,
      target: SkillTarget.openCode,
      deployedFiles: count,
      packageCount: 0,
      message: count == 0
          ? tr(
              'Cursor Rule 目录为空，已生成空的 AGENTS.md → $target',
              'Cursor Rule directory is empty, wrote empty AGENTS.md → $target',
            )
          : tr(
              '已从 Cursor 批量转换 $count 条 Rule 到 Open Code AGENTS.md → $target',
              'Converted $count Rules from Cursor to Open Code AGENTS.md → $target',
            ),
    );
  }

  Future<SkillSyncResult> _convertOpenCodeCommands(
    String source,
    String target,
  ) async {
    final sourceDir = Directory(source);
    if (!await sourceDir.exists()) {
      return SkillSyncResult(
        ok: true,
        target: SkillTarget.openCode,
        message: tr(
          'Cursor Command 目录不存在，跳过转换 → $source',
          'Cursor Command directory not found, skipped → $source',
        ),
      );
    }
    final commands = await openCodeConverter.convertCommands(
      sourceDir: source,
      targetDir: target,
    );
    final deleteHint = commands.deleted == 0
        ? ''
        : tr(
            '，并删除多余 ${commands.deleted} 项',
            ', removed ${commands.deleted} extra items',
          );
    return SkillSyncResult(
      ok: true,
      target: SkillTarget.openCode,
      deployedFiles: commands.written,
      packageCount: 0,
      message: tr(
        '已从 Cursor 转换 Open Code Command：${commands.written} 个'
            '$deleteHint → $target',
        'Converted ${commands.written} Commands from Cursor to Open Code'
            '$deleteHint → $target',
      ),
    );
  }

  Future<SkillSyncResult> _convertSkillsFromCursor() async {
    final source = McpPaths.cursorSkillsPath;
    final target = McpPaths.codexSkillsPath;
    if (source == null || target == null) {
      throw StateError(
        tr('当前平台不支持 Skill 转换', 'Skill conversion is not supported on this platform'),
      );
    }
    final sourceDir = Directory(source);
    if (!await sourceDir.exists()) {
      return SkillSyncResult(
        ok: true,
        target: SkillTarget.codex,
        message: tr(
          'Cursor Skill 目录不存在，跳过转换 → $source',
          'Cursor Skill directory not found, skipped → $source',
        ),
      );
    }
    final converted = await skillConverter.convertAll(
      cursorSkillsDir: source,
      codexSkillsDir: target,
    );
    final copied = converted.items.fold<int>(
      0,
      (sum, e) => sum + e.copiedFiles,
    );
    final deletedInPacks = converted.items.fold<int>(
      0,
      (sum, e) => sum + e.deletedEntries,
    );
    final removed = converted.removedPackages;
    final removeHint = removed == 0
        ? ''
        : tr('，并删除多余 $removed 个包', ', removed $removed extra packages');
    final extraHint = deletedInPacks == 0
        ? ''
        : tr(
            '，包内删除 $deletedInPacks 项',
            ', removed $deletedInPacks extra items inside packages',
          );
    final errorHint = converted.errors.isEmpty
        ? ''
        : tr(
            '；失败 ${converted.errors.length} 个包（${converted.errors.join('，')}）',
            '; failed ${converted.errors.length} packages (${converted.errors.join(', ')})',
          );
    return SkillSyncResult(
      ok: converted.errors.isEmpty,
      target: SkillTarget.codex,
      deployedFiles: copied,
      packageCount: converted.items.length,
      message: converted.items.isEmpty && converted.errors.isEmpty
          ? tr(
              'Cursor Skill 目录为空，未转换任何包$removeHint → $target',
              'Cursor Skill directory is empty, nothing converted$removeHint → $target',
            )
          : tr(
              '已从 Cursor 批量转换 ${converted.items.length} 个 Skill 到 Codex'
                  '（复制 $copied 个文件，并写入 agents/openai.yaml'
                  '$extraHint$removeHint$errorHint）→ $target',
              'Converted ${converted.items.length} Skills from Cursor to Codex'
                  ' ($copied files, wrote agents/openai.yaml'
                  '$extraHint$removeHint$errorHint) → $target',
            ),
    );
  }

  Future<SkillSyncResult> _convertRulesFromCursor() async {
    final source = McpPaths.cursorRulesPath;
    final target = McpPaths.codexAgentsMdPath;
    if (source == null || target == null) {
      throw StateError(
        tr('当前平台不支持 Rule 转换', 'Rule conversion is not supported on this platform'),
      );
    }
    final sourceDir = Directory(source);
    if (!await sourceDir.exists()) {
      return SkillSyncResult(
        ok: true,
        target: SkillTarget.codex,
        message: tr(
          'Cursor Rule 目录不存在，跳过转换 → $source',
          'Cursor Rule directory not found, skipped → $source',
        ),
      );
    }
    final items = await agentsConverter.convertAll(
      cursorRulesDir: source,
      agentsMdPath: target,
    );
    return SkillSyncResult(
      ok: true,
      target: SkillTarget.codex,
      deployedFiles: items.length,
      packageCount: items.length,
      message: items.isEmpty
          ? tr(
              'Cursor Rule 目录为空，已生成空的 AGENTS.md → $target',
              'Cursor Rule directory is empty, wrote empty AGENTS.md → $target',
            )
          : tr(
              '已从 Cursor 批量转换 ${items.length} 条 Rule 到 Codex AGENTS.md → $target',
              'Converted ${items.length} Rules from Cursor to Codex AGENTS.md → $target',
            ),
    );
  }
}
