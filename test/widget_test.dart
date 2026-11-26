import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_hub/app.dart';
import 'package:mcp_hub/app_brand.dart';
import 'package:mcp_hub/common/app_locale.dart';
import 'package:mcp_hub/common/app_theme_mode.dart';
import 'package:mcp_hub/controllers/hub_controller.dart';
import 'package:mcp_hub/webdav/webdav_config.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppLocale.setLanguage(AppLanguage.zh);
    await AppThemeMode.setPreference(AppThemePreference.system);
  });

  test('AppThemeMode 支持加载、切换与循环并持久化', () async {
    await AppThemeMode.load();
    expect(AppThemeMode.current, AppThemePreference.system);

    await AppThemeMode.cycle();
    expect(AppThemeMode.current, AppThemePreference.light);

    await AppThemeMode.cycle();
    expect(AppThemeMode.current, AppThemePreference.dark);

    await AppThemeMode.load();
    expect(AppThemeMode.current, AppThemePreference.dark);

    await AppThemeMode.cycle();
    expect(AppThemeMode.current, AppThemePreference.system);
  });

  testWidgets('Esc 先关闭弹窗再返回子页面，根工作台保持打开', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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

    await tester.tap(find.text('MCP 服务').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加 MCP'));
    await tester.pumpAndSettle();
    expect(find.text('添加 MCP'), findsWidgets);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('客户端配置对齐'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('客户端配置对齐'), findsOneWidget);
  });

  testWidgets('桌面工作台侧边栏切换、三步同步流、一体化 MCP 页与设置中心', (tester) async {
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
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1280, 1400));

    await tester.pumpWidget(
      ChangeNotifierProvider.value(value: hub, child: const McpHubApp()),
    );
    await tester.pump();

    // 1. 验证侧边栏品牌与 4 个一级导航
    expect(find.text(AppBrand.displayName), findsOneWidget);
    expect(find.text('同步中心'), findsWidgets);
    expect(find.text('MCP 服务'), findsWidgets);
    expect(find.text('操作日志'), findsWidgets);
    expect(find.text('设置与备份'), findsWidgets);

    // 2. 验证三步同步流与资源卡片
    expect(find.text('三步批量同步流程'), findsOneWidget);
    expect(find.text('应用文件夹资源'), findsOneWidget);
    expect(find.text('转换文件夹资源'), findsOneWidget);
    expect(find.text('MCP 清单'), findsOneWidget);
    expect(find.text('Skill'), findsOneWidget);
    expect(find.text('Command'), findsOneWidget);
    expect(find.text('Rule'), findsOneWidget);
    expect(find.text('Hook'), findsOneWidget);
    expect(find.text('管理 MCP 服务'), findsOneWidget);

    // 3. 验证三步流主要确认弹窗
    await tester.tap(find.text('应用文件夹资源'));
    await tester.pumpAndSettle();
    expect(find.text('确认应用文件夹资源？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('上传 Hub 配置'));
    await tester.pumpAndSettle();
    expect(find.text('确认覆盖远端压缩包？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('合并 Hub 配置'));
    await tester.pumpAndSettle();
    expect(find.text('确认合并 Hub 配置？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    // 4. 切换到「MCP 服务」一级视图：客户端对齐与本地列表同页直达
    await tester.tap(find.text('MCP 服务').first);
    await tester.pumpAndSettle();
    expect(find.text('客户端配置对齐'), findsOneWidget);
    expect(find.text('添加 MCP'), findsOneWidget);

    // 5. 切换到「操作日志」一级视图
    await tester.tap(find.text('操作日志').first);
    await tester.pumpAndSettle();
    expect(find.text('全部类型'), findsOneWidget);

    // 6. 切换到「设置与备份」一级视图并切三个子标签
    await tester.tap(find.text('设置与备份').first);
    await tester.pumpAndSettle();
    expect(find.text('外观主题'), findsOneWidget);
    expect(find.text('界面语言'), findsOneWidget);

    await tester.tap(find.text('WebDAV 同步'));
    await tester.pumpAndSettle();
    expect(find.text('启用 WebDAV 下载/上传'), findsOneWidget);

    await tester.tap(find.text('配置备份'));
    await tester.pumpAndSettle();
    expect(find.text('导出 / 导入'), findsOneWidget);

    // 7. 切回同步中心并缩窄窗口验证紧凑侧边栏无溢出
    await tester.tap(find.text('同步中心').first);
    await tester.pumpAndSettle();
    await tester.binding.setSurfaceSize(const Size(640, 800));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 8. 验证字体家族与标题/正文层级
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    final theme = app.theme!;
    expect(theme.textTheme.titleLarge?.fontFamily, 'Noto Sans SC');
    expect(theme.textTheme.titleLarge?.fontWeight, FontWeight.w600);
    expect(theme.textTheme.bodyMedium?.fontWeight, FontWeight.w400);
    expect(app.darkTheme?.brightness, Brightness.dark);
  });
}
