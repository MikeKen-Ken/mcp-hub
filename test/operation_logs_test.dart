import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_hub/common/app_locale.dart';
import 'package:mcp_hub/controllers/hub_controller.dart';
import 'package:mcp_hub/features/operation_logs/operation_logs.dart';
import 'package:mcp_hub/features/skill_sync/skill_sync.dart';
import 'package:mcp_hub/webdav/webdav_config.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppLocale.setLanguage(AppLanguage.zh);
  });

  group('AppLocale', () {
    test('默认使用简体中文，支持切换并持久化到 SharedPreferences', () async {
      await AppLocale.load();
      expect(AppLocale.current, AppLanguage.zh);
      expect(tr('中文', 'English'), '中文');

      await AppLocale.setLanguage(AppLanguage.en);
      expect(AppLocale.current, AppLanguage.en);
      expect(tr('中文', 'English'), 'English');

      await AppLocale.load();
      expect(AppLocale.current, AppLanguage.en);

      await AppLocale.setLanguage(AppLanguage.zh);
      expect(AppLocale.current, AppLanguage.zh);
    });
  });

  group('OperationLogStore & OperationLogRecorder', () {
    test('持久化写入、读取、最大条数裁剪与清空', () async {
      final temp = await Directory.systemTemp.createTemp('op_log_store_test_');
      addTearDown(() async {
        if (await temp.exists()) await temp.delete(recursive: true);
      });
      final logPath = p.join(temp.path, 'operation_logs.json');
      final store = OperationLogStore(maxEntries: 3, filePath: logPath);
      final recorder = OperationLogRecorder(store);

      await recorder.record(
        category: OperationLogCategory.sync,
        action: '下载 Skill',
        target: 'Cursor',
        ok: true,
        message: '已下载 3 个文件',
        pulledFiles: 3,
      );
      await recorder.record(
        category: OperationLogCategory.convert,
        action: '转换文件夹资源',
        target: '全部资源',
        ok: false,
        message: 'Codex：已转换 2 条 Rule；Open Code：失败（权限不足）',
        deployedFiles: 2,
      );
      await recorder.record(
        category: OperationLogCategory.apply,
        action: '应用文件夹资源',
        target: 'Cursor',
        ok: true,
        message: '已写入 5 个文件',
        deployedFiles: 5,
      );
      await recorder.record(
        category: OperationLogCategory.backup,
        action: '导出配置备份',
        target: 'backup.zip',
        ok: true,
        message: '备份已导出',
      );

      expect(store.entries.length, 3);
      expect(store.entries.first.action, '导出配置备份');
      expect(store.entries[1].category, OperationLogCategory.apply);
      expect(store.entries[2].status, OperationLogStatus.partial);
      expect(store.entries[2].detail, contains('\n'));

      final reloaded = OperationLogStore(maxEntries: 3, filePath: logPath);
      await reloaded.load();
      expect(reloaded.entries.length, 3);
      expect(reloaded.entries.first.action, '导出配置备份');
      expect(reloaded.entries[2].status, OperationLogStatus.partial);

      await reloaded.clear();
      expect(reloaded.entries, isEmpty);

      final afterClear = OperationLogStore(maxEntries: 3, filePath: logPath);
      await afterClear.load();
      expect(afterClear.entries, isEmpty);
    });
  });

  group('HubController 操作日志记录', () {
    test('记录未配置 WebDAV 时的下载/合并/上传及转换失败或成功结果', () async {
      final logStore = OperationLogStore(persistToFile: false);
      final hub = HubController(
        initiallyLoading: false,
        operationLogStore: logStore,
      );
      addTearDown(hub.dispose);

      // 1. 尝试下载（未配置 WebDAV -> 失败记录）
      hub.webDavConfig = WebDavConfig.empty;
      final dl = await hub.syncAllResourcesFromWebDav();
      expect(dl.ok, isFalse);

      // 2. 尝试转换无对应目录的资源（Command -> Codex 失败记录）
      final cv = await hub.convertResourceFromCursor(
        AgentResourceKind.command,
        target: SkillTarget.codex,
      );
      expect(cv.ok, isFalse);

      // 3. 尝试 HubConfiguration 下载（未配置 WebDAV -> 失败记录）
      final bulk = await hub.hubConfiguration.download();
      expect(bulk.ok, isFalse);

      expect(hub.operationLogs.entries.length, 3);
      expect(
        hub.operationLogs.entries[0].category,
        OperationLogCategory.sync,
      );
      expect(hub.operationLogs.entries[0].status, OperationLogStatus.failure);
      expect(
        hub.operationLogs.entries[1].category,
        OperationLogCategory.convert,
      );
      expect(hub.operationLogs.entries[1].status, OperationLogStatus.failure);
      expect(
        hub.operationLogs.entries[2].category,
        OperationLogCategory.sync,
      );
    });

    testWidgets('OperationLogsScreen 展示分类、状态筛选与详情展开', (tester) async {
      final store = OperationLogStore(persistToFile: false);
      final recorder = OperationLogRecorder(store);
      await recorder.record(
        category: OperationLogCategory.sync,
        action: '上传 Hub 配置',
        target: 'Hub 配置',
        ok: true,
        message: '已上传 12 个文件',
        pushedFiles: 12,
        durationMs: 320,
      );
      await recorder.record(
        category: OperationLogCategory.convert,
        action: '转换文件夹资源',
        target: '全部资源',
        ok: false,
        message: 'Codex：已转换 2 个；Open Code：失败（路径无效）',
        deployedFiles: 2,
        durationMs: 145,
      );

      final hub = HubController(
        initiallyLoading: false,
        operationLogStore: store,
      );
      addTearDown(hub.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: hub,
          child: const MaterialApp(home: OperationLogsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('上传 Hub 配置'), findsOneWidget);
      expect(find.textContaining('转换文件夹资源'), findsOneWidget);
      expect(find.text('部分失败'), findsOneWidget);
      expect(find.text('成功'), findsOneWidget);

      // 按「资源转换」分类筛选
      await tester.tap(find.widgetWithText(ChoiceChip, '资源转换'));
      await tester.pumpAndSettle();
      expect(find.textContaining('转换文件夹资源'), findsOneWidget);
      expect(find.textContaining('上传 Hub 配置'), findsNothing);

      // 展开查看逐项详情
      await tester.tap(find.textContaining('转换文件夹资源'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Open Code：失败（路径无效）'), findsOneWidget);
      expect(find.text('复制详情'), findsOneWidget);
    });
  });
}
