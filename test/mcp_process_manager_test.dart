import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_hub/models/mcp_server_entry.dart';
import 'package:mcp_hub/models/mcp_transport.dart';
import 'package:mcp_hub/services/mcp_process_manager.dart';
import 'package:mcp_hub/services/mcp_repo_service.dart';
import 'package:path/path.dart' as p;

void main() {
  test('失效 cwd 时回退到存在的本地目录', () async {
    final directory = await Directory.systemTemp.createTemp('mcp-hub-test-');
    addTearDown(() => directory.delete(recursive: true));
    final server = McpServerEntry(
      id: 'everything',
      name: 'Everything',
      transport: McpTransport.stdio,
      command: 'npx',
      cwd: '${directory.path}-missing',
      localPath: directory.path,
    );

    expect(
      await McpProcessManager().resolveWorkingDirectory(server),
      directory.path,
    );
  });

  test('cwd 与本地目录均不存在时不传工作目录', () async {
    const server = McpServerEntry(
      id: 'missing',
      name: 'Missing',
      transport: McpTransport.stdio,
      command: 'npx',
      cwd: 'Z:/not-a-real-mcp-directory',
      localPath: 'Z:/not-a-real-local-directory',
    );

    expect(await McpProcessManager().resolveWorkingDirectory(server), isNull);
  });

  test('deleteDirectoryResilient 能删除包含只读文件的目录', () async {
    final directory = await Directory.systemTemp.createTemp('mcp-hub-ro-');
    final nested = File(p.join(directory.path, '.git', 'objects', 'pack.idx'));
    await nested.parent.create(recursive: true);
    await nested.writeAsString('readonly-content');
    if (Platform.isWindows) {
      await Process.run('attrib', ['+R', nested.path]);
    }

    await McpRepoService.deleteDirectoryResilient(directory);
    expect(await directory.exists(), isFalse);
  });
}
