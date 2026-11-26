import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_hub/app.dart';
import 'package:mcp_hub/app_brand.dart';
import 'package:mcp_hub/common/app_locale.dart';
import 'package:mcp_hub/controllers/hub_controller.dart';
import 'package:mcp_hub/webdav/webdav_config.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppLocale.setLanguage(AppLanguage.zh);
  });

  testWidgets('Esc 先关闭弹窗再返回上一页，根页面保持打开', (tester) async {
    final hub = HubController(initiallyLoading: false);
    addTearDown(hub.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(value: hub, child: const McpHubApp()),
    );
    await tester.pump();

    await tester.tap(find.text('应用文件夹资源'));
    await tester.pumpAndSettle();
    expect(find.text('确认应用文件夹资源？'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('确认应用文件夹资源？'), findsNothing);

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

  testWidgets('首页默认中文显示、Apply 按钮使用深主色样式并支持查看操作日志', (tester) async {
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
    expect(find.text('配置中心'), findsOneWidget);
    expect(find.text('Hub 配置'), findsWidgets);
    expect(find.text('应用文件夹资源'), findsOneWidget);
    expect(find.text('转换文件夹资源'), findsOneWidget);
    expect(find.text('配置备份'), findsNothing);
    expect(find.text('本地 MCP'), findsNothing);

    expect(find.text('MCP 清单'), findsOneWidget);
    expect(find.text('文件夹资源'), findsOneWidget);
    expect(find.text('MCP'), findsOneWidget);
    expect(find.text('Skill'), findsOneWidget);
    expect(find.text('Command'), findsOneWidget);
    expect(find.text('Rule'), findsOneWidget);
    expect(find.text('Hook'), findsOneWidget);
    expect(find.text('打开 MCP 设置'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('最近操作日志'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('最近操作日志'), findsOneWidget);
    // 滚回顶部后再点击顶部卡片按钮，避免按钮被 AppBar 遮挡
    await tester.drag(find.byType(ListView).first, const Offset(0, 1200));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('应用文件夹资源'));

    // 验证「应用文件夹资源」与「转换文件夹资源」均为深主色 FilledButton（无 tonal 背景色）
    final applyButton = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('应用文件夹资源'),
        matching: find.byType(FilledButton),
      ),
    );
    final convertButton = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('转换文件夹资源'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(applyButton.style?.backgroundColor, isNull);
    expect(convertButton.style?.backgroundColor, isNull);

    // 验证卡片内「应用到 Cursor」同样使用深主色 FilledButton
    final applyCursorButtons = tester
        .widgetList<FilledButton>(
          find.ancestor(
            of: find.text('应用到 Cursor'),
            matching: find.byType(FilledButton),
          ),
        )
        .toList();
    expect(applyCursorButtons, isNotEmpty);
    for (final button in applyCursorButtons) {
      expect(button.style?.backgroundColor, isNull);
    }

    await tester.tap(find.text('应用文件夹资源'));
    await tester.pumpAndSettle();
    expect(find.text('确认应用文件夹资源？'), findsOneWidget);
    expect(find.text('确认应用'), findsOneWidget);
    expect(find.textContaining('不会把 MCP 清单写入客户端配置'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('确认应用文件夹资源？'), findsNothing);

    await tester.tap(find.text('上传 Hub 配置'));
    await tester.pumpAndSettle();
    expect(find.text('确认覆盖远端压缩包？'), findsOneWidget);
    expect(find.text('确认上传'), findsOneWidget);
    expect(find.textContaining('Hub 配置（MCP 清单与文件夹资源）'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('确认覆盖远端压缩包？'), findsNothing);

    await tester.tap(find.text('合并 Hub 配置'));
    await tester.pumpAndSettle();
    expect(find.text('确认合并 Hub 配置？'), findsOneWidget);
    expect(find.textContaining('清单合并会立即更新 Hub 列表'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    final mcpCard = find.ancestor(
      of: find.text('打开 MCP 设置'),
      matching: find.byType(Card),
    );
    final mcpApply = find.descendant(
      of: mcpCard,
      matching: find.text('写入客户端'),
    );
    await tester.ensureVisible(mcpApply);
    await tester.tap(mcpApply);
    await tester.pumpAndSettle();
    expect(find.text('确认写入客户端？'), findsOneWidget);
    expect(find.textContaining('当前全部 MCP'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    final mcpMerge = find.descendant(of: mcpCard, matching: find.text('合并'));
    await tester.ensureVisible(mcpMerge);
    await tester.tap(mcpMerge);
    await tester.pumpAndSettle();
    expect(find.text('确认合并 MCP 清单？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    final mcpUpload = find.descendant(of: mcpCard, matching: find.text('上传'));
    await tester.ensureVisible(mcpUpload);
    await tester.tap(mcpUpload);
    await tester.pumpAndSettle();
    expect(find.text('确认覆盖远端压缩包？'), findsOneWidget);
    expect(find.textContaining('MCP 清单'), findsWidgets);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    // 打开操作日志页面
    await tester.tap(find.byTooltip('操作日志'));
    await tester.pumpAndSettle();
    expect(find.text('操作日志'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('WebDAV 设置'));
    await tester.pumpAndSettle();
    expect(find.text('界面语言'), findsOneWidget);
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
