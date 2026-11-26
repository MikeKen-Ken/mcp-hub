import '../../common/app_locale.dart';

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
        title: kind == HubNoticeKind.error
            ? tr('失败', 'Failed')
            : tr('完成', 'Complete'),
      );
    }
    final kind = _resolveKind(cleaned, ok);
    final title = _buildTitle(cleaned, kind);
    final detail = cleaned == title ? null : cleaned;
    return HubNotice(kind: kind, title: title, detail: detail);
  }

  String get kindLabel => switch (kind) {
    HubNoticeKind.success => tr('成功', 'Success'),
    HubNoticeKind.error => tr('失败', 'Error'),
    HubNoticeKind.info => tr('提示', 'Notice'),
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
      lower.contains('failed') ||
      lower.contains('fatal:') ||
      lower.contains('exception') ||
      RegExp(r'\berror\b').hasMatch(lower)) {
    return HubNoticeKind.error;
  }
  if (message.startsWith('已') ||
      message.contains('完成') ||
      message.contains('成功') ||
      message.startsWith('Downloaded') ||
      message.startsWith('Applied') ||
      message.startsWith('Uploaded') ||
      message.startsWith('Updated') ||
      lower.contains('complete') ||
      lower.contains('success')) {
    return HubNoticeKind.success;
  }
  return HubNoticeKind.info;
}

bool _isPartialFailure(String message) {
  return message.contains('部分失败') ||
      message.contains('partially failed') ||
      (message.contains('失败') &&
          (message.contains('成功') || message.contains('已'))) ||
      (message.toLowerCase().contains('failed') &&
          (message.toLowerCase().contains('success') ||
              message.contains('Downloaded')));
}

String _buildTitle(String message, HubNoticeKind kind) {
  if (_looksLikeGitDump(message)) {
    return _gitTitle(message, kind);
  }
  final parts = message
      .split(RegExp(r'[；;\n]'))
      .map(_stripPathTail)
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) {
    return kind == HubNoticeKind.error
        ? tr('失败', 'Error')
        : tr('完成', 'Complete');
  }
  if (parts.length == 1) {
    return _ellipsis(parts.first);
  }
  final failed = parts.where(_partLooksFailed).length;
  if (failed > 0 && failed < parts.length) {
    return tr(
      '部分失败（${parts.length - failed} 成功 / $failed 失败）',
      'Partially failed (${parts.length - failed} succeeded / $failed failed)',
    );
  }
  if (failed == parts.length) {
    return _ellipsis(tr('失败：${parts.first}', 'Failed: ${parts.first}'));
  }
  return _ellipsis(
    tr('${parts.first}（共 ${parts.length} 项）', '${parts.first} (${parts.length} items)'),
  );
}

bool _partLooksFailed(String part) {
  final lower = part.toLowerCase();
  return part.contains('失败') ||
      lower.contains('failed') ||
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
  if (kind == HubNoticeKind.error) return tr('更新失败', 'Update failed');
  if (message.contains('Already up to date') ||
      message.contains('Already up-to-date') ||
      message.contains('已是最新')) {
    return tr('已是最新', 'Already up to date');
  }
  return tr('已更新', 'Updated');
}

String _ellipsis(String text) {
  if (text.length <= _titleMaxChars) return text;
  return '${text.substring(0, _titleMaxChars - 1)}…';
}
