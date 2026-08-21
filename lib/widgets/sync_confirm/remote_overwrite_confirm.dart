import 'package:flutter/material.dart';

/// 手动上传前确认：远端同名压缩包会被本机内容整包覆盖。
Future<bool> confirmRemoteOverwrite(
  BuildContext context, {
  required String scope,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Replace remote package?'),
          content: Text(
            'This will package the local "$scope" and upload it to WebDAV.\n\n'
            'The remote archive with the same name will be completely replaced. Unsynced content from other devices will be lost.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Confirm upload'),
            ),
          ],
        ),
      ) ??
      false;
}
