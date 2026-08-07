/// Derive a display / folder name from a git remote URL.
abstract final class RepoName {
  /// `https://github.com/org/foo-bar.git` → `foo-bar`
  /// `git@github.com:org/foo-bar.git` → `foo-bar`
  static String? fromGitUrl(String? raw) {
    if (raw == null) return null;
    var url = raw.trim();
    if (url.isEmpty) return null;

    // git@host:path/repo.git
    final scp = RegExp(r'^git@[^:]+:(.+)$').firstMatch(url);
    if (scp != null) {
      url = scp.group(1)!;
    } else {
      // strip scheme + host for https://...
      final uri = Uri.tryParse(url);
      if (uri != null && uri.path.isNotEmpty) {
        url = uri.path;
      }
    }

    url = url.replaceAll(RegExp(r'\\'), '/');
    url = url.replaceFirst(RegExp(r'^/+'), '');
    url = url.replaceFirst(RegExp(r'/$'), '');
    url = url.replaceFirst(RegExp(r'\.git$', caseSensitive: false), '');
    if (url.isEmpty) return null;

    final segments = url.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return null;
    return segments.last;
  }

  static String slug(String name) {
    final cleaned = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return cleaned;
  }
}
