import 'package:flutter/material.dart';

import '../../../common/app_theme.dart';

class SyncStatusPill extends StatelessWidget {
  const SyncStatusPill({
    super.key,
    required this.icon,
    required this.label,
    required this.active,
    this.error = false,
  });

  final IconData icon;
  final String label;
  final bool active;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = error
        ? scheme.errorContainer
        : active
        ? scheme.primaryContainer
        : AppTheme.subtleBg(context);
    final fg = error
        ? scheme.onErrorContainer
        : active
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;
    final border = error
        ? scheme.error.withValues(alpha: 0.25)
        : active
        ? scheme.primary.withValues(alpha: 0.28)
        : AppTheme.hairline(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg),
          ),
        ],
      ),
    );
  }
}
