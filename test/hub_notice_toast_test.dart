import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_hub/widgets/hub_notice/hub_notice.dart';

void main() {
  testWidgets('长消息只显示短标题，详情里能看到全文', (tester) async {
    const raw =
        '已下载 Cursor Skill 到缓存：12 个文件（约 3 个 Skill 包）'
        r' → C:\Users\demo\.mcp-hub\skills\cursor（未写入正式目录，请使用「应用到 Cursor」）';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () => showHubNotice(context, message: raw, ok: true),
                child: const Text('触发'),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('触发'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(raw), findsNothing);
    expect(find.text('详情'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    await tester.tap(find.text('详情'));
    await tester.pumpAndSettle();
    expect(find.text(raw), findsOneWidget);
  });

  testWidgets('失败通知使用错误图标且可关闭', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () => showHubNotice(
                  context,
                  message: 'git pull 失败：fatal: not a git repository',
                  ok: false,
                ),
                child: const Text('触发'),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('触发'));
    await tester.pump();
    expect(find.byIcon(Icons.error), findsOneWidget);
    expect(find.textContaining('失败'), findsWidgets);
  });
}
