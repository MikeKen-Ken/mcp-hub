import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_hub/app.dart';
import 'package:mcp_hub/app_brand.dart';
import 'package:mcp_hub/controllers/hub_controller.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('Esc 依次关闭弹窗和返回上一页，根页面保持打开', (tester) async {
    final hub = HubController(initiallyLoading: false);
    addTearDown(hub.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(value: hub, child: const McpHubApp()),
    );
    await tester.pump();

    await tester.tap(find.text('Agent 配置下载/上传'));
    await tester.pumpAndSettle();
    expect(find.text('按资源管理'), findsOneWidget);

    await tester.tap(find.text('2  更新/覆盖全部'));
    await tester.pumpAndSettle();
    expect(find.text('确认更新/覆盖？'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('确认更新/覆盖？'), findsNothing);
    expect(find.text('按资源管理'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('配置中心'), findsOneWidget);
    expect(find.text('按资源管理'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('配置中心'), findsOneWidget);
  });

  testWidgets('home shows Agent Hub title', (tester) async {
    final hub = HubController(initiallyLoading: false);
    addTearDown(hub.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(value: hub, child: const McpHubApp()),
    );
    await tester.pump();
    expect(find.text(AppBrand.displayName), findsOneWidget);
    expect(find.text('Agent 配置下载/上传'), findsOneWidget);
    expect(find.text('本地 MCP'), findsNothing);

    await tester.tap(find.text('Agent 配置下载/上传'));
    await tester.pumpAndSettle();
    expect(find.text('按资源管理'), findsOneWidget);
    expect(find.text('MCP'), findsOneWidget);
    expect(find.text('Skill'), findsOneWidget);
    expect(find.text('Command'), findsOneWidget);
    expect(find.text('Rule'), findsOneWidget);
    expect(find.text('打开 MCP 设置'), findsOneWidget);

    await tester.tap(find.text('2  更新/覆盖全部'));
    await tester.pumpAndSettle();
    expect(find.text('确认更新/覆盖？'), findsOneWidget);
    expect(find.text('继续覆盖'), findsOneWidget);
    expect(find.textContaining('缓存中不存在的本地文件和目录也会被删除。'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('确认更新/覆盖？'), findsNothing);

    final mcpApply = find.text('更新/覆盖').first;
    await tester.ensureVisible(mcpApply);
    await tester.tap(mcpApply);
    await tester.pumpAndSettle();
    expect(find.text('确认更新/覆盖？'), findsOneWidget);
    expect(find.textContaining('当前已启用的 MCP'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    final mcpSettings = find.text('打开 MCP 设置');
    await tester.ensureVisible(mcpSettings);
    await tester.tap(mcpSettings);
    await tester.pumpAndSettle();
    expect(find.text('客户端 MCP'), findsOneWidget);
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
