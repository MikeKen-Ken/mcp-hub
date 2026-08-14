import 'webdav_config.dart';

/// WebDAV 上固定名压缩包路径（每次覆盖，不按日期累加）。
abstract final class WebDavZipPaths {
  static const catalogZipName = 'catalog.zip';
  static const catalogEntryName = 'catalog.json';

  static String remoteRoot(WebDavConfig config) {
    final base = config.remotePath.trim().replaceAll(RegExp(r'/+$'), '');
    return base.isEmpty ? WebDavConfig.defaultRemotePath : base;
  }

  static String catalogZip(WebDavConfig config) =>
      '${remoteRoot(config)}/$catalogZipName';

  /// 旧版单文件清单，仅下载时回退读取。
  static String legacyCatalogJson(WebDavConfig config) =>
      '${remoteRoot(config)}/catalog.json';

  /// `{remotePath}/skills.zip` 等。
  static String resourceZip(WebDavConfig config, String resourceWireName) =>
      '${remoteRoot(config)}/$resourceWireName.zip';
}
