import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../common/app_locale.dart';
import '../../controllers/hub_controller.dart';
import '../../widgets/hub_notice/hub_notice.dart';
import '../../widgets/status_badge.dart';
import 'operation_log_entry.dart';

enum _StatusFilter { all, success, failed }

class OperationLogsScreen extends StatefulWidget {
  const OperationLogsScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<OperationLogsScreen> createState() => _OperationLogsScreenState();
}

class _OperationLogsScreenState extends State<OperationLogsScreen> {
  final _searchController = TextEditingController();
  OperationLogCategory? _categoryFilter;
  _StatusFilter _statusFilter = _StatusFilter.all;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<OperationLogEntry> _filter(List<OperationLogEntry> all) {
    final q = _query.trim().toLowerCase();
    return all
        .where((entry) {
          if (_categoryFilter != null && entry.category != _categoryFilter) {
            return false;
          }
          switch (_statusFilter) {
            case _StatusFilter.all:
              break;
            case _StatusFilter.success:
              if (entry.status != OperationLogStatus.success) return false;
            case _StatusFilter.failed:
              if (entry.status == OperationLogStatus.success) return false;
          }
          if (q.isEmpty) return true;
          return entry.action.toLowerCase().contains(q) ||
              (entry.target?.toLowerCase().contains(q) ?? false) ||
              entry.summary.toLowerCase().contains(q) ||
              entry.detail.toLowerCase().contains(q);
        })
        .toList(growable: false);
  }

  Future<void> _copyFiltered(
    BuildContext context,
    HubController hub,
    List<OperationLogEntry> filtered,
  ) async {
    final text = hub.operationLogs.exportText(items: filtered);
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    showHubNotice(
      context,
      message: tr(
        '已复制 ${filtered.length} 条日志到剪贴板',
        'Copied ${filtered.length} log entries to clipboard',
      ),
      ok: true,
    );
  }

  Future<void> _exportFiltered(
    BuildContext context,
    HubController hub,
    List<OperationLogEntry> filtered,
  ) async {
    final text = hub.operationLogs.exportText(items: filtered);
    if (text.isEmpty) return;
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final suggested =
        'AgentHub-logs-${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}.txt';
    final location = await getSaveLocation(
      suggestedName: suggested,
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Text', extensions: ['txt', 'log']),
      ],
    );
    if (location == null || !context.mounted) return;
    try {
      await File(location.path).writeAsString(text, flush: true);
      if (!context.mounted) return;
      showHubNotice(
        context,
        message: tr(
          '已导出 ${filtered.length} 条日志 → ${location.path}',
          'Exported ${filtered.length} log entries → ${location.path}',
        ),
        ok: true,
      );
    } catch (error) {
      if (!context.mounted) return;
      showHubNotice(
        context,
        message: tr('导出日志失败：$error', 'Failed to export logs: $error'),
        ok: false,
      );
    }
  }

  Future<void> _confirmClear(BuildContext context, HubController hub) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr('清空全部操作日志？', 'Clear all operation logs?')),
        content: Text(
          tr(
            '这会删除当前保存的 ${hub.operationLogs.length} 条历史记录，且无法撤销。',
            'This will delete all ${hub.operationLogs.length} saved log entries and cannot be undone.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(tr('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(tr('确认清空', 'Clear')),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await hub.operationLogs.clear();
    if (!context.mounted) return;
    showHubNotice(context, message: tr('已清空操作日志', 'Operation logs cleared'), ok: true);
  }

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<HubController>();
    final all = hub.operationLogs.entries;
    final filtered = _filter(all);
    final successCount = filtered
        .where((e) => e.status == OperationLogStatus.success)
        .length;
    final partialCount = filtered
        .where((e) => e.status == OperationLogStatus.partial)
        .length;
    final failureCount = filtered
        .where((e) => e.status == OperationLogStatus.failure)
        .length;

    final actions = <Widget>[
      IconButton(
        tooltip: tr('复制当前筛选日志', 'Copy filtered logs'),
        onPressed: filtered.isEmpty
            ? null
            : () => _copyFiltered(context, hub, filtered),
        icon: const Icon(Icons.copy_all_outlined, size: 19),
      ),
      if (hub.isDesktopSupported)
        IconButton(
          tooltip: tr('导出为文本文件', 'Export to text file'),
          onPressed: filtered.isEmpty
              ? null
              : () => _exportFiltered(context, hub, filtered),
          icon: const Icon(Icons.download_outlined, size: 19),
        ),
      IconButton(
        tooltip: tr('清空日志', 'Clear logs'),
        onPressed: all.isEmpty ? null : () => _confirmClear(context, hub),
        icon: const Icon(Icons.delete_sweep_outlined, size: 19),
      ),
    ];

    final bodyContent = Column(
      children: [
        if (widget.embedded)
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 22, 28, 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('操作日志', 'Operation Logs'),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        tr(
                          '查看全部同步、下载、上传、应用、转换、MCP 与备份操作明细。',
                          'Review detailed records for sync, transfer, apply, convert, MCP, and backup operations.',
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                ...actions,
              ],
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            widget.embedded ? 28 : 16,
            12,
            widget.embedded ? 28 : 16,
            8,
          ),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: tr(
                      '搜索操作、目标、结果或错误信息…',
                      'Search action, target, result, or error…',
                    ),
                    isDense: true,
                    border: const OutlineInputBorder(),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: tr('清除搜索', 'Clear search'),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                            icon: const Icon(Icons.clear),
                          ),
                  ),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: Text(tr('全部类型', 'All')),
                        selected: _categoryFilter == null,
                        onSelected: (_) => setState(() => _categoryFilter = null),
                      ),
                      const SizedBox(width: 6),
                      for (final category in OperationLogCategory.values) ...[
                        ChoiceChip(
                          label: Text(category.label),
                          selected: _categoryFilter == category,
                          onSelected: (_) => setState(
                            () => _categoryFilter =
                                _categoryFilter == category ? null : category,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    ChoiceChip(
                      label: Text(tr('全部结果', 'All results')),
                      selected: _statusFilter == _StatusFilter.all,
                      onSelected: (_) =>
                          setState(() => _statusFilter = _StatusFilter.all),
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: Text(tr('仅成功', 'Success only')),
                      selected: _statusFilter == _StatusFilter.success,
                      onSelected: (_) =>
                          setState(() => _statusFilter = _StatusFilter.success),
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: Text(tr('仅异常/失败', 'Errors only')),
                      selected: _statusFilter == _StatusFilter.failed,
                      onSelected: (_) =>
                          setState(() => _statusFilter = _StatusFilter.failed),
                    ),
                    const Spacer(),
                    Text(
                      tr(
                        '共 ${filtered.length} 条（成功 $successCount · 部分失败 $partialCount · 失败 $failureCount）',
                        '${filtered.length} total ($successCount ok · $partialCount partial · $failureCount failed)',
                      ),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        all.isEmpty
                            ? tr(
                                '暂无历史操作记录。执行同步、下载、上传、应用或转换后，记录会自动保存在这里。',
                                'No operation logs yet. Sync, download, upload, apply, or convert actions will be recorded here.',
                              )
                            : tr('没有符合当前筛选条件的日志', 'No logs match the current filter'),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.fromLTRB(
                      widget.embedded ? 28 : 16,
                      12,
                      widget.embedded ? 28 : 16,
                      24,
                    ),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) =>
                        _OperationLogTile(entry: filtered[index]),
                  ),
          ),
        ],
      );

    if (widget.embedded) {
      return Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: bodyContent,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('操作日志', 'Operation Logs')),
        actions: actions,
      ),
      body: bodyContent,
    );
  }
}

