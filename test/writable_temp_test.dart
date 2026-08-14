import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_hub/common/writable_temp.dart';
import 'package:mcp_hub/webdav/webdav_zip_transfer.dart';

void main() {
  setUp(WritableTemp.clearCache);

  test('Windows 候选目录包含长路径回退，且不重复', () {
    final paths = WritableTemp.candidatePaths(
      systemTempPath: r'C:\Users\KEN-NA~1\AppData\Local\Temp',
      env: const {
        'TEMP': r'C:\Users\KEN-NA~1\AppData\Local\Temp',
        'TMP': r'C:\Users\KEN-NA~1\AppData\Local\Temp',
        'LOCALAPPDATA': r'C:\Users\Ken-Narmal\AppData\Local',
        'USERPROFILE': r'C:\Users\Ken-Narmal',
      },
      isWindows: true,
    );
    expect(paths.first, r'C:\Users\KEN-NA~1\AppData\Local\Temp');
    expect(paths, contains(r'C:\Users\Ken-Narmal\AppData\Local\Temp'));
    expect(paths, contains(r'C:\Users\Ken-Narmal\.mcp_hub\tmp'));
    expect(paths.toSet().length, paths.length);
  });

  test('非 Windows 候选目录包含 /tmp 与用户目录回退', () {
    final paths = WritableTemp.candidatePaths(
      systemTempPath: '/var/folders/xx/tmp',
      env: const {'TMPDIR': '/var/folders/xx/tmp', 'HOME': '/home/ken'},
      isWindows: false,
    );
    expect(paths, contains('/tmp'));
    expect(paths, contains('/var/tmp'));
    expect(paths, contains('/home/ken/.mcp_hub/tmp'));
  });

  test('可解析并写入临时文件，且路径可再次打开', () async {
    final file = await WritableTemp.createFile('mcp_hub_dl', '.zip');
    addTearDown(() async {
      if (await file.exists()) await file.delete();
    });
    await file.writeAsBytes(const <int>[1, 2, 3], flush: true);
    final raf = await file.open(mode: FileMode.read);
    expect(await raf.length(), 3);
    await raf.close();
  });

  test('本机 PathNotFound 不算远端 404', () {
    final local = PathNotFoundException(
      r"C:\Users\KEN-NA~1\AppData\Local\Temp\mcp_hub_dl.zip",
      const OSError('系统找不到指定的文件。', 2),
      'Cannot open file',
    );
    expect(WebDavZipTransfer.isRemoteNotFound(local), isFalse);
    expect(
      WebDavZipTransfer.isRemoteNotFound(
        Exception('PathNotFoundException: Cannot open file'),
      ),
      isFalse,
    );
  });

  test('HTTP 404 算远端缺失', () {
    expect(
      WebDavZipTransfer.isRemoteNotFound(Exception('DioError [bad response]: 404')),
      isTrue,
    );
    expect(
      WebDavZipTransfer.isRemoteNotFound(Exception('404 Not Found')),
      isTrue,
    );
  });
}
