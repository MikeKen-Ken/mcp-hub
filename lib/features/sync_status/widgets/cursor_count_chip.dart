import 'package:flutter/material.dart';

/// Small header chip showing how many of this item Cursor currently has.
class CursorCountChip extends StatelessWidget {
  const CursorCountChip({
    super.key,
    required this.count,
    required this.tooltip,
  });

  final int count;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text('$count', style: Theme.of(context).textTheme.labelLarge),
      ),
    );
  }
}
