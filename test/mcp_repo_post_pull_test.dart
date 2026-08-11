import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_hub/services/mcp_repo_post_pull.dart';

void main() {
  group('McpRepoPostPull detection', () {
    test('package.json 含 build 脚本时需 npm 构建', () async {
      final dir = await Directory.systemTemp.createTemp('mcp-hub-node-');
      addTearDown(() => dir.delete(recursive: true));
      await File('${dir.path}/package.json').writeAsString(
        '{"name":"demo","scripts":{"build":"tsc"}}',
      );
      expect(await McpRepoPostPull.needsNodeRebuild(dir.path), isTrue);
      expect(await McpRepoPostPull.needsUvSync(dir.path), isFalse);
    });

    test('无 build 脚本时不需 npm 构建', () async {
      final dir = await Directory.systemTemp.createTemp('mcp-hub-node-');
      addTearDown(() => dir.delete(recursive: true));
      await File('${dir.path}/package.json').writeAsString(
        '{"name":"demo","scripts":{"start":"node index.js"}}',
      );
      expect(await McpRepoPostPull.needsNodeRebuild(dir.path), isFalse);
    });

    test('pyproject.toml 存在时需 uv sync', () async {
      final dir = await Directory.systemTemp.createTemp('mcp-hub-py-');
      addTearDown(() => dir.delete(recursive: true));
      await File('${dir.path}/pyproject.toml').writeAsString('[project]\nname="demo"\n');
      expect(await McpRepoPostPull.needsUvSync(dir.path), isTrue);
      expect(await McpRepoPostPull.needsNodeRebuild(dir.path), isFalse);
    });

    test('无配置文件时跳过构建步骤', () async {
      final dir = await Directory.systemTemp.createTemp('mcp-hub-empty-');
      addTearDown(() => dir.delete(recursive: true));
      final result = await McpRepoPostPull.apply(localPath: dir.path);
      expect(result.ok, isTrue);
      expect(result.message, isEmpty);
    });
  });
}
