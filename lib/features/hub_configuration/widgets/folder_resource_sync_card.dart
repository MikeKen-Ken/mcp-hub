import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../common/agent_platforms.dart';
import '../../../common/app_locale.dart';
import '../../../common/app_theme.dart';
import '../../../common/package_time.dart';
import '../../../controllers/hub_controller.dart';
import '../../../features/skill_sync/skill_sync.dart';
import '../../../features/sync_status/sync_status.dart';
import '../../../services/mcp_paths.dart';
import '../../../widgets/hub_notice/hub_notice.dart';
import '../../../widgets/op_status/op_status.dart';
import '../../../widgets/sync_confirm/sync_confirm.dart';
import 'directory_path_row.dart';
import 'orphan_skills_cleanup_dialog.dart';
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cloudStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 30),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    );

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
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: scheme.primary.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Icon(
                    switch (resource) {
                      AgentResourceKind.skill => Icons.auto_awesome_outlined,
                      AgentResourceKind.command => Icons.terminal_outlined,
                      AgentResourceKind.rule => Icons.rule_outlined,
                      AgentResourceKind.hook => Icons.account_tree_outlined,
                    },
                    size: 18,
                    color: scheme.primary,
                  ),
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
                              style: theme.textTheme.titleMedium,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_targetSummary != null) ...[
                            SyncStatusPill(
                              icon: Icons.transform_outlined,
                              label: _targetSummary!,
                              active: true,
                            ),
                            const SizedBox(width: 6),
                          ],
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
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
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
                  icon: const Icon(Icons.install_desktop_outlined, size: 16),
                  label: Text(tr('应用到 Cursor', 'Apply to Cursor')),
                ),
                if (_canConvert)
                  FilledButton.tonalIcon(
                    onPressed: !supported || busy
                        ? null
                        : () => _run(
                            context,
                            () => hub.convertResourceToAllTargets(resource),
                          ),
                    icon: const Icon(Icons.transform_outlined, size: 16),
                    label: Text(tr('转换', 'Convert')),
                  ),
                if (resource == AgentResourceKind.skill)
                  OutlinedButton.icon(
                    onPressed: !supported || busy
                        ? null
                        : () => showOrphanSkillsCleanupDialog(context),
                    icon: const Icon(Icons.cleaning_services_outlined, size: 16),
                    label: Text(tr('清理多余项', 'Clean extras')),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.subtleBg(context),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.hairline(context)),
              ),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    tr('云端：', 'Cloud:'),
                    style: theme.textTheme.labelSmall,
                  ),
                  OutlinedButton.icon(
                    style: cloudStyle,
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
                                  load: () => hub.peekRemoteResourceUploadedAt(
                                    resource,
                                  ),
                                ),
                              ],
                            );
                            if (!confirmed || !context.mounted) return;
                            await _run(
                              context,
                              () => hub.syncResourceToAllTargets(resource),
                            );
                          },
                    icon: const Icon(Icons.cloud_download_outlined, size: 15),
                    label: Text(tr('下载', 'Download')),
                  ),
                  OutlinedButton.icon(
                    style: cloudStyle,
                    onPressed: !supported || !webDavReady || busy
                        ? null
                        : () => _run(
                            context,
                            () => hub.mergeResourceToAllTargets(resource),
                          ),
                    icon: const Icon(Icons.merge_outlined, size: 15),
                    label: Text(tr('合并', 'Merge')),
                  ),
                  OutlinedButton.icon(
                    style: cloudStyle,
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
                    icon: const Icon(Icons.cloud_upload_outlined, size: 15),
                    label: Text(tr('上传', 'Upload')),
                  ),
                ],
              ),
            ),
            OpStatusBar(
              progress: busy && hub.skillSync.lastResource == resource
                  ? hub.skillSync.progress
                  : null,
              errorMessage: busy ? null : hub.skillSync.failureFor(resource),
            ),
            const SizedBox(height: 8),
            const Divider(),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 6),
              title: Text(
                tr('查看目录与转换规则', 'View Directories and Conversion Rules'),
                style: theme.textTheme.labelLarge,
              ),
              children: [
                if (_convertHint != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _convertHint!,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ),
                for (final target in SkillTarget.values)
                  DirectoryPathRow(
                    label: target == SkillTarget.cursor
                        ? tr(
                            '${target.label}（正式目录）',
                            '${target.label} (official)',
                          )
                        : tr(
                            '${target.label}（本地转换）',
                            '${target.label} (converted)',
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

  String? get _targetSummary => switch (resource) {
    AgentResourceKind.skill => tr('7 目标', '7 targets'),
    AgentResourceKind.rule => tr('6 目标', '6 targets'),
    AgentResourceKind.command => 'OpenCode',
    AgentResourceKind.hook => 'Codex',
  };

  String? get _convertHint => switch (resource) {
    AgentResourceKind.skill => tr(
      '一键转换：以本机 Cursor 为源镜像并转换为目标格式'
          '（Codex：生成 openai.yaml；OpenCode：改写 SKILL.md frontmatter；'
          'WorkBuddy / WorkBuddy AI：直接复制并保留目标端已有 Skill；'
          'DeepSeek Harness：复制到 ~/.dsh/skills；豆包：复制到工作区 .user_skills；'
          'Antigravity：复制到 ~/.gemini/config/skills）',
      'One-click conversion: mirror the package, then convert it for Codex, OpenCode, '
          'WorkBuddy / WorkBuddy AI, DeepSeek Harness, Doubao, and Antigravity.',
    ),
    AgentResourceKind.rule => tr(
      '一键转换：按规则作用域过滤 alwaysApply: false 后生成各端全局规则'
          '（Codex / OpenCode AGENTS.md、WorkBuddy cursor-sync/、DeepSeek ~/.dsh/AGENTS.md、Antigravity ~/.gemini/GEMINI.md）',
      'One-click conversion: skip alwaysApply: false rules and update Codex / OpenCode / '
          'WorkBuddy / DeepSeek Harness / Antigravity.',
    ),
    AgentResourceKind.command => tr(
      '一键转换：将 Cursor Command 保留子目录镜像到 OpenCode commands/ 并补齐 frontmatter（多余项会清理）',
      'One-click conversion: mirror Cursor commands into OpenCode commands/ with frontmatter.',
    ),
    AgentResourceKind.hook => tr(
      '一键转换：从 Cursor hooks.json 与 hooks/ 生成 Codex hooks.json 与 hooks/（自动跳过 Codex 不支持的 Glob Hook）',
      'One-click conversion: generate Codex hooks.json and hooks/ from Cursor (skips Cursor-only Glob hooks).',
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
