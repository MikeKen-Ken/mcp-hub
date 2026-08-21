import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// 解析本机可写临时目录，并保证随后创建的文件能真正打开。
///
/// Windows 上 `Directory.systemTemp` 常给出 `KEN-NA~1` 这类 8.3 短路径；
/// 短名被禁用或 `TEMP` 失效时，直接打开会变成 `PathNotFoundException`。
class WritableTemp {
  WritableTemp._();

  static Directory? _cached;

  @visibleForTesting
  static void clearCache() {
    _cached = null;
  }

  static Future<Directory> resolveDir() async {
    final cached = _cached;
    if (cached != null && await canUse(cached)) return cached;
    final dir = await _pickDir();
    _cached = dir;
    return dir;
  }

  static Future<File> createFile(String prefix, String extension) async {
    final ext = extension.startsWith('.') ? extension : '.$extension';
    final dir = await resolveDir();
    final file = File(
      p.join(dir.path, '${prefix}_${DateTime.now().microsecondsSinceEpoch}$ext'),
    );
    await file.writeAsBytes(const <int>[], flush: true);
    await _assertOpenable(file, FileMode.append);
    return file;
  }

  static Future<Directory> createDir(String prefix) async {
    final parent = await resolveDir();
    final dir = Directory(
      p.join(
        parent.path,
        '${prefix}_${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    await dir.create(recursive: true);
    return dir;
  }

  @visibleForTesting
  static List<String> candidatePaths({
    required String systemTempPath,
    required Map<String, String> env,
    required bool isWindows,
  }) {
    final ctx = isWindows ? p.windows : p.posix;
    final out = <String>[];
    void add(String? raw) {
      final value = raw?.trim() ?? '';
      if (value.isEmpty) return;
      if (!out.contains(value)) out.add(value);
    }

    add(systemTempPath);
    add(env['TMPDIR']);
    add(env['TEMP']);
    add(env['TMP']);
    if (isWindows) {
      final localAppData = env['LOCALAPPDATA']?.trim();
      if (localAppData != null && localAppData.isNotEmpty) {
        add(ctx.join(localAppData, 'Temp'));
      }
      final userProfile = env['USERPROFILE']?.trim();
      if (userProfile != null && userProfile.isNotEmpty) {
        add(ctx.join(userProfile, 'AppData', 'Local', 'Temp'));
      }
    } else {
      add('/tmp');
      add('/var/tmp');
    }
    final home = (env['USERPROFILE'] ?? env['HOME'])?.trim();
    if (home != null && home.isNotEmpty) {
      add(ctx.join(home, '.mcp_hub', 'tmp'));
    }
    return out;
  }

  @visibleForTesting
  static Future<bool> canUse(Directory dir) async {
    File? probe;
    try {
      await dir.create(recursive: true);
      probe = File(
        p.join(
          dir.path,
          '.mcp_hub_wprobe_${DateTime.now().microsecondsSinceEpoch}',
        ),
      );
      await probe.writeAsBytes(const <int>[0x6d], flush: true);
      await _assertOpenable(probe, FileMode.read);
      return await probe.length() == 1;
    } catch (_) {
      return false;
    } finally {
      try {
        if (probe != null && await probe.exists()) await probe.delete();
      } catch (_) {}
    }
  }

  static Future<Directory> _pickDir() async {
    final tried = <String>[];
    for (final raw in candidatePaths(
      systemTempPath: Directory.systemTemp.path,
      env: Platform.environment,
      isWindows: Platform.isWindows,
    )) {
      tried.add(raw);
      final resolved = await _canonicalizeIfUsable(raw);
      if (resolved != null) return resolved;
    }
    throw StateError('No writable temporary directory found (tried: ${tried.join('; ')})');
  }

  static Future<Directory?> _canonicalizeIfUsable(String raw) async {
    final dir = Directory(raw);
    if (!await dir.exists()) {
      try {
        await dir.create(recursive: true);
      } catch (_) {
        return null;
      }
    }
    String path;
    try {
      path = await dir.resolveSymbolicLinks();
    } catch (_) {
      path = dir.absolute.path;
    }
    final resolved = Directory(path);
    if (!await canUse(resolved)) return null;
    return resolved;
  }

  static Future<void> _assertOpenable(File file, FileMode mode) async {
    final raf = await file.open(mode: mode);
    await raf.close();
  }
}
