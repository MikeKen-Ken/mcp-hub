/// Last completed WebDAV attempt for one package (catalog or agent resource).
class LastSyncAttempt {
  const LastSyncAttempt({
    required this.packageKey,
    required this.ok,
    required this.at,
  });

  final String packageKey;
  final bool ok;
  final DateTime at;

  Map<String, Object> toJson() => {
    'ok': ok,
    'at': at.toUtc().toIso8601String(),
  };

  static LastSyncAttempt? fromJson(String packageKey, Object? raw) {
    if (raw is! Map) return null;
    final ok = raw['ok'];
    if (ok is! bool) return null;
    final parsed = DateTime.tryParse('${raw['at']}');
    if (parsed == null) return null;
    return LastSyncAttempt(packageKey: packageKey, ok: ok, at: parsed);
  }
}

abstract final class LastSyncAttemptKeys {
  static const catalog = 'catalog';
  static const skills = 'skills';
  static const commands = 'commands';
  static const rules = 'rules';
  static const hooks = 'hooks';

  static const all = [catalog, skills, commands, rules, hooks];
}
