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
            '即将把本机「$scope」打包上传到 WebDAV。\n\n'
            '远端同名压缩包会被整包覆盖，其他设备上尚未同步下来的远端内容会丢失。',
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
