import 'package:flutter/material.dart';

import '../../common/app_motion.dart';
import '../../common/sync_progress.dart';
import '../hub_notice/hub_notice.dart';

/// 下载/上传进行中显示进度；失败后常驻在按钮附近，直到下次成功。
class OpStatusBar extends StatelessWidget {
  const OpStatusBar({super.key, this.progress, this.errorMessage});

  final SyncProgress? progress;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final duration = AppMotion.durationOf(context, AppMotion.fast);
    final progress = this.progress;
    Widget child;
    if (progress != null) {
      child = _ProgressStrip(
        key: const ValueKey('progress'),
        progress: progress,
      );
    } else {
      final error = errorMessage?.trim();
      child = error != null && error.isNotEmpty
          ? _FailureStrip(key: const ValueKey('error'), message: error)
          : const SizedBox.shrink(key: ValueKey('idle'));
    }

    return AnimatedSize(
      duration: duration,
      curve: AppMotion.emphasized,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: duration,
        switchInCurve: AppMotion.emphasized,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SizeTransition(
            sizeFactor: animation,
            alignment: Alignment.topCenter,
            child: child,
          ),
        ),
        child: child,
      ),
    );
  }
}

class _ProgressStrip extends StatelessWidget {
  const _ProgressStrip({super.key, required this.progress});

  final SyncProgress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            progress.caption,
            style: theme.textTheme.labelMedium?.copyWith(color: scheme.primary),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(minHeight: 6, value: progress.value),
          ),
        ],
      ),
    );
  }
}

class _FailureStrip extends StatelessWidget {
  const _FailureStrip({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final notice = HubNotice.fromMessage(message, ok: false);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
          child: Row(
            children: [
              Icon(Icons.error, size: 18, color: scheme.onErrorContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Last failure: ${notice.title}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onErrorContainer,
                  ),
                ),
              ),
              TextButton(
                onPressed: () =>
                    showHubNoticeDetail(context, message, ok: false),
                style: TextButton.styleFrom(
                  foregroundColor: scheme.onErrorContainer,
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Details'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
