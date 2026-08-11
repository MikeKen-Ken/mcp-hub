import 'dart:convert';
import 'dart:io';

import '../common/agent_platforms.dart';
import '../models/mcp_server_entry.dart';
import 'mcp_client_config.dart';
import 'mcp_paths.dart';

/// 兼容旧名；新代码请使用 [AgentPlatformId]。
typedef McpClientKind = AgentPlatformId;

/// 客户端 MCP 配置对齐状态类别。
enum McpClientAlignStatus {
  /// 已与 Hub 启用项对齐
  aligned,

  /// 当前平台不支持读写客户端配置
  platformUnsupported,

  /// 无法解析用户配置路径
  pathUnresolved,

  /// Hub 中没有启用的 MCP
  noEnabledServers,

  /// 配置文件不存在
  fileMissing,

  /// 配置文件解析失败
  parseError,

  /// 存在缺失服务器或字段不一致等
  incomplete,
}

/// 一次客户端配置检测的结构化诊断报告。
class McpClientAlignReport {
  const McpClientAlignReport({
    required this.platform,
    required this.status,
    this.configPath,
    this.parseErrorMessage,
    this.missingServerIds = const [],
    this.fieldDiffs = const [],
    this.rmcpClientMissing = false,
  });

  final AgentPlatformId platform;

  /// 兼容旧字段名。
  AgentPlatformId get kind => platform;

  final McpClientAlignStatus status;
  final String? configPath;
  final String? parseErrorMessage;
  final List<String> missingServerIds;
  final List<McpClientFieldDiff> fieldDiffs;

  /// 仅 Codex：缺少 `rmcp_client = true`
  final bool rmcpClientMissing;

  bool get isAligned => status == McpClientAlignStatus.aligned;

  String get clientLabel => AgentPlatforms.labelOf(platform);

  /// 按钮等短标签。
  String get shortLabel => switch (status) {
        McpClientAlignStatus.aligned => '已对齐',
        McpClientAlignStatus.platformUnsupported => '平台不支持',
        McpClientAlignStatus.pathUnresolved => '路径不可用',
        McpClientAlignStatus.noEnabledServers => '无启用 MCP',
        McpClientAlignStatus.fileMissing => '配置文件不存在',
        McpClientAlignStatus.parseError => '解析失败',
        McpClientAlignStatus.incomplete => _incompleteShortLabel(),
      };

  String _incompleteShortLabel() {
    if (missingServerIds.isNotEmpty &&
        fieldDiffs.isEmpty &&
        !rmcpClientMissing) {
      return '缺少 ${missingServerIds.length} 个 MCP';
    }
    if (fieldDiffs.isNotEmpty &&
        missingServerIds.isEmpty &&
        !rmcpClientMissing) {
      return '字段不一致';
    }
    return '未对齐';
  }

  /// 具体原因（不含客户端名前缀），用于汇总与详情。
  String get reasonText {
    switch (status) {
      case McpClientAlignStatus.aligned:
        return '已对齐';
      case McpClientAlignStatus.platformUnsupported:
        return '当前平台不支持';
      case McpClientAlignStatus.pathUnresolved:
        return '无法解析配置路径';
      case McpClientAlignStatus.noEnabledServers:
        return '无启用的 MCP';
      case McpClientAlignStatus.fileMissing:
        return '配置文件不存在';
      case McpClientAlignStatus.parseError:
        final detail = parseErrorMessage;
        return detail == null || detail.isEmpty
            ? '配置解析失败'
            : '配置解析失败：$detail';
      case McpClientAlignStatus.incomplete:
        return _incompleteReasonText();
    }
  }

  String _incompleteReasonText() {
    final parts = <String>[];
    if (missingServerIds.isNotEmpty) {
      parts.add('缺少 ${missingServerIds.join('、')}');
    }
    if (fieldDiffs.isNotEmpty) {
      final seen = <String>{};
      final unique = <String>[];
      for (final diff in fieldDiffs) {
        if (seen.add(diff.label)) unique.add(diff.label);
      }
      parts.add('${unique.join('、')} 不一致');
    }
    if (rmcpClientMissing) {
      parts.add('缺少 rmcp_client');
    }
    return parts.isEmpty ? '未对齐' : parts.join('；');
  }

  /// 带客户端前缀的说明，例如 `Cursor：缺少 hubMCP`。
  String get prefixedReason => '$clientLabel：$reasonText';
}

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

