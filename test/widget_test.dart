import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_hub/app.dart';
import 'package:mcp_hub/app_brand.dart';
import 'package:mcp_hub/controllers/hub_controller.dart';
import 'package:mcp_hub/webdav/webdav_config.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('Esc 依次关闭弹窗和返回上一页，根页面保持打开', (tester) async {
    final hub = HubController(initiallyLoading: false);
    addTearDown(hub.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(value: hub, child: const McpHubApp()),
    );
    await tester.pump();

    await tester.tap(find.text('2  应用到 Cursor'));
    await tester.pumpAndSettle();
    expect(find.text('确认应用到 Cursor？'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('确认应用到 Cursor？'), findsNothing);

    await tester.tap(find.byTooltip('WebDAV 设置'));
    await tester.pumpAndSettle();
    expect(find.text('WebDAV 下载/上传'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('配置中心'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('配置中心'), findsOneWidget);
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
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    await tester.pumpWidget(
      ChangeNotifierProvider.value(value: hub, child: const McpHubApp()),
    );
    await tester.pump();
    expect(find.text(AppBrand.displayName), findsOneWidget);
    expect(find.text('Agent 配置'), findsOneWidget);
    expect(find.text('2  应用到 Cursor'), findsOneWidget);
    expect(find.text('配置备份'), findsNothing);
    expect(find.text('本地 MCP'), findsNothing);

    expect(find.text('按资源管理'), findsOneWidget);
    expect(find.text('MCP'), findsOneWidget);
    expect(find.text('Skill'), findsOneWidget);
    expect(find.text('Command'), findsOneWidget);
    expect(find.text('Rule'), findsOneWidget);
    expect(find.text('Hook'), findsOneWidget);
    expect(find.text('打开 MCP 设置'), findsOneWidget);
    expect(find.text('一键转换'), findsWidgets);

    await tester.tap(find.text('2  应用到 Cursor'));
    await tester.pumpAndSettle();
    expect(find.text('确认应用到 Cursor？'), findsOneWidget);
    expect(find.text('确认应用'), findsOneWidget);
    expect(find.textContaining('本操作不会转换 Codex / Open Code'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('确认应用到 Cursor？'), findsNothing);

    await tester.tap(find.text('3  上传全部'));
    await tester.pumpAndSettle();
    expect(find.text('确认覆盖远端？'), findsOneWidget);
    expect(find.text('确认上传'), findsOneWidget);
    expect(find.textContaining('远端同名压缩包会被整包覆盖'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('确认覆盖远端？'), findsNothing);

    final mcpCard = find.ancestor(
      of: find.text('打开 MCP 设置'),
      matching: find.byType(Card),
    );
    final mcpApply = find.descendant(of: mcpCard, matching: find.text('写入客户端'));
    await tester.ensureVisible(mcpApply);
    await tester.tap(mcpApply);
    await tester.pumpAndSettle();
    expect(find.text('确认写入客户端？'), findsOneWidget);
    expect(find.textContaining('当前全部 MCP'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    final mcpUpload = find.descendant(of: mcpCard, matching: find.text('上传'));
    await tester.ensureVisible(mcpUpload);
    await tester.tap(mcpUpload);
    await tester.pumpAndSettle();
    expect(find.text('确认覆盖远端？'), findsOneWidget);
    expect(find.textContaining('本机「MCP 清单」'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('WebDAV 设置'));
    await tester.pumpAndSettle();
    expect(find.text('配置备份'), findsOneWidget);
    await tester.tap(find.text('配置备份'));
    await tester.pumpAndSettle();
    expect(find.text('导出 / 导入'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
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
