import 'package:flutter/material.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleSmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      letterSpacing: 0.2,
    );
    if (trailing == null) {
      return Text(title, style: style);
    }
    return Row(
      children: [
        Expanded(child: Text(title, style: style)),
        trailing!,
      ],
    );
  }
}
