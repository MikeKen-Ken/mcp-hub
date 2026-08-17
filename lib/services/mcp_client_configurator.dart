import 'dart:convert';
import 'dart:io';

import '../common/agent_platforms.dart';
import '../models/mcp_server_entry.dart';
import '../services/hub_mcp_constants.dart';
import 'mcp_client_config.dart';
import 'mcp_client_config_reader.dart';
import 'mcp_paths.dart';

/// 兼容旧名；新代码请使用 [AgentPlatformId]。
typedef McpClientKind = AgentPlatformId;

/// 客户端 MCP 配置对齐状态类别。
enum McpClientAlignStatus {
  /// 已与 Hub 全部 MCP 对齐
  aligned,

  /// 当前平台不支持读写客户端配置
  platformUnsupported,

  /// 无法解析用户配置路径
  pathUnresolved,

  /// Hub 中没有 MCP
  noServers,

  /// @deprecated 使用 [noServers]。
  @Deprecated('使用 noServers')
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
    this.extraServerIds = const [],
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

  /// 客户端配置中有、Hub 目录未登记的 MCP id。
  final List<String> extraServerIds;

  bool get isAligned => status == McpClientAlignStatus.aligned;

  String get clientLabel => AgentPlatforms.labelOf(platform);

  /// 按钮等短标签。
  String get shortLabel => switch (status) {
        McpClientAlignStatus.aligned => '已对齐',
        McpClientAlignStatus.platformUnsupported => '平台不支持',
        McpClientAlignStatus.pathUnresolved => '路径不可用',
        McpClientAlignStatus.noServers => '无 MCP',
        McpClientAlignStatus.noEnabledServers => '无 MCP',
        McpClientAlignStatus.fileMissing => '配置文件不存在',
        McpClientAlignStatus.parseError => '解析失败',
        McpClientAlignStatus.incomplete => _incompleteShortLabel(),
      };

