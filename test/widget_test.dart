import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_hub/app.dart';
import 'package:mcp_hub/app_brand.dart';
import 'package:mcp_hub/controllers/hub_controller.dart';
import 'package:mcp_hub/webdav/webdav_config.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('Esc closes dialogs then the previous page; root stays open', (
    tester,
  ) async {
    final hub = HubController(initiallyLoading: false);
    addTearDown(hub.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(value: hub, child: const McpHubApp()),
    );
    await tester.pump();

    await tester.tap(find.text('Apply Folder resources'));
    await tester.pumpAndSettle();
    expect(find.text('Apply Folder resources?'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Apply Folder resources?'), findsNothing);

    await tester.tap(find.byTooltip('WebDAV settings'));
    await tester.pumpAndSettle();
    expect(find.text('WebDAV Download/Upload'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Configuration Center'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Configuration Center'), findsOneWidget);
  });

  testWidgets('home shows Agent Hub title', (tester) async {
    final hub = HubController(initiallyLoading: false);
    hub.webDavConfig = const WebDavConfig(
      enabled: true,
      serverUrl: 'https://dav.example.com',
      username: 'user',
      password: 'secret',
      remotePath: '/AgentHub',
      autoSync: false,
      autoPull: false,
      pollIntervalSeconds: WebDavConfig.defaultPollIntervalSeconds,
      pushDebounceSeconds: WebDavConfig.defaultPushDebounceSeconds,
    );
    addTearDown(hub.dispose);
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      ChangeNotifierProvider.value(value: hub, child: const McpHubApp()),
    );
    await tester.pump();
    expect(find.text(AppBrand.displayName), findsOneWidget);
    expect(find.text('Hub configuration'), findsWidgets);
    expect(find.text('Apply Folder resources'), findsOneWidget);
    expect(find.text('Configuration Backup'), findsNothing);
    expect(find.text('Local MCP'), findsNothing);

    expect(find.text('Catalog'), findsOneWidget);
    expect(find.text('Folder resources'), findsOneWidget);
    expect(find.text('MCP'), findsOneWidget);
    expect(find.text('Skill'), findsOneWidget);
    expect(find.text('Command'), findsOneWidget);
    expect(find.text('Rule'), findsOneWidget);
    expect(find.text('Hook'), findsOneWidget);
    expect(find.text('Open MCP Settings'), findsOneWidget);
    expect(find.text('Convert Folder resources'), findsOneWidget);
    expect(find.text('Download All'), findsNothing);
    expect(find.text('Upload All'), findsNothing);

    await tester.tap(find.text('Apply Folder resources'));
    await tester.pumpAndSettle();
    expect(find.text('Apply Folder resources?'), findsOneWidget);
    expect(find.text('Confirm apply'), findsOneWidget);
    expect(find.textContaining('does not write the Catalog'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Apply Folder resources?'), findsNothing);

    await tester.tap(find.text('Upload Hub configuration'));
    await tester.pumpAndSettle();
    expect(find.text('Replace remote package?'), findsOneWidget);
    expect(find.text('Confirm upload'), findsOneWidget);
    expect(
      find.textContaining('Hub configuration (Catalog and Folder resources)'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Replace remote package?'), findsNothing);

    await tester.tap(find.text('Merge Hub configuration'));
    await tester.pumpAndSettle();
    expect(find.text('Merge Hub configuration?'), findsOneWidget);
    expect(
      find.textContaining('Catalog merge changes the Hub list now'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    final mcpCard = find.ancestor(
      of: find.text('Open MCP Settings'),
      matching: find.byType(Card),
    );
    final mcpApply = find.descendant(
      of: mcpCard,
      matching: find.text('Write to Clients'),
    );
    await tester.ensureVisible(mcpApply);
    await tester.tap(mcpApply);
    await tester.pumpAndSettle();
    expect(find.text('Write to clients?'), findsOneWidget);
    expect(find.textContaining('all current MCPs'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    final mcpMerge = find.descendant(of: mcpCard, matching: find.text('Merge'));
    await tester.ensureVisible(mcpMerge);
    await tester.tap(mcpMerge);
    await tester.pumpAndSettle();
    expect(find.text('Merge the Catalog?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    final mcpUpload = find.descendant(
      of: mcpCard,
      matching: find.text('Upload'),
    );
    await tester.ensureVisible(mcpUpload);
    await tester.tap(mcpUpload);
    await tester.pumpAndSettle();
    expect(find.text('Replace remote package?'), findsOneWidget);
    expect(find.textContaining('Catalog'), findsWidgets);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('WebDAV settings'));
    await tester.pumpAndSettle();
    expect(find.text('Configuration Backup'), findsOneWidget);
    await tester.tap(find.text('Configuration Backup'));
    await tester.pumpAndSettle();
    expect(find.text('Export / Import'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    final mcpSettings = find.text('Open MCP Settings');
    await tester.ensureVisible(mcpSettings);
    await tester.tap(mcpSettings);
    await tester.pumpAndSettle();
    expect(find.text('Client MCP'), findsOneWidget);
    expect(find.text('Local MCP'), findsOneWidget);

    await tester.tap(find.text('Local MCP'));
    await tester.pumpAndSettle();
    expect(find.text('Add MCP'), findsOneWidget);

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    final theme = app.theme!;
    final styles = <TextStyle?>[
      theme.textTheme.displayLarge,
      theme.textTheme.displayMedium,
      theme.textTheme.displaySmall,
      theme.textTheme.headlineLarge,
      theme.textTheme.headlineMedium,
      theme.textTheme.headlineSmall,
      theme.textTheme.titleLarge,
      theme.textTheme.titleMedium,
      theme.textTheme.titleSmall,
      theme.textTheme.bodyLarge,
      theme.textTheme.bodyMedium,
      theme.textTheme.bodySmall,
      theme.textTheme.labelLarge,
      theme.textTheme.labelMedium,
      theme.textTheme.labelSmall,
    ];
    expect(styles.map((style) => style?.fontFamily).toSet(), {'Noto Sans SC'});
    expect(styles.map((style) => style?.fontWeight).toSet(), {FontWeight.w400});
  });
}
