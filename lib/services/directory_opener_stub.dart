abstract final class DirectoryOpener {
  static Future<void> open(String? path) async {
    throw UnsupportedError('当前平台不支持打开本地目录');
  }
}