  String _incompleteShortLabel() {
    if (missingServerIds.isNotEmpty &&
        fieldDiffs.isEmpty &&
        !rmcpClientMissing &&
        extraServerIds.isEmpty) {
      return '缺少 ${missingServerIds.length} 个 MCP';
    }
    if (extraServerIds.isNotEmpty &&
        missingServerIds.isEmpty &&
        fieldDiffs.isEmpty &&
        !rmcpClientMissing) {
      return '未登记 ${extraServerIds.length} 个';
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
      case McpClientAlignStatus.noServers:
        return '无 MCP';
      case McpClientAlignStatus.noEnabledServers:
        return '无 MCP';
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
    if (extraServerIds.isNotEmpty) {
      parts.add('未登记 ${extraServerIds.join('、')}');
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

/// 从客户端配置导入 Hub 未登记 MCP 的结果。
class McpClientImportResult {
  const McpClientImportResult({
    required this.ok,
    required this.message,
    this.imported = const [],
    this.skippedIds = const [],
    this.extraByPlatform = const {},
  });

  final bool ok;
  final String message;

  /// 已解析并拟加入 Hub 的条目（调用方写入目录）。
  final List<McpServerEntry> imported;

  /// Hub 中已存在而跳过的 id。
  final List<String> skippedIds;

  /// 各客户端配置里存在、Hub 未登记的 id（用于诊断展示）。
  final Map<AgentPlatformId, List<String>> extraByPlatform;

  int get importedCount => imported.length;

  McpClientImportResult copyWith({String? message}) {
    return McpClientImportResult(
      ok: ok,
      message: message ?? this.message,
      imported: imported,
      skippedIds: skippedIds,
      extraByPlatform: extraByPlatform,
    );
  }
}

/// Write all Hub servers into registered client global configs.
abstract final class McpClientConfigurator {
  /// 结构化诊断：检查 Hub 中全部 MCP 是否已转换并对齐。
  static Future<McpClientAlignReport> diagnoseAll(
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

    if (servers.isEmpty) {
      return McpClientAlignReport(
        platform: platform,
        status: McpClientAlignStatus.noServers,
        configPath: path,
        extraServerIds: await _extraServerIds(platform, hubIds: const {}),
      );
    }

    final file = File(path);
    if (!await file.exists()) {
      return McpClientAlignReport(
        platform: platform,
        status: McpClientAlignStatus.fileMissing,
        configPath: path,
        missingServerIds: servers.map((s) => s.id).toList(),
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
    for (final server in servers) {
      final diagnosis = _diagnoseServer(mcpConfig.format, text, server);
      if (diagnosis.missing) {
        missing.add(server.id);
      } else {
        diffs.addAll(diagnosis.diffs);
      }
    }

    final rmcpMissing = platform == AgentPlatformId.codex &&
        !McpClientConfig.hasCodexRmcpClient(text);

    final hubIds = servers.map((s) => s.id).toSet();
    final extraServerIds = await _extraServerIds(platform, hubIds: hubIds);

    if (missing.isEmpty && diffs.isEmpty && !rmcpMissing) {
      if (extraServerIds.isEmpty) {
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
        extraServerIds: extraServerIds,
      );
    }

    return McpClientAlignReport(
      platform: platform,
      status: McpClientAlignStatus.incomplete,
      configPath: path,
      missingServerIds: missing,
      fieldDiffs: diffs,
      rmcpClientMissing: rmcpMissing,
      extraServerIds: extraServerIds,
    );
  }

  /// 读取某客户端配置文件中的全部 MCP 条目。
  static Future<List<McpServerEntry>> readServersFromClient(
    AgentPlatformId platform,
  ) async {
    final text = await _readClientConfigText(platform);
    if (text == null) return const [];
    final definition = AgentPlatforms.of(platform);
    final mcpConfig = definition.mcpConfig;
    if (mcpConfig == null) return const [];
    return _parseClientServers(mcpConfig.format, text);
  }

  /// 从已登记客户端导入 Hub 中不存在的 MCP（不覆盖已有 id）。
  static Future<McpClientImportResult> importMissingServers({
    required List<McpServerEntry> hubServers,
    List<AgentPlatformId>? sources,
  }) async {
    if (!McpPaths.isDesktopSupported) {
      return const McpClientImportResult(
        ok: false,
        message: '仅桌面端支持从客户端导入',
      );
    }

    final hubIds = hubServers.map((s) => s.id).toSet();
    final platformSources = sources ?? AgentPlatforms.mcpConfigurable.map((p) => p.id).toList();
    final extraByPlatform = <AgentPlatformId, List<String>>{};
    final toImport = <McpServerEntry>[];
    final skipped = <String>[];
    final seenImportIds = <String>{};

    for (final platform in platformSources) {
      final parsed = await readServersFromClient(platform);
      final extras = <String>[];
      for (final server in parsed) {
        if (server.id == HubMcpConstants.serverKey || server.builtIn) continue;
        if (hubIds.contains(server.id)) {
          if (!skipped.contains(server.id)) skipped.add(server.id);
          continue;
        }
        extras.add(server.id);
        if (seenImportIds.add(server.id)) {
          toImport.add(
            server.copyWith(
              notes: server.notes ?? '从 ${AgentPlatforms.labelOf(platform)} 导入',
            ),
          );
        }
      }
      if (extras.isNotEmpty) {
        extraByPlatform[platform] = extras;
      }
    }

    if (toImport.isEmpty) {
      return McpClientImportResult(
        ok: true,
        message: '没有需要从客户端导入的新 MCP',
        skippedIds: skipped,
        extraByPlatform: extraByPlatform,
      );
    }

    final labels = extraByPlatform.entries
        .where((e) => e.value.isNotEmpty)
        .map((e) => '${AgentPlatforms.labelOf(e.key)} ${e.value.length} 个')
        .join('、');
    return McpClientImportResult(
      ok: true,
      message: '可从客户端导入 ${toImport.length} 个 MCP（$labels）',
      imported: toImport,
      skippedIds: skipped,
      extraByPlatform: extraByPlatform,
    );
  }

  static Future<String?> _readClientConfigText(AgentPlatformId platform) async {
    final definition = AgentPlatforms.of(platform);
    final mcpConfig = definition.mcpConfig;
    if (mcpConfig == null) return null;
    final path = mcpConfig.configFilePath();
    if (path == null) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    try {
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  static Future<List<String>> _extraServerIds(
    AgentPlatformId platform, {
    required Set<String> hubIds,
  }) async {
    final parsed = await readServersFromClient(platform);
    return [
      for (final s in parsed)
        if (!hubIds.contains(s.id) &&
            s.id != HubMcpConstants.serverKey &&
            !s.builtIn)
          s.id,
    ];
  }

  static List<McpServerEntry> _parseClientServers(
    AgentMcpConfigFormat format,
    String text,
  ) =>
      switch (format) {
        AgentMcpConfigFormat.cursorJson =>
          McpClientConfigReader.parseCursorServers(text),
        AgentMcpConfigFormat.codexToml =>
          McpClientConfigReader.parseCodexServers(text),
        AgentMcpConfigFormat.openCodeJson =>
          McpClientConfigReader.parseOpenCodeServers(text),
      };

  /// 兼容旧 API；现在检查全部 MCP，而不是仅检查启用项。
  @Deprecated('使用 diagnoseAll')
  static Future<McpClientAlignReport> diagnoseEnabled(
    AgentPlatformId platform, {
    required List<McpServerEntry> servers,
  }) =>
      diagnoseAll(platform, servers: servers);

  /// 兼容封装：是否全部 MCP 已对齐。
  static Future<bool> areEnabledConfigured(
    AgentPlatformId platform, {
    required List<McpServerEntry> servers,
  }) async {
    final report = await diagnoseAll(platform, servers: servers);
    return report.isAligned;
  }

  static Future<McpConfigureResult> configure(
    AgentPlatformId platform, {
    required List<McpServerEntry> servers,
    Set<String> removeIds = const {},
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
        removeIds: removeIds,
      );
      await file.writeAsString(next);
      final enabledCount = servers.where((s) => s.enabled).length;
      return McpConfigureResult(
        ok: true,
        path: path,
        message:
            '已同步 ${definition.label}（启用 $enabledCount / 共 ${servers.length}），请重载 MCP 或重启 ${definition.label}',
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
          McpClientConfig.diagnoseOpenCodeServer(
            text,
            server: server,
            environment: Platform.environment,
          ),
      };

  static String _upsertConfig(
    AgentMcpConfigFormat format,
    String? existing, {
    required List<McpServerEntry> servers,
    required Set<String> managedIds,
    Set<String> removeIds = const {},
  }) =>
      switch (format) {
        AgentMcpConfigFormat.cursorJson => McpClientConfig.upsertCursorJson(
            existing,
            servers: servers,
            managedIds: managedIds,
            removeIds: removeIds,
          ),
        AgentMcpConfigFormat.codexToml => McpClientConfig.upsertCodexToml(
            existing,
            servers: servers,
            managedIds: managedIds,
            removeIds: removeIds,
          ),
        AgentMcpConfigFormat.openCodeJson => McpClientConfig.upsertOpenCodeJson(
            existing,
            servers: servers,
            managedIds: managedIds,
            removeIds: removeIds,
            environment: Platform.environment,
          ),
      };
}
