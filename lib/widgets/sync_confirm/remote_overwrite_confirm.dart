import 'package:flutter/material.dart';

import '../../common/app_locale.dart';

/// 手动上传前确认：远端同名压缩包会被本机内容整包覆盖。
Future<bool> confirmRemoteOverwrite(
  BuildContext context, {
  required String scope,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(tr('确认覆盖远端压缩包？', 'Replace remote package?')),
          content: Text(
            tr(
              '这会打包本地「$scope」并上传到 WebDAV。\n\n'
                  '远端同名压缩包将被完全替换，其他设备尚未同步的内容可能会丢失。',
              'This will package the local "$scope" and upload it to WebDAV.\n\n'
                  'The remote archive with the same name will be completely replaced. Unsynced content from other devices will be lost.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(tr('取消', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(tr('确认上传', 'Confirm upload')),
            ),
          ],
        ),
      ) ??
      false;
}
