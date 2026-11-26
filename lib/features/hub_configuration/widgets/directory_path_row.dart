import 'package:flutter/material.dart';

import '../../../common/app_locale.dart';
import '../../../services/directory_opener.dart';
import '../../../widgets/hub_notice/hub_notice.dart';

class DirectoryPathRow extends StatelessWidget {
  const DirectoryPathRow({
    super.key,
    required this.label,
    required this.displayPath,
    required this.directoryPath,
    required this.enabled,
  });

  final String label;
  final String? displayPath;
  final String? directoryPath;
  final bool enabled;

  Future<void> _open(BuildContext context) async {
    try {
      await DirectoryOpener.open(directoryPath);
    } catch (error) {
      if (!context.mounted) return;
      showHubNotice(
        context,
        message: tr('打开目录失败：$error', 'Failed to open directory: $error'),
        ok: false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SelectableText(
            '$label: ${displayPath ?? tr('(不可用)', '(unavailable)')}',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
        IconButton(
          tooltip: tr('打开 $label 目录', 'Open $label directory'),
          onPressed: enabled && directoryPath != null
              ? () => _open(context)
              : null,
          icon: const Icon(Icons.folder_open_outlined),
        ),
      ],
    );
  }
}
