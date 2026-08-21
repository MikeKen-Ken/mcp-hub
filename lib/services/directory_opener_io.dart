import 'dart:io';

abstract final class DirectoryOpener {
  static Future<void> open(String? path) async {
    if (path == null || path.trim().isEmpty) {
      throw StateError('Directory path is unavailable');
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
      'Opening local directories is not supported on this platform',
    );
  }
}
