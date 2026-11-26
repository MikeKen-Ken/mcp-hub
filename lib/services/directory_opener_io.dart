import 'dart:io';

import '../common/app_locale.dart';

abstract final class DirectoryOpener {
  static Future<void> open(String? path) async {
    if (path == null || path.trim().isEmpty) {
      throw StateError(tr('目录路径不可用', 'Directory path is unavailable'));
    }

    final directory = Directory(path);
    await directory.create(recursive: true);

    if (Platform.isWindows) {
      await Process.start('explorer.exe', [
        directory.path,
      ], mode: ProcessStartMode.detached);
      return;
    }
    if (Platform.isMacOS) {
      await Process.start('open', [
        directory.path,
      ], mode: ProcessStartMode.detached);
      return;
    }
    if (Platform.isLinux) {
      await Process.start('xdg-open', [
        directory.path,
      ], mode: ProcessStartMode.detached);
      return;
    }

    throw UnsupportedError(
      tr('当前平台不支持打开本地目录', 'Opening local directories is not supported on this platform'),
    );
  }
}
