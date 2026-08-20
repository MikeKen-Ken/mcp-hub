import 'dart:io';

import 'package:path/path.dart' as p;

import '../../services/mcp_paths.dart';
import 'skill_folder_copy.dart';

/// Cursor 用户级 Hook：`hooks.json` + `hooks/` 目录成对管理。
class CursorHooksLayout {
  const CursorHooksLayout({
    required this.configDirectory,
    this.hooksJsonName = 'hooks.json',
    this.hooksDirectoryName = 'hooks',
  });

  final String configDirectory;
  final String hooksJsonName;
  final String hooksDirectoryName;

  String get hooksJsonPath => p.join(configDirectory, hooksJsonName);

  String get hooksDirectoryPath => p.join(configDirectory, hooksDirectoryName);

  static CursorHooksLayout? cursorUser() {
    final dir = McpPaths.cursorConfigDirectory;
    if (dir == null) return null;
    return CursorHooksLayout(configDirectory: dir);
  }

  static CursorHooksLayout? codexUser() {
    final dir = McpPaths.codexConfigDirectory;
    if (dir == null) return null;
    return CursorHooksLayout(configDirectory: dir);
  }
}

/// 把 Cursor 的 `hooks.json` 与 `hooks/` 打成/解开 WebDAV 包（不碰 `.cursor` 其它文件）。
class CursorHooksBundle {
  const CursorHooksBundle({this.folderCopy = const SkillFolderCopy()});

  final SkillFolderCopy folderCopy;

  static const jsonFileName = 'hooks.json';
  static const scriptsDirName = 'hooks';

  /// 从 Cursor 正式位置导出到 [bundleDir]（`hooks.json` + `hooks/`）。
  Future<SkillFolderCopyResult> exportFromLayout({
    required CursorHooksLayout layout,
    required String bundleDir,
  }) async {
    final bundle = Directory(bundleDir);
    if (await bundle.exists()) {
      await bundle.delete(recursive: true);
    }
    await bundle.create(recursive: true);

    var files = 0;
    var dirs = 0;
    final srcJson = File(layout.hooksJsonPath);
    if (await srcJson.exists()) {
      await srcJson.copy(p.join(bundle.path, jsonFileName));
      files += 1;
    }

    final srcHooks = Directory(layout.hooksDirectoryPath);
    if (await srcHooks.exists()) {
      final copied = await folderCopy.copyContents(
        sourceDir: srcHooks.path,
        targetDir: p.join(bundle.path, scriptsDirName),
      );
      files += copied.copiedFiles;
      dirs += copied.copiedDirs + 1;
    } else {
      await Directory(p.join(bundle.path, scriptsDirName)).create();
    }

    return SkillFolderCopyResult(
      copiedFiles: files,
      copiedDirs: dirs,
      sourcePath: layout.configDirectory,
      targetPath: bundle.path,
    );
  }

  /// 用包内容覆盖 Cursor 正式 `hooks.json` 与 `hooks/`（不删除其它配置）。
  Future<SkillFolderCopyResult> applyToLayout({
    required String bundleDir,
    required CursorHooksLayout layout,
  }) async {
    final bundle = Directory(bundleDir);
    if (!await bundle.exists()) {
      await bundle.create(recursive: true);
    }

    var files = 0;
    var deleted = 0;
    final srcJson = File(p.join(bundle.path, jsonFileName));
    final destJson = File(layout.hooksJsonPath);
    if (await srcJson.exists()) {
      await destJson.parent.create(recursive: true);
      await srcJson.copy(destJson.path);
      files += 1;
    } else if (await destJson.exists()) {
      await destJson.delete();
      deleted += 1;
    }

    final srcHooks = Directory(p.join(bundle.path, scriptsDirName));
    if (!await srcHooks.exists()) {
      await srcHooks.create(recursive: true);
    }
    final mirrored = await folderCopy.mirrorContents(
      sourceDir: srcHooks.path,
      targetDir: layout.hooksDirectoryPath,
    );
    files += mirrored.copiedFiles;
    deleted += mirrored.deletedEntries;

    return SkillFolderCopyResult(
      copiedFiles: files,
      copiedDirs: mirrored.copiedDirs,
      sourcePath: bundle.path,
      targetPath: layout.configDirectory,
      deletedEntries: deleted,
    );
  }

  Future<int> countBundleFiles(String bundleDir) async {
    final dir = Directory(bundleDir);
    if (!await dir.exists()) return 0;
    var count = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      if (p.basename(entity.path).startsWith('.')) continue;
      count += 1;
    }
    return count;
  }
}
