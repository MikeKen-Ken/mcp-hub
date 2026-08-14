import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_hub/webdav/catalog_sync_document.dart';
import 'package:mcp_hub/webdav/catalog_zip_codec.dart';
import 'package:mcp_hub/webdav/webdav_config.dart';
import 'package:mcp_hub/webdav/webdav_zip_paths.dart';
import 'package:mcp_hub/webdav/zip_directory_codec.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mcp_hub_zip_codec_');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('远端压缩包使用固定名', () {
    const config = WebDavConfig(
      enabled: true,
      serverUrl: 'https://dav.example.com/',
      username: 'u',
      password: 'p',
      remotePath: '/AgentHub',
      autoSync: false,
      autoPull: false,
      pollIntervalSeconds: WebDavConfig.defaultPollIntervalSeconds,
      pushDebounceSeconds: WebDavConfig.defaultPushDebounceSeconds,
    );
    expect(WebDavZipPaths.catalogZip(config), '/AgentHub/catalog.zip');
    expect(WebDavZipPaths.resourceZip(config, 'skills'), '/AgentHub/skills.zip');
    expect(
      WebDavZipPaths.resourceZip(config, 'commands'),
      '/AgentHub/commands.zip',
    );
    expect(WebDavZipPaths.resourceZip(config, 'rules'), '/AgentHub/rules.zip');
  });

  test('目录打包再解压可还原文件，并跳过点开头条目', () async {
    final source = Directory(p.join(temp.path, 'src'));
    await File(p.join(source.path, 'a.txt')).create(recursive: true);
    await File(p.join(source.path, 'a.txt')).writeAsString('hello');
    await File(p.join(source.path, 'nested', 'b.txt')).create(recursive: true);
    await File(p.join(source.path, 'nested', 'b.txt')).writeAsString('world');
    await File(p.join(source.path, '.secret')).create(recursive: true);
    await File(p.join(source.path, '.secret')).writeAsString('no');

    final zipPath = p.join(temp.path, 'pack.zip');
    const codec = ZipDirectoryCodec();
    await codec.packDirectory(sourceDir: source.path, zipPath: zipPath);

    final dest = Directory(p.join(temp.path, 'dest'));
    final count = await codec.extractTo(
      zipPath: zipPath,
      targetDir: dest.path,
      wipeTarget: true,
    );
    expect(count, 2);
    expect(await File(p.join(dest.path, 'a.txt')).readAsString(), 'hello');
    expect(
      await File(p.join(dest.path, 'nested', 'b.txt')).readAsString(),
      'world',
    );
    expect(File(p.join(dest.path, '.secret')).existsSync(), isFalse);
  });

  test('catalog.zip 可往返清单文档', () async {
    const doc = CatalogSyncDocument(
      servers: [
        SyncableServer(
          id: 'demo',
          name: 'Demo',
          transport: 'stdio',
          updatedAt: 42,
          command: 'npx',
        ),
      ],
      updatedAt: 42,
      tombstones: {'gone': 1},
    );
    final zipPath = p.join(temp.path, 'catalog.zip');
    final codec = CatalogZipCodec();
    await codec.writeDocument(doc: doc, zipPath: zipPath);
    final restored = await codec.readDocument(zipPath);
    expect(restored.updatedAt, 42);
    expect(restored.servers.single.id, 'demo');
    expect(restored.tombstones['gone'], 1);
  });
}
