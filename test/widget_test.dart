import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_hub/app.dart';
import 'package:mcp_hub/app_brand.dart';
import 'package:mcp_hub/controllers/hub_controller.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('home shows Agent Hub title', (tester) async {
    final hub = HubController(initiallyLoading: false);
    addTearDown(hub.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: hub,
        child: const McpHubApp(),
      ),
    );
    await tester.pump();
    expect(find.text(AppBrand.displayName), findsOneWidget);
    expect(find.text('客户端 MCP'), findsOneWidget);
    expect(find.text('Agent 配置同步'), findsOneWidget);
    expect(find.text('本地 MCP'), findsNothing);

    await tester.tap(find.text('客户端 MCP'));
    await tester.pumpAndSettle();
    expect(find.text('本地 MCP'), findsOneWidget);

    await tester.tap(find.text('本地 MCP'));
    await tester.pumpAndSettle();
    expect(find.text('添加 MCP'), findsOneWidget);

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