class _OperationLogTile extends StatelessWidget {
  const _OperationLogTile({required this.entry});

  final OperationLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (icon, iconColor, badgeBg, badgeFg) = switch (entry.status) {
      OperationLogStatus.success => (
        Icons.check_circle_outline,
        scheme.primary,
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
      ),
      OperationLogStatus.partial => (
        Icons.warning_amber_rounded,
        Colors.orange.shade800,
        Colors.orange.shade100,
        Colors.orange.shade900,
      ),
      OperationLogStatus.failure => (
        Icons.error_outline,
        scheme.error,
        scheme.errorContainer,
        scheme.onErrorContainer,
      ),
    };

    final metaParts = <String>[
      entry.formattedTime,
      entry.category.label,
      if (entry.formattedDuration != null) entry.formattedDuration!,
      ...entry.metricChips,
    ];

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.fromLTRB(14, 6, 12, 6),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        leading: Icon(icon, color: iconColor),
        title: Row(
          children: [
            Flexible(
              child: Text(
                entry.target == null || entry.target!.trim().isEmpty
                    ? entry.action
                    : '${entry.action} · ${entry.target}',
                style: theme.textTheme.titleSmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: badgeBg,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                entry.status.label,
                style: theme.textTheme.labelSmall?.copyWith(color: badgeFg),
              ),
            ),
            if (entry.trigger == OperationLogTrigger.auto) ...[
              const SizedBox(width: 6),
              StatusBadge(label: entry.trigger.label, tonal: true),
            ],
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.summary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Text(
                metaParts.join(' · '),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              entry.detail.trim().isEmpty ? entry.summary : entry.detail,
              style: theme.textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: entry.toPlainText()));
                showHubNotice(
                  context,
                  message: tr('已复制该条日志详情', 'Log entry copied'),
                  ok: true,
                );
              },
              icon: const Icon(Icons.copy_outlined, size: 18),
              label: Text(tr('复制详情', 'Copy details')),
            ),
          ),
        ],
      ),
    );
  }
}
