import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../common/app_locale.dart';
import '../../common/app_motion.dart';
import '../../controllers/hub_controller.dart';
import '../../widgets/status_badge.dart';
import 'operation_log_entry.dart';
import 'operation_logs_screen.dart';

/// 首页底部的「最近操作日志」概览卡片，快速查看最近同步/上传/下载/转换结果。
class RecentOperationLogsCard extends StatelessWidget {
  const RecentOperationLogsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<HubController>();
    final entries = hub.operationLogs.entries;
    final recent = entries.take(5).toList(growable: false);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.history, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr(
                      '最近操作日志（共 ${entries.length} 条）',
                      'Recent Operation Logs (${entries.length})',
                    ),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => pushAppPage<void>(
                    context,
                    const OperationLogsScreen(),
                  ),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: Text(tr('查看全部', 'View all')),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (recent.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  tr(
                    '暂无历史操作记录。执行同步、下载、上传、应用或转换后，会在这里记录执行结果与明细。',
                    'No operation logs yet. Results from sync, download, upload, apply, and convert will appear here.',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              for (var i = 0; i < recent.length; i++) ...[
                if (i > 0) const Divider(height: 12),
                _RecentLogRow(
                  entry: recent[i],
                  onTap: () => pushAppPage<void>(
                    context,
                    const OperationLogsScreen(),
                  ),
                ),
              ],
          ],
        ),
      ),
    );
  }
}

class _RecentLogRow extends StatelessWidget {
  const _RecentLogRow({required this.entry, required this.onTap});

  final OperationLogEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (icon, iconColor) = switch (entry.status) {
      OperationLogStatus.success => (
        Icons.check_circle_outline,
        scheme.primary,
      ),
      OperationLogStatus.partial => (
        Icons.warning_amber_rounded,
        Colors.orange.shade800,
      ),
      OperationLogStatus.failure => (Icons.error_outline, scheme.error),
    };

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          entry.target == null || entry.target!.trim().isEmpty
                              ? entry.action
                              : '${entry.action} · ${entry.target}',
                          style: theme.textTheme.labelLarge,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      StatusBadge(
                        label: entry.status.label,
                        active: entry.status == OperationLogStatus.success,
                        tonal: entry.status == OperationLogStatus.partial,
                      ),
                      if (entry.trigger == OperationLogTrigger.auto) ...[
                        const SizedBox(width: 4),
                        StatusBadge(label: entry.trigger.label),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    entry.summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              entry.formattedTime.substring(5),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
