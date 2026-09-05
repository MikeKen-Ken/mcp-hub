import 'package:flutter/material.dart';

/// Merge that changes the live Hub Catalog, or Hub configuration including Catalog.
Future<bool> confirmCatalogMerge(BuildContext context) {
  return confirmLiveCatalogMerge(
    context,
    title: 'Merge the Catalog?',
    body:
        'This will download the remote Catalog and merge it with the Hub list now.\n\n'
        'Client MCP config does not change. Use Write to Clients after this if you want Cursor / Codex / Open Code updated.',
  );
}

Future<bool> confirmHubConfigurationMerge(BuildContext context) {
  return confirmLiveCatalogMerge(
    context,
    title: 'Merge Hub configuration?',
    body:
        'Catalog merge changes the Hub list now. Folder resource merge writes the Hub cache.\n\n'
        'Cursor folders and Client MCP config do not change.',
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
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Confirm merge'),
            ),
          ],
        ),
      ) ??
      false;
}
