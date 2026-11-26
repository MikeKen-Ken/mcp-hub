import 'package:flutter/material.dart';

import '../common/app_motion.dart';
import '../common/app_theme.dart';

/// 与标题文字行高对齐的紧凑状态标签。
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    this.tonal = false,
    this.active = false,
    this.error = false,
  });

  final String label;
  final bool tonal;
  final bool active;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bg = error
        ? scheme.errorContainer
        : active
        ? scheme.primaryContainer
        : tonal
        ? scheme.secondaryContainer
        : AppTheme.subtleBg(context);
    final fg = error
        ? scheme.onErrorContainer
        : active
        ? scheme.onPrimaryContainer
        : tonal
        ? scheme.onSecondaryContainer
        : scheme.onSurfaceVariant;
    final border = error
        ? scheme.error.withValues(alpha: 0.25)
        : active
        ? scheme.primary.withValues(alpha: 0.3)
        : AppTheme.hairline(context);

    return AnimatedContainer(
      duration: AppMotion.durationOf(context, AppMotion.fast),
      curve: AppMotion.emphasized,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: border),
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
