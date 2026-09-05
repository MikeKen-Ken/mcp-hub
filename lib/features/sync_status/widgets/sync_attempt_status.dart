import 'package:flutter/material.dart';

import '../last_sync_attempt.dart';
import '../last_sync_attempt_label.dart';

/// Version line plus last WebDAV attempt, with Syncing kept beside the last result.
class SyncAttemptStatus extends StatelessWidget {
  const SyncAttemptStatus({
    super.key,
    required this.attempt,
    this.versionLabel,
    this.syncing = false,
    this.unavailableLabel,
  });

  final LastSyncAttempt? attempt;
  final String? versionLabel;
  final bool syncing;
  final String? unavailableLabel;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    final version = versionLabel?.trim();
    final attemptLine = lastSyncAttemptOverviewLabel(
      latest: attempt,
      syncing: syncing,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (unavailableLabel != null)
          Text(unavailableLabel!, style: style)
        else if (version != null && version.isNotEmpty)
          Text(version, style: style),
        Text(attemptLine, style: style),
      ],
    );
  }
}
