import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../common/agent_platforms.dart';
import '../../../common/app_locale.dart';
import '../../../common/package_time.dart';
import '../../../controllers/hub_controller.dart';
import '../../../features/skill_sync/skill_sync.dart';
import '../../../features/sync_status/sync_status.dart';
import '../../../services/mcp_paths.dart';
import '../../../widgets/hub_notice/hub_notice.dart';
import '../../../widgets/op_status/op_status.dart';
import '../../../widgets/sync_confirm/sync_confirm.dart';
import 'directory_path_row.dart';
import 'sync_status_pill.dart';

class FolderResourceSyncCard extends StatelessWidget {
  const FolderResourceSyncCard({super.key, required this.resource});

  final AgentResourceKind resource;

  Future<void> _run(
    BuildContext context,
    Future<SkillSyncResult> Function() action,
  ) async {
    final result = await action();
    if (!context.mounted) return;
    showHubNotice(context, message: result.message, ok: result.ok);
  }

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<HubController>();
    final counts = hub.cursorItemCounts;
    final supported = hub.isDesktopSupported;
    final webDavReady = hub.isWebDavReady;
    final busy = hub.isSyncBusy;
    final thisBusy =
        busy &&
        (hub.skillSync.lastResource == resource ||
            hub.skillSync.lastResource == null ||
            hub.hubConfiguration.busy);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  child: Icon(switch (resource) {
                    AgentResourceKind.skill => Icons.auto_awesome_outlined,
                    AgentResourceKind.command => Icons.terminal_outlined,
                    AgentResourceKind.rule => Icons.rule_outlined,
                    AgentResourceKind.hook => Icons.account_tree_outlined,
                  }),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              resource.label,
                              style: Theme.of(context).textTheme.titleMedium,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          CursorCountChip(
                            count: counts.forResource(resource),
                            tooltip: tr(
                              'Cursor 中已有 ${counts.forResource(resource)} 个 ${resource.label}',
                              '${counts.forResource(resource)} ${resource.wireName} in Cursor',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      SyncAttemptStatus(
                        attempt: hub.syncAttempts.get(resource.wireName),
                        versionLabel: supported && webDavReady
                            ? currentPackageVersionLabel(
                                hub.skillSync.uploadedAtFor(resource),
                              )
                            : null,
                        syncing: thisBusy,
                        unavailableLabel: !supported
                            ? tr(
                                '当前平台不支持目录下载/上传',
                                'Directory download/upload is not supported on this platform',
                              )
                            : (webDavReady
                                  ? null
                                  : tr(
                                      'WebDAV 尚未就绪，仍可使用本地转换',
                                      'WebDAV is not ready; local conversion is still available',
                                    )),
                      ),
                      if (_canConvert) ...[
                        const SizedBox(height: 6),
                        SyncStatusPill(
                          icon: Icons.transform_outlined,
                          label: tr('支持一键转换', 'Conversion supported'),
                          active: true,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: !supported || !webDavReady || busy
                      ? null
                      : () async {
                          final confirmed = await confirmRemoteDownload(
                            context,
                            title: tr(
                              '确认下载远端 ${resource.label}？',
                              'Download remote ${resource.label}?',
                            ),
                            body: tr(
                              '这会下载远端 ${resource.label} 压缩包并覆盖本地缓存。\n\n'
                                  'Cursor 正式目录暂不会改动。',
                              'This will download the remote ${resource.label} archive and replace the local cache.\n\n'
                                  'The official Cursor directory will not be changed.',
                            ),
                            packages: [
                              RemotePackageDateQuery(
                                label: resource.label,
                                load: () =>
                                    hub.peekRemoteResourceUploadedAt(resource),
                              ),
                            ],
                          );
                          if (!confirmed || !context.mounted) return;
                          await _run(
                            context,
                            () => hub.syncResourceToAllTargets(resource),
                          );
                        },
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: Text(tr('下载', 'Download')),
                ),
                OutlinedButton.icon(
                  onPressed: !supported || !webDavReady || busy
                      ? null
                      : () => _run(
                          context,
                          () => hub.mergeResourceToAllTargets(resource),
                        ),
                  icon: const Icon(Icons.merge_outlined),
                  label: Text(tr('合并', 'Merge')),
                ),
                FilledButton.icon(
                  onPressed: !supported || busy
                      ? null
                      : () async {
                          final confirmed = await confirmFolderResourceApply(
                            context,
                            scope: resource.label,
                          );
                          if (!confirmed || !context.mounted) return;
                          await _run(
                            context,
                            () => hub.applyResourceFromCache(resource),
                          );
                        },
                  icon: const Icon(Icons.install_desktop_outlined),
                  label: Text(tr('应用到 Cursor', 'Apply to Cursor')),
                ),
                OutlinedButton.icon(
                  onPressed: !supported || !webDavReady || busy
                      ? null
                      : () async {
                          final confirmed = await confirmRemoteOverwrite(
                            context,
                            scope: resource.label,
                          );
                          if (!confirmed || !context.mounted) return;
                          await _run(
                            context,
                            () => hub.pushResourceToAllTargets(resource),
                          );
                        },
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: Text(tr('上传', 'Upload')),
                ),
                if (_canConvert)
                  FilledButton.icon(
                    onPressed: !supported || busy
                        ? null
                        : () => _run(
                            context,
                            () => hub.convertResourceToAllTargets(resource),
                          ),
                    icon: const Icon(Icons.transform_outlined),
                    label: Text(tr('转换', 'Convert')),
                  ),
              ],
            ),
            OpStatusBar(
              progress: busy && hub.skillSync.lastResource == resource
                  ? hub.skillSync.progress
                  : null,
              errorMessage: busy ? null : hub.skillSync.failureFor(resource),
            ),
            const Divider(height: 24),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: Text(
                tr('查看目录与转换规则', 'View Directories and Conversion Rules'),
              ),
              children: [
                if (_convertHint != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _convertHint!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                for (final target in SkillTarget.values)
                  DirectoryPathRow(
                    label: target == SkillTarget.cursor
                        ? tr(
                            '${target.label}（正式目录）',
                            '${target.label} (official directory)',
                          )
                        : tr(
                            '${target.label}（本地转换）',
                            '${target.label} (local conversion)',
                          ),
                    displayPath: _pathLabelFor(hub, target),
                    directoryPath: _directoryFor(hub, target),
                    enabled: supported && resource.supportsLocalPath(target),
                  ),
                DirectoryPathRow(
                  label: tr('缓存（Cursor）', 'Cache (Cursor)'),
                  displayPath: McpPaths.resourceCachePath(
                    resource.wireName,
                    SkillTarget.cursor.wireName,
                  ),
                  directoryPath: McpPaths.resourceCachePath(
                    resource.wireName,
                    SkillTarget.cursor.wireName,
                  ),
                  enabled: supported,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String? get _convertHint => switch (resource) {
    AgentResourceKind.skill => tr(
      '一键转换：以本机 Cursor 为源镜像并转换为目标格式'
          '（Codex：生成 openai.yaml；OpenCode：改写 SKILL.md frontmatter；'
          'WorkBuddy / WorkBuddy AI：直接复制并保留目标端已有 Skill；'
          'DeepSeek Harness：复制到 ~/.dsh/skills 并按需补全 kebab-case name 与 description；'
          '豆包：复制到工作区 .user_skills 并补齐 name / description；'
          'Antigravity：复制到 ~/.gemini/config/skills 并规范化 name 与 description）',
      'One-click conversion: mirror the package, then convert it to the target format '
          '(Codex: openai.yaml; OpenCode: SKILL.md frontmatter; '
          'WorkBuddy / WorkBuddy AI: plain copy, existing Skills are kept; '
          'DeepSeek Harness: copy into ~/.dsh/skills and fill kebab-case name plus description when missing; '
          'Doubao: copy into the workspace .user_skills and add name / description; '
          'Antigravity: copy into ~/.gemini/config/skills and normalize the kebab-case name plus description)',
    ),
    AgentResourceKind.rule => tr(
      '一键转换：从 Cursor 规则生成 Codex / OpenCode 的 AGENTS.md；'
          'WorkBuddy / WorkBuddy AI 复制到 rules/cursor-sync/；'
          'DeepSeek Harness 更新 ~/.dsh/AGENTS.md 托管段；'
          'Antigravity 更新 ~/.gemini/GEMINI.md 托管段',
      'One-click conversion: generate AGENTS.md for Codex / OpenCode from Cursor rules; '
          'WorkBuddy / WorkBuddy AI get a copy under rules/cursor-sync/; '
          'DeepSeek Harness updates the managed section of ~/.dsh/AGENTS.md; '
          'Antigravity updates the managed section of ~/.gemini/GEMINI.md',
    ),
    AgentResourceKind.command => tr(
      '一键转换：将 Cursor Command 镜像到 OpenCode commands/<name>.md（多余项会清理；Codex 暂无对等目录）',
      'One-click conversion: mirror Cursor commands into OpenCode commands/<name>.md (extra commands are removed; Codex has no equivalent directory)',
    ),
    AgentResourceKind.hook => tr(
      '一键转换：从 Cursor hooks.json 与 hooks/ 生成 Codex hooks.json 与 hooks/（自动适配事件名与 matcher；OpenCode 暂无对等 hooks.json）',
      'One-click conversion: generate Codex hooks.json and hooks/ from Cursor hooks.json and hooks/ (event names and matchers are adapted to Codex; OpenCode has no equivalent hooks.json)',
    ),
  };

  bool get _canConvert =>
      resource.canConvertTo(SkillTarget.codex) ||
      resource.canConvertTo(SkillTarget.openCode) ||
      resource.canConvertToWorkBuddy ||
      resource.canConvertToDeepSeek ||
      resource.canConvertToDoubao ||
      resource.canConvertToAntigravity;

  String? _pathLabelFor(HubController hub, SkillTarget target) {
    if (resource == AgentResourceKind.rule && target == SkillTarget.codex) {
      return McpPaths.codexAgentsMdPath;
    }
    if (resource == AgentResourceKind.rule &&
        target == SkillTarget.deepSeekHarness) {
      return McpPaths.deepSeekAgentsMdPath;
    }
    if (resource == AgentResourceKind.rule &&
        target == SkillTarget.antigravity) {
      return McpPaths.antigravityGeminiMdPath;
    }
    if (resource == AgentResourceKind.hook && target == SkillTarget.cursor) {
      return '${McpPaths.cursorHooksJsonPath}  +  ${McpPaths.cursorHooksPath}';
    }
    if (resource == AgentResourceKind.hook && target == SkillTarget.codex) {
      return '${McpPaths.codexHooksJsonPath}  +  ${McpPaths.codexHooksPath}';
    }
    return hub.skillSync.resourceDeployPathFor(resource, target);
  }

  String? _directoryFor(HubController hub, SkillTarget target) {
    if (resource == AgentResourceKind.rule && target == SkillTarget.codex) {
      return McpPaths.codexConfigDirectory;
    }
    if (resource == AgentResourceKind.rule &&
        target == SkillTarget.deepSeekHarness) {
      return McpPaths.deepSeekConfigDirectory;
    }
    if (resource == AgentResourceKind.rule &&
        target == SkillTarget.antigravity) {
      return McpPaths.antigravityHomeDirectory;
    }
    if (resource == AgentResourceKind.hook && target == SkillTarget.cursor) {
      return McpPaths.cursorConfigDirectory;
    }
    if (resource == AgentResourceKind.hook && target == SkillTarget.codex) {
      return McpPaths.codexConfigDirectory;
    }
    return hub.skillSync.resourceDeployPathFor(resource, target);
  }
}

Future<bool> confirmFolderResourceApply(
  BuildContext context, {
  required String scope,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(tr('确认应用到 Cursor？', 'Apply to Cursor?')),
          content: Text(
            tr(
              '这会把缓存中的 $scope 全量镜像写入 Cursor 正式目录。\n\n'
                  '缓存中缺失的本地 Cursor 文件与目录也会被删除。\n\n'
                  '此操作不会自动转换 Codex / OpenCode；如需转换请使用「转换」。',
              'This will mirror the cached $scope into the official Cursor directory.\n\n'
                  'Local Cursor files and directories missing from the cache will also be deleted.\n\n'
                  'This does not convert Codex / OpenCode; use Convert Folder resources when needed.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(tr('取消', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(tr('确认应用', 'Confirm apply')),
            ),
          ],
        ),
      ) ??
      false;
}