/// Write enabled Hub servers into registered client global configs.
abstract final class McpClientConfigurator {
  /// 结构化诊断：说明是否对齐及具体原因。
  static Future<McpClientAlignReport> diagnoseEnabled(
    AgentPlatformId platform, {
    required List<McpServerEntry> servers,
  }) async {
    if (!McpPaths.isDesktopSupported) {
      return McpClientAlignReport(
        platform: platform,
        status: McpClientAlignStatus.platformUnsupported,
      );
    }

    final definition = AgentPlatforms.of(platform);
    final mcpConfig = definition.mcpConfig;
    if (mcpConfig == null) {
      return McpClientAlignReport(
        platform: platform,
        status: McpClientAlignStatus.platformUnsupported,
      );
    }

    final path = mcpConfig.configFilePath();
    if (path == null) {
      return McpClientAlignReport(
        platform: platform,
        status: McpClientAlignStatus.pathUnresolved,
      );
    }

    final enabled = servers.where((s) => s.enabled).toList();
    if (enabled.isEmpty) {
      return McpClientAlignReport(
        platform: platform,
        status: McpClientAlignStatus.noEnabledServers,
        configPath: path,
      );
    }

    final file = File(path);
    if (!await file.exists()) {
      return McpClientAlignReport(
        platform: platform,
        status: McpClientAlignStatus.fileMissing,
        configPath: path,
        missingServerIds: enabled.map((s) => s.id).toList(),
      );
    }

    late final String text;
    try {
      text = await file.readAsString();
    } catch (error) {
      return McpClientAlignReport(
        platform: platform,
        status: McpClientAlignStatus.parseError,
        configPath: path,
        parseErrorMessage: error.toString(),
      );
    }

    if (_usesJsonRootValidation(mcpConfig.format) && text.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is! Map) {
          return McpClientAlignReport(
            platform: platform,
            status: McpClientAlignStatus.parseError,
            configPath: path,
            parseErrorMessage: '根节点必须是对象',
          );
        }
      } on FormatException catch (error) {
        return McpClientAlignReport(
          platform: platform,
          status: McpClientAlignStatus.parseError,
          configPath: path,
          parseErrorMessage: error.message,
        );
      }
    }

    final missing = <String>[];
    final diffs = <McpClientFieldDiff>[];
    for (final server in enabled) {
      final diagnosis = _diagnoseServer(mcpConfig.format, text, server);
      if (diagnosis.missing) {
        missing.add(server.id);
      } else {
        diffs.addAll(diagnosis.diffs);
      }
    }

    final rmcpMissing = platform == AgentPlatformId.codex &&
        !McpClientConfig.hasCodexRmcpClient(text);

    if (missing.isEmpty && diffs.isEmpty && !rmcpMissing) {
      return McpClientAlignReport(
        platform: platform,
        status: McpClientAlignStatus.aligned,
        configPath: path,
      );
    }

    return McpClientAlignReport(
      platform: platform,
      status: McpClientAlignStatus.incomplete,
      configPath: path,
      missingServerIds: missing,
      fieldDiffs: diffs,
      rmcpClientMissing: rmcpMissing,
    );
  }

  /// 兼容封装：是否全部启用项已对齐。
  static Future<bool> areEnabledConfigured(
    AgentPlatformId platform, {
    required List<McpServerEntry> servers,
  }) async {
    final report = await diagnoseEnabled(platform, servers: servers);
    return report.isAligned;
  }

  static Future<McpConfigureResult> configure(
    AgentPlatformId platform, {
    required List<McpServerEntry> servers,
  }) async {
    if (!McpPaths.isDesktopSupported) {
      return const McpConfigureResult(
        ok: false,
        message: '仅桌面端支持一键配置 MCP 客户端',
      );
    }

    final definition = AgentPlatforms.of(platform);
    final mcpConfig = definition.mcpConfig;
    if (mcpConfig == null) {
      return McpConfigureResult(
        ok: false,
        message: '${definition.label} 暂不支持 MCP 配置写入',
      );
    }

    final path = mcpConfig.configFilePath();
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
      final next = _upsertConfig(
        mcpConfig.format,
        existing,
        servers: servers,
        managedIds: managedIds,
      );
      await file.writeAsString(next);
      final count = servers.where((s) => s.enabled).length;
      return McpConfigureResult(
        ok: true,
        path: path,
        message: '已写入 ${definition.label}（$count 个启用的 MCP），请重启 ${definition.label}',
      );
    } catch (error) {
      return McpConfigureResult(
        ok: false,
        path: path,
        message: '写入失败：$error',
      );
    }
  }

  static bool _usesJsonRootValidation(AgentMcpConfigFormat format) =>
      format == AgentMcpConfigFormat.cursorJson ||
      format == AgentMcpConfigFormat.openCodeJson;

  static McpServerConfigDiagnosis _diagnoseServer(
    AgentMcpConfigFormat format,
    String text,
    McpServerEntry server,
  ) =>
      switch (format) {
        AgentMcpConfigFormat.cursorJson =>
          McpClientConfig.diagnoseCursorServer(text, server: server),
        AgentMcpConfigFormat.codexToml =>
          McpClientConfig.diagnoseCodexServer(text, server: server),
        AgentMcpConfigFormat.openCodeJson =>
          McpClientConfig.diagnoseOpenCodeServer(text, server: server),
      };

  static String _upsertConfig(
    AgentMcpConfigFormat format,
    String? existing, {
    required List<McpServerEntry> servers,
    required Set<String> managedIds,
  }) =>
      switch (format) {
        AgentMcpConfigFormat.cursorJson => McpClientConfig.upsertCursorJson(
            existing,
            servers: servers,
            managedIds: managedIds,
          ),
        AgentMcpConfigFormat.codexToml => McpClientConfig.upsertCodexToml(
            existing,
            servers: servers,
            managedIds: managedIds,
          ),
        AgentMcpConfigFormat.openCodeJson => McpClientConfig.upsertOpenCodeJson(
            existing,
            servers: servers,
            managedIds: managedIds,
          ),
      };
}
