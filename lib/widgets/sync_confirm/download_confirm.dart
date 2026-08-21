import 'package:flutter/material.dart';

import '../../common/package_time.dart';

class RemotePackageDateQuery {
  const RemotePackageDateQuery({required this.label, required this.load});

  final String label;
  final Future<DateTime?> Function() load;
}

/// 下载覆盖前确认，并展示远端压缩包日期。
Future<bool> confirmRemoteDownload(
  BuildContext context, {
  required String title,
  required String body,
  required List<RemotePackageDateQuery> packages,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: _DownloadConfirmBody(body: body, packages: packages),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Confirm download'),
            ),
          ],
        ),
      ) ??
      false;
}

Future<bool> confirmCatalogReplace(
  BuildContext context, {
  required Future<DateTime?> Function() loadRemoteUploadedAt,
}) {
  return confirmRemoteDownload(
    context,
    title: 'Replace the local MCP catalog?',
    body:
        'This will download the remote catalog.zip and replace the local MCP list.\n\n'
        'Extra local entries will be removed; paths, secrets, and enabled states remain local.\n\n'
        'Use “Merge” if you want to keep entries from both sides.',
    packages: [
      RemotePackageDateQuery(label: 'MCP catalog', load: loadRemoteUploadedAt),
    ],
  );
}

class _DownloadConfirmBody extends StatefulWidget {
  const _DownloadConfirmBody({required this.body, required this.packages});

  final String body;
  final List<RemotePackageDateQuery> packages;

  @override
  State<_DownloadConfirmBody> createState() => _DownloadConfirmBodyState();
}

class _DownloadConfirmBodyState extends State<_DownloadConfirmBody> {
  late final List<Future<DateTime?>> _futures;

  @override
  void initState() {
    super.initState();
    _futures = [for (final package in widget.packages) package.load()];
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.body),
          const SizedBox(height: 16),
          for (var i = 0; i < widget.packages.length; i++)
            _RemoteDateLine(
              label: widget.packages[i].label,
              future: _futures[i],
            ),
        ],
      ),
    );
  }
}

class _RemoteDateLine extends StatelessWidget {
  const _RemoteDateLine({required this.label, required this.future});

  final String label;
  final Future<DateTime?> future;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: FutureBuilder<DateTime?>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Text('$label: Reading remote date…', style: style);
          }
          if (snapshot.hasError) {
            return Text('$label: Could not read remote date', style: style);
          }
          final time = snapshot.data;
          if (time == null) {
            return Text(
              '$label: No remote package or date available',
              style: style,
            );
          }
          return Text(
            '$label: remote version ${formatPackageTime(time)}',
            style: style,
          );
        },
      ),
    );
  }
}
