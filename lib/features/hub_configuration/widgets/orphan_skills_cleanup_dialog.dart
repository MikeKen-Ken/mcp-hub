import 'package:flutter/material.dart';

import '../../../common/agent_platforms.dart';
import '../../../common/app_locale.dart';
import '../../../common/app_theme.dart';
import '../../../widgets/hub_notice/hub_notice.dart';
import '../../skill_sync/orphan_skills_cleaner.dart';

/// 扫描并让用户勾选清理目标端多余 Skill（及旧版废弃 Codex 缓存）的弹窗。
Future<void> showOrphanSkillsCleanupDialog(BuildContext context) async {
  final result = await showDialog<OrphanSkillDeleteResult>(
    context: context,
    builder: (_) => const _OrphanSkillsCleanupDialog(),
  );
  if (result == null || !context.mounted) return;
  if (!result.ok) {
    showHubNotice(
      context,
      message: tr(
        '部分清理失败（已清理 ${result.deletedSkillCount} 个 Skill）：${result.errors.join('；')}',
        'Partially failed (cleaned ${result.deletedSkillCount} Skills): ${result.errors.join('; ')}',
      ),
      ok: false,
    );
    return;
  }

  final parts = <String>[];
  if (result.deletedSkillCount > 0) {
    parts.add(
      tr(
        '已清理 ${result.deletedSkillCount} 个多余 Skill（共 ${result.deletedDirectoryCount} 个目录）',
        'Cleaned ${result.deletedSkillCount} extra Skills (${result.deletedDirectoryCount} directories)',
      ),
    );
  }
  if (result.deletedObsoleteCodexCache) {
    parts.add(
      tr('已清理旧版废弃 Codex 缓存', 'Removed obsolete Codex cache directory'),
    );
  }
  if (parts.isNotEmpty) {
    showHubNotice(context, message: parts.join('；'), ok: true);
  }
}

class _OrphanSkillsCleanupDialog extends StatefulWidget {
  const _OrphanSkillsCleanupDialog();

  @override
  State<_OrphanSkillsCleanupDialog> createState() =>
      _OrphanSkillsCleanupDialogState();
}

class _OrphanSkillsCleanupDialogState
    extends State<_OrphanSkillsCleanupDialog> {
  final _cleaner = const OrphanSkillsCleaner();

  OrphanSkillScanResult? _scan;
  Object? _scanError;
  final Set<String> _selectedNames = {};
  bool _deleteObsoleteCache = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final scan = await _cleaner.scan();
      if (!mounted) return;
      setState(() {
        _scan = scan;
        _deleteObsoleteCache = scan.obsoleteCodexCacheExists;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _scanError = error);
    }
  }

  Future<void> _confirmDelete() async {
    final scan = _scan;
    if (scan == null || _deleting) return;
    final selectedEntries = scan.entries
        .where((e) => _selectedNames.contains(e.name))
        .toList();
    if (selectedEntries.isEmpty && !_deleteObsoleteCache) return;

    setState(() => _deleting = true);
    final result = await _cleaner.deleteSelected(
      selectedEntries: selectedEntries,
      deleteObsoleteCodexCachePath:
          _deleteObsoleteCache ? scan.obsoleteCodexCachePath : null,
    );
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final scan = _scan;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final allSelected =
        scan != null &&
        scan.entries.isNotEmpty &&
        _selectedNames.length == scan.entries.length;
    final selectedCount = _selectedNames.length;
    final canDelete =
        !_deleting &&
        scan != null &&
        (selectedCount > 0 || _deleteObsoleteCache);

    return AlertDialog(
      title: Text(
        tr('检查并清理多余 Skill', 'Check & Clean Extra Skills'),
      ),
      content: SizedBox(
        width: 560,
        child: _buildBody(context, theme, scheme, scan, allSelected),
      ),
      actions: [
        TextButton(
          onPressed: _deleting ? null : () => Navigator.of(context).pop(),
          child: Text(scan != null && scan.isEmpty
              ? tr('关闭', 'Close')
              : tr('取消', 'Cancel')),
        ),
        if (scan != null && !scan.isEmpty)
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: canDelete ? _confirmDelete : null,
            child: _deleting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    selectedCount > 0
                        ? tr('删除所选 ($selectedCount)', 'Delete Selected ($selectedCount)')
                        : tr('清理旧缓存', 'Clean Old Cache'),
                  ),
          ),
      ],
    );
  }

  Widget _buildBody(
    BuildContext context,
    ThemeData theme,
    ColorScheme scheme,
    OrphanSkillScanResult? scan,
    bool allSelected,
  ) {
    if (_scanError != null) {
      return Text(
        tr('扫描失败：$_scanError', 'Scan failed: $_scanError'),
        style: TextStyle(color: scheme.error),
      );
    }
    if (scan == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(
              tr('正在扫描各客户端 Skill 目录…', 'Scanning client Skill directories…'),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      );
    }
    if (scan.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline, color: scheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                tr(
                  '所有目标端与 Cursor 主源一致，未发现多余 Skill 或废弃缓存。',
                  'All target clients match Cursor; no extra Skills or obsolete cache found.',
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (scan.entries.isNotEmpty) ...[
          Text(
            tr(
              '以下 Skill 存在于其他客户端目录，但 Cursor 主源中已不存在。请只勾选确认废弃的历史残留；客户端自带或市场安装的 Skill 请勿勾选。',
              'These Skills exist in target clients but are missing from Cursor. Select only stale leftovers; leave client built-in or marketplace Skills unchecked.',
            ),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                tr(
                  '共 ${scan.entries.length} 项',
                  '${scan.entries.length} found',
                ),
                style: theme.textTheme.labelMedium,
              ),
              const Spacer(),
              TextButton(
                onPressed: _deleting
                    ? null
                    : () {
                        setState(() {
                          if (allSelected) {
                            _selectedNames.clear();
                          } else {
                            _selectedNames
                              ..clear()
                              ..addAll(scan.entries.map((e) => e.name));
                          }
                        });
                      },
                child: Text(
                  allSelected
                      ? tr('取消全选', 'Deselect all')
                      : tr('全选', 'Select all'),
                ),
              ),
            ],
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppTheme.subtleBg(context),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.hairline(context)),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: scan.entries.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final entry = scan.entries[index];
                  final checked = _selectedNames.contains(entry.name);
                  final targetsText = entry.locations
                      .map((l) => AgentPlatforms.labelOf(l.target))
                      .join(' · ');
                  final subtitle = entry.description == null
                      ? targetsText
                      : '$targetsText\n${entry.description}';
                  return CheckboxListTile(
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: checked,
                    onChanged: _deleting
                        ? null
                        : (v) {
                            setState(() {
                              if (v == true) {
                                _selectedNames.add(entry.name);
                              } else {
                                _selectedNames.remove(entry.name);
                              }
                            });
                          },
                    title: Text(
                      entry.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
        if (scan.obsoleteCodexCacheExists) ...[
          const SizedBox(height: 10),
          CheckboxListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 6),
            controlAffinity: ListTileControlAffinity.leading,
            value: _deleteObsoleteCache,
            onChanged: _deleting
                ? null
                : (v) => setState(() => _deleteObsoleteCache = v == true),
            title: Text(
              tr(
                '同时清理旧版废弃 Codex 缓存目录',
                'Also remove obsolete Codex cache folder',
              ),
              style: theme.textTheme.bodyMedium,
            ),
            subtitle: Text(
              scan.obsoleteCodexCachePath ?? '',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ],
    );
  }
}
