import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_hub/common/sync_progress.dart';
import 'package:mcp_hub/widgets/op_status/op_status.dart';

void main() {
  test('进度文案带分数，未知总数时走不确定态', () {
    const known = SyncProgress(label: '正在下载 Skill', current: 3, total: 10);
    expect(known.value, 0.3);
    expect(known.caption, '正在下载 Skill  3 / 10');

    const unknown = SyncProgress(label: '正在下载 MCP 清单');
    expect(unknown.value, isNull);
    expect(unknown.caption, '正在下载 MCP 清单');
  });

  testWidgets('失败条常驻显示短标题', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: OpStatusBar(
            errorMessage: '下载失败：远端目录不存在 → /AgentHub/skills/cursor',
          ),
        ),
      ),
    );
    expect(find.textContaining('上次失败'), findsOneWidget);
    expect(find.text('详情'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('进行中显示进度条', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: OpStatusBar(
            progress: SyncProgress(label: '正在上传 Skill', current: 2, total: 4),
          ),
        ),
      ),
    );
    expect(find.text('正在上传 Skill  2 / 4'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });
}
