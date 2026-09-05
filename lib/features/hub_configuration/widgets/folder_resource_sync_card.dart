import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../common/agent_platforms.dart';
import '../../../controllers/hub_controller.dart';
import '../../../features/skill_sync/skill_sync.dart';
import '../../../features/sync_status/sync_status.dart';
import '../../../common/package_time.dart';
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
                            tooltip:
                                '${counts.forResource(resource)} ${resource.wireName} in Cursor',
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
                            ? 'Directory download/upload is not supported on this platform'
                            : (webDavReady
                                  ? null
                                  : 'WebDAV is not ready; local conversion is still available'),
                      ),
                      if (_canConvert) ...[
                        const SizedBox(height: 6),
                        const SyncStatusPill(
                          icon: Icons.transform_outlined,
                          label: 'Conversion supported',
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
                            title: 'Download remote ${resource.label}?',
                            body:
                                'This will download the remote ${resource.label} archive and replace the local cache.\n\n'
                                'The official Cursor directory will not be changed.',
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
                  label: const Text('Download'),
                ),
                OutlinedButton.icon(
                  onPressed: !supported || !webDavReady || busy
                      ? null
                      : () => _run(
                          context,
                          () => hub.mergeResourceToAllTargets(resource),
                        ),
                  icon: const Icon(Icons.merge_outlined),
                  label: const Text('Merge'),
                ),
                FilledButton.tonalIcon(
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
                  label: const Text('Apply to Cursor'),
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
                  label: const Text('Upload'),
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
                    label: const Text('Convert'),
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
              title: const Text('View Directories and Conversion Rules'),
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
                        ? '${target.label} (official directory)'
                        : '${target.label} (local conversion)',
                    displayPath: _pathLabelFor(hub, target),
                    directoryPath: _directoryFor(hub, target),
                    enabled: supported && resource.supportsLocalPath(target),
                  ),
                DirectoryPathRow(
                  label: 'Cache (Cursor)',
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
    AgentResourceKind.skill =>
      'One-click conversion: mirror the package, then convert it to the target format (Codex: openai.yaml; OpenCode: SKILL.md frontmatter)',
    AgentResourceKind.rule =>
      'One-click conversion: generate AGENTS.md for Codex / OpenCode from Cursor rules',
    AgentResourceKind.command =>
      'One-click conversion: mirror Cursor commands into OpenCode commands/<name>.md (extra commands are removed; Codex has no equivalent directory)',
    AgentResourceKind.hook =>
      'One-click conversion: generate Codex hooks.json and hooks/ from Cursor hooks.json and hooks/ (event names and matchers are adapted to Codex; OpenCode has no equivalent hooks.json)',
  };

  bool get _canConvert =>
      resource.canConvertTo(SkillTarget.codex) ||
      resource.canConvertTo(SkillTarget.openCode);

  String? _pathLabelFor(HubController hub, SkillTarget target) {
    if (resource == AgentResourceKind.rule && target == SkillTarget.codex) {
      return McpPaths.codexAgentsMdPath;
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
          title: const Text('Apply to Cursor?'),
          content: Text(
            'This will mirror the cached $scope into the official Cursor directory.\n\n'
            'Local Cursor files and directories missing from the cache will also be deleted.\n\n'
            'This does not convert Codex / OpenCode; use Convert Folder resources when needed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Confirm apply'),
            ),
          ],
        ),
      ) ??
      false;
}
