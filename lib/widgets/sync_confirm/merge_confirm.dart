import 'package:flutter/material.dart';

import '../../common/app_locale.dart';

/// Merge that changes the live Hub Catalog, or Hub configuration including Catalog.
Future<bool> confirmCatalogMerge(BuildContext context) {
  return confirmLiveCatalogMerge(
    context,
    title: tr('确认合并 MCP 清单？', 'Merge the Catalog?'),
    body: tr(
      '这会下载远端 MCP 清单并立即与本地 Hub 列表合并。\n\n'
          '客户端 MCP 配置暂不会改动。如需更新 Cursor / Codex / Open Code，请随后点击「写入客户端」。',
      'This will download the remote Catalog and merge it with the Hub list now.\n\n'
          'Client MCP config does not change. Use Write to Clients after this if you want Cursor / Codex / Open Code updated.',
    ),
  );
}

Future<bool> confirmHubConfigurationMerge(BuildContext context) {
  return confirmLiveCatalogMerge(
    context,
    title: tr('确认合并 Hub 配置？', 'Merge Hub configuration?'),
    body: tr(
      'MCP 清单合并会立即更新 Hub 列表；文件夹资源合并会写入本地 Hub 缓存。\n\n'
          'Cursor 正式目录和客户端 MCP 配置暂不会改动。',
      'Catalog merge changes the Hub list now. Folder resource merge writes the Hub cache.\n\n'
          'Cursor folders and Client MCP config do not change.',
    ),
  );
}

Future<bool> confirmLiveCatalogMerge(
  BuildContext context, {
  required String title,
  required String body,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(tr('取消', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(tr('确认合并', 'Confirm merge')),
            ),
          ],
        ),
      ) ??
      false;
}
