/// 通知语义：成功 / 失败 / 普通提示。
enum HubNoticeKind { success, error, info }

/// 把原始长消息收成「一行标题 + 可选全文」。
class HubNotice {
  const HubNotice({required this.kind, required this.title, this.detail});

  final HubNoticeKind kind;
  final String title;
  final String? detail;

  bool get hasDetail => detail != null && detail!.trim().isNotEmpty;

  factory HubNotice.fromMessage(String message, {bool? ok}) {
    final cleaned = _cleanException(message.trim());
    if (cleaned.isEmpty) {
      final kind = ok == false ? HubNoticeKind.error : HubNoticeKind.info;
      return HubNotice(
        kind: kind,
        title: kind == HubNoticeKind.error ? 'Failed' : 'Complete',
      );
    }
    final kind = _resolveKind(cleaned, ok);
    final title = _buildTitle(cleaned, kind);
    final detail = cleaned == title ? null : cleaned;
    return HubNotice(kind: kind, title: title, detail: detail);
  }

  String get kindLabel => switch (kind) {
    HubNoticeKind.success => '成功',
    HubNoticeKind.error => '失败',
    HubNoticeKind.info => '提示',
  };
}

const _titleMaxChars = 36;

String _cleanException(String message) {
  const prefixes = ['StateError: ', 'Exception: ', 'Bad state: '];
  var text = message;
  for (final prefix in prefixes) {
    if (text.startsWith(prefix)) {
      text = text.substring(prefix.length).trim();
    }
  }
  return text;
}

HubNoticeKind _resolveKind(String message, bool? ok) {
  if (_isPartialFailure(message)) return HubNoticeKind.error;
  if (ok == false) return HubNoticeKind.error;
  if (ok == true) return HubNoticeKind.success;
  final lower = message.toLowerCase();
  if (message.contains('失败') ||
      message.contains('错误') ||
      lower.contains('fatal:') ||
      lower.contains('exception') ||
      RegExp(r'\berror\b').hasMatch(lower)) {
    return HubNoticeKind.error;
  }
  if (message.startsWith('已') ||
      message.contains('完成') ||
      message.contains('成功')) {
    return HubNoticeKind.success;
  }
  return HubNoticeKind.info;
}

bool _isPartialFailure(String message) {
  return message.contains('部分失败') ||
      (message.contains('失败') &&
          (message.contains('成功') || message.contains('已')));
}

String _buildTitle(String message, HubNoticeKind kind) {
  if (_looksLikeGitDump(message)) {
    return _gitTitle(message, kind);
  }
  final parts = message
      .split(RegExp(r'[；\n]'))
      .map(_stripPathTail)
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) {
    return kind == HubNoticeKind.error ? '失败' : '完成';
  }
  if (parts.length == 1) {
    return _ellipsis(parts.first);
  }
  final failed = parts.where(_partLooksFailed).length;
  if (failed > 0 && failed < parts.length) {
    return '部分失败（${parts.length - failed} 成功 / $failed 失败）';
  }
  if (failed == parts.length) {
    return _ellipsis('失败：${parts.first}');
  }
  return _ellipsis('${parts.first}（共 ${parts.length} 项）');
}

bool _partLooksFailed(String part) {
  final lower = part.toLowerCase();
  return part.contains('失败') ||
      lower.contains('fatal:') ||
      lower.contains('error:');
}

String _stripPathTail(String part) {
  final arrow = part.indexOf(' → ');
  if (arrow <= 0) return part;
  final after = part.substring(arrow + 3);
  if (after.contains('\\') || after.contains('/') || after.startsWith('~')) {
    return part.substring(0, arrow).trim();
  }
  return part;
}

bool _looksLikeGitDump(String message) {
  return message.contains('Already up to date') ||
      message.contains('Already up-to-date') ||
      message.contains('Fast-forward') ||
      RegExp(r'Updating [0-9a-f]+\.\.[0-9a-f]+').hasMatch(message) ||
      RegExp(r'\d+ files? changed').hasMatch(message);
}

String _gitTitle(String message, HubNoticeKind kind) {
  if (kind == HubNoticeKind.error) return '更新失败';
  if (message.contains('Already up to date') ||
      message.contains('Already up-to-date') ||
      message.contains('已是最新')) {
    return '已是最新';
  }
  return '已更新';
}

String _ellipsis(String text) {
  if (text.length <= _titleMaxChars) return text;
  return '${text.substring(0, _titleMaxChars - 1)}…';
}
