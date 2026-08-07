import 'dart:io';

import '../models/mcp_server_entry.dart';
import 'mcp_client_config.dart';
import 'mcp_paths.dart';

enum McpClientKind { cursor, codex }

class McpConfigureResult {
  const McpConfigureResult({
    required this.ok,
    required this.message,
    this.path,
  });

  final bool ok;
  final String message;
  final String? path;
}

/// Write enabled Hub servers into Cursor / Codex global config.
/// Pattern mirrored from kanban's McpClientConfigurator.
abstract final class McpClientConfigurator {
  static Future<bool> areEnabledConfigured(
    McpClientKind kind, {
    required List<McpServerEntry> servers,
  }) async {
    if (!McpPaths.isDesktopSupported) return false;
    final enabled = servers.where((s) => s.enabled).toList();
    if (enabled.isEmpty) return false;
    final path = _pathFor(kind);
    if (path == null) return false;
    final file = File(path);
    if (!await file.exists()) return false;
    final text = await file.readAsString();
    return switch (kind) {
      McpClientKind.cursor => enabled.every(
          (s) => McpClientConfig.isCursorServerConfigured(text, server: s),
        ),
      McpClientKind.codex => enabled.every(
          (s) => McpClientConfig.isCodexServerConfigured(text, server: s),
        ),
    };
  }

  static Future<McpConfigureResult> configure(
    McpClientKind kind, {
    required List<McpServerEntry> servers,
  }) async {
    if (!McpPaths.isDesktopSupported) {
      return const McpConfigureResult(
        ok: false,
        message: '仅桌面端支持一键配置 MCP 客户端',
      );
    }

    final path = _pathFor(kind);
    if (path == null) {
      return const McpConfigureResult(
        ok: false,
        message: '无法解析用户配置路径',
      );
    }

    try {
      final file = File(path);
      await file.parent.create(recursive: true);
      final existing = await file.exists() ? await file.readAsString() : null;
      final managedIds = servers.map((s) => s.id).toSet();
      final next = switch (kind) {
        McpClientKind.cursor => McpClientConfig.upsertCursorJson(
            existing,
            servers: servers,
            managedIds: managedIds,
          ),
        McpClientKind.codex => McpClientConfig.upsertCodexToml(
            existing,
            servers: servers,
            managedIds: managedIds,
          ),
      };
      await file.writeAsString(next);
      final label = kind == McpClientKind.cursor ? 'Cursor' : 'Codex';
      final count = servers.where((s) => s.enabled).length;
      return McpConfigureResult(
        ok: true,
        path: path,
        message: '已写入 $label（$count 个启用的 MCP），请重启 $label',
      );
    } catch (error) {
      return McpConfigureResult(
        ok: false,
        path: path,
        message: '写入失败：$error',
      );
    }
  }

  static String? _pathFor(McpClientKind kind) => switch (kind) {
        McpClientKind.cursor => McpPaths.cursorMcpJsonPath,
        McpClientKind.codex => McpPaths.codexConfigTomlPath,
      };
}
