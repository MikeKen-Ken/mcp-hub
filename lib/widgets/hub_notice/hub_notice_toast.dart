import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'hub_notice_copy.dart';

/// 在根层弹出短通知：成败用图标区分，长文进「详情」，切页后仍保留。
void showHubNotice(BuildContext context, {required String message, bool? ok}) {
  final notice = HubNotice.fromMessage(message, ok: ok);
  final messenger = _rootMessenger(context);
  if (messenger == null) return;
  final navigator = Navigator.maybeOf(context, rootNavigator: true);
  final scheme = Theme.of(context).colorScheme;
  final isError = notice.kind == HubNoticeKind.error;

  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      showCloseIcon: true,
      closeIconColor: isError ? scheme.onError : scheme.onInverseSurface,
      backgroundColor: isError ? scheme.error : null,
      duration: isError
          ? const Duration(seconds: 10)
          : const Duration(seconds: 5),
      content: _HubNoticeSnackContent(
        notice: notice,
        onDetail: !notice.hasDetail || navigator == null
            ? null
            : () {
                messenger.hideCurrentSnackBar();
                _showNoticeDetail(navigator.context, notice);
              },
      ),
    ),
  );
}

ScaffoldMessengerState? _rootMessenger(BuildContext context) {
  final navigator = Navigator.maybeOf(context, rootNavigator: true);
  if (navigator != null) {
    final root = ScaffoldMessenger.maybeOf(navigator.context);
    if (root != null) return root;
  }
  return ScaffoldMessenger.maybeOf(context);
}

/// 弹出完整说明（常驻失败条的「详情」也走这里）。
void showHubNoticeDetail(BuildContext context, String message, {bool? ok}) {
  _showNoticeDetail(context, HubNotice.fromMessage(message, ok: ok));
}

void _showNoticeDetail(BuildContext context, HubNotice notice) {
  final detail = notice.detail ?? notice.title;
  showDialog<void>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: Text(notice.kindLabel),
        content: SizedBox(width: 480, child: SelectableText(detail)),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: detail));
            },
            child: const Text('复制'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      );
    },
  );
}

class _HubNoticeSnackContent extends StatelessWidget {
  const _HubNoticeSnackContent({required this.notice, this.onDetail});

  final HubNotice notice;
  final VoidCallback? onDetail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final onBar = notice.kind == HubNoticeKind.error
        ? scheme.onError
        : scheme.onInverseSurface;
    final icon = switch (notice.kind) {
      HubNoticeKind.success => Icons.check_circle,
      HubNoticeKind.error => Icons.error,
      HubNoticeKind.info => Icons.info,
    };
    final iconColor = switch (notice.kind) {
      HubNoticeKind.success => scheme.inversePrimary,
      HubNoticeKind.error => scheme.onError,
      HubNoticeKind.info => onBar,
    };
    return Row(
      children: [
        Icon(icon, color: iconColor, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            notice.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: onBar,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        if (onDetail != null)
          TextButton(
            onPressed: onDetail,
            style: TextButton.styleFrom(
              foregroundColor: onBar,
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('详情'),
          ),
      ],
    );
  }
}
