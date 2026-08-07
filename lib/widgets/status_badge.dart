import 'package:flutter/material.dart';

/// 与标题文字行高对齐的紧凑状态标签（避免 Material Chip 撑高导致上下不居中）。
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    this.tonal = false,
  });

  final String label;
  final bool tonal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bg = tonal ? scheme.secondaryContainer : scheme.surfaceContainerHighest;
    final fg = tonal ? scheme.onSecondaryContainer : scheme.onSurfaceVariant;

    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          height: 1.2,
          leadingDistribution: TextLeadingDistribution.even,
        ),
      ),
    );
  }
}
