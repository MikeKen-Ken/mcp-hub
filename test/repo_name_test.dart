import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_hub/services/repo_name.dart';

void main() {
  group('RepoName.fromGitUrl', () {
    test('https github url', () {
      expect(
        RepoName.fromGitUrl('https://github.com/org/mcp-server.git'),
        'mcp-server',
      );
    });

    test('ssh github url', () {
      expect(
        RepoName.fromGitUrl('git@github.com:org/foo-bar.git'),
        'foo-bar',
      );
    });

    test('url without .git', () {
      expect(
        RepoName.fromGitUrl('https://github.com/org/kanban'),
        'kanban',
      );
    });

    test('empty', () {
      expect(RepoName.fromGitUrl(''), isNull);
      expect(RepoName.fromGitUrl(null), isNull);
    });
  });
}
