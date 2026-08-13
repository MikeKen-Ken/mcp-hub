import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_hub/widgets/hub_notice/hub_notice.dart';

void main() {
  test('短成功消息原样作为标题', () {
    final notice = HubNotice.fromMessage('已保存', ok: true);
    expect(notice.kind, HubNoticeKind.success);
    expect(notice.title, '已保存');
    expect(notice.hasDetail, isFalse);
  });

  test('失败用图标语义，并去掉 StateError 前缀', () {
    final notice = HubNotice.fromMessage(
      'StateError: git clone 失败 (code 128)',
      ok: false,
    );
    expect(notice.kind, HubNoticeKind.error);
    expect(notice.title, contains('失败'));
    expect(notice.title.startsWith('StateError'), isFalse);
  });

  test('带路径的长成功消息去掉路径并保留详情', () {
    const raw =
        '已下载 Cursor Skill 到缓存：12 个文件（约 3 个 Skill 包）'
        r' → C:\Users\demo\.mcp-hub\skills\cursor（未写入正式目录，请使用「应用到 Cursor」）';
    final notice = HubNotice.fromMessage(raw, ok: true);
    expect(notice.kind, HubNoticeKind.success);
    expect(notice.title, isNot(contains(r'C:\')));
    expect(notice.title.length, lessThanOrEqualTo(36));
    expect(notice.detail, raw);
  });

  test('git 输出收成短标题', () {
    const raw = '''
Updating abcdef0..1234567
Fast-forward
 README.md | 2 +-
 1 file changed, 1 insertion(+), 1 deletion(-)
''';
    final notice = HubNotice.fromMessage('demo: $raw', ok: true);
    expect(notice.title, '已更新');
    expect(notice.detail, contains('Fast-forward'));
  });

  test('多段结果在有失败时显示部分失败', () {
    final notice = HubNotice.fromMessage(
      'Cursor：已写入；Codex：失败（权限不足）',
      ok: false,
    );
    expect(notice.kind, HubNoticeKind.error);
    expect(notice.title, '部分失败（1 成功 / 1 失败）');
    expect(notice.hasDetail, isTrue);
  });

  test('打开目录失败即使未传 ok 也判为失败', () {
    final notice = HubNotice.fromMessage('打开目录失败：进程退出');
    expect(notice.kind, HubNoticeKind.error);
    expect(notice.title, contains('失败'));
  });
}
