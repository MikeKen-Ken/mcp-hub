import 'package:mcp_dart/mcp_dart.dart';

import '../common/agent_platforms.dart';
import '../controllers/hub_controller.dart';
import '../features/skill_sync/skill_sync.dart';
import '../models/mcp_transport.dart';
import '../models/mcp_server_runtime_info.dart';
import 'hub_mcp_constants.dart';
import 'hub_mcp_results.dart';
import 'mcp_client_configurator.dart';
import 'mcp_server_runtime_resolver.dart';

/// Register tools so Cursor/Codex can operate Agent Hub itself.
void registerHubMcpTools(McpServer server, HubController hub) {
  server.registerTool(
    'list_servers',
    description: '列出 Hub 管理的全部 MCP（含内置 hubMCP）',
    inputSchema: JsonSchema.object(properties: const {}),
    annotations:
        const ToolAnnotations(readOnlyHint: true, openWorldHint: false),
    callback: (args, extra) async {
      return mcpJsonResult({
        'hubEndpoint': hub.hubEndpointUrl,
        'hubStatus': hub.hubMcpHost.status.name,
        'servers': [
          for (final s in hub.servers)
            {
              'id': s.id,
              'name': s.name,
              'transport': s.transport.wireName,
              'enabled': s.enabled,
              'builtIn': s.builtIn,
              'repoUrl': s.repoUrl,
              'localPath': s.localPath,
              'command': s.command,
              'args': s.args,
              'env': s.env,
              'cwd': s.cwd,
              'url': s.url,
              'autoStart': s.autoStart,
              'runtime': hub.runtimeInfoFor(s).toJson(),
            },
        ],
      });
    },
  );

  server.registerTool(
    'add_server',
    description:
        '添加一个 MCP：可传 GitHub URL（名称可省略，自动取仓库名），'
        'stdio 填 command/args/env/cwd，HTTP 填 url',
    inputSchema: JsonSchema.object(
      properties: {
        'repoUrl': JsonSchema.string(description: 'Git 仓库 URL'),
        'name': JsonSchema.string(description: '可选；默认取 URL 仓库名'),
        'transport': JsonSchema.string(description: 'stdio 或 http，默认 stdio'),
        'command': JsonSchema.string(),
        'args': JsonSchema.array(items: JsonSchema.string()),
        'env': JsonSchema.object(
          description: '环境变量（仅存本机，不进 WebDAV）',
          additionalProperties: JsonSchema.string(),
        ),
        'cwd': JsonSchema.string(description: 'stdio 工作目录（本机路径）'),
        'url': JsonSchema.string(description: 'HTTP 端点'),
        'enabled': JsonSchema.boolean(description: '默认 true'),
        'cloneRepo': JsonSchema.boolean(description: '是否 git clone，默认 true'),
        'autoStart': JsonSchema.boolean(
          description:
              '仅 HTTP：Hub 启动时是否拉起进程；省略时对可拉起的 HTTP 默认 true',
        ),
      },
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: true,
    ),
    callback: (args, extra) async {
      try {
        final transportRaw =
            mcpTrimmedString(args['transport'])?.toLowerCase() ?? 'stdio';
        final transport = transportRaw == 'http'
            ? McpTransport.http
            : McpTransport.stdio;
        final autoStartExplicit = args.containsKey('autoStart');
        final id = await hub.addServer(
          name: mcpTrimmedString(args['name']) ?? '',
          transport: transport,
          repoUrl: mcpTrimmedString(args['repoUrl']),
          command: mcpTrimmedString(args['command']),
          args: mcpStringList(args['args']),
          env: mcpStringMap(args['env']),
          cwd: mcpTrimmedString(args['cwd']),
          url: mcpTrimmedString(args['url']),
          enabled: mcpBool(args['enabled'], fallback: true),
          autoStart: autoStartExplicit ? mcpBool(args['autoStart']) : null,
          cloneRepo: mcpBool(args['cloneRepo'], fallback: true),
        );
        return mcpJsonResult({
          'ok': true,
          'id': id,
          'message': hub.lastMessage,
        });
      } catch (error) {
        return mcpErrorResult('$error');
      }
    },
  );

  server.registerTool(
    'set_enabled',
    description: '启用或禁用某个 MCP（影响是否写入 Cursor/Codex）',
    inputSchema: JsonSchema.object(
      properties: {
        'id': JsonSchema.string(),
        'enabled': JsonSchema.boolean(),
      },
      required: ['id', 'enabled'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final id = mcpTrimmedString(args['id']);
      if (id == null) return mcpErrorResult('id 不能为空');
      await hub.setEnabled(id, mcpBool(args['enabled']));
      return mcpJsonResult({'ok': true, 'id': id, 'enabled': mcpBool(args['enabled'])});
    },
  );

  server.registerTool(
    'update_server',
    description: '对指定 MCP 本地仓库执行 git pull，并按项目类型自动 npm 构建 / uv sync',
    inputSchema: JsonSchema.object(
      properties: {
        'id': JsonSchema.string(),
      },
      required: ['id'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: true,
    ),
    callback: (args, extra) async {
      final id = mcpTrimmedString(args['id']);
      if (id == null) return mcpErrorResult('id 不能为空');
      try {
        await hub.updateServer(id);
        return mcpJsonResult({'ok': true, 'message': hub.lastMessage});
      } catch (error) {
        return mcpErrorResult('$error');
      }
    },
  );

  server.registerTool(
    'update_all_servers',
    description: '对所有可 Git 更新的 MCP 执行 pull，并自动构建 / 同步依赖',
    inputSchema: JsonSchema.object(properties: const {}),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: true,
    ),
    callback: (args, extra) async {
      await hub.updateAllServers();
      return mcpJsonResult({'ok': true, 'message': hub.lastMessage});
    },
  );

  server.registerTool(
    'remove_server',
    description: '从 Hub 移除 MCP 条目并删除本地 clone（不能移除内置 hubMCP）',
    inputSchema: JsonSchema.object(
      properties: {
        'id': JsonSchema.string(),
      },
      required: ['id'],
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: true,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final id = mcpTrimmedString(args['id']);
      if (id == null) return mcpErrorResult('id 不能为空');
      if (id == HubMcpConstants.serverKey) {
        return mcpErrorResult('不能移除内置 hubMCP');
      }
      try {
        await hub.removeServer(id);
        return mcpJsonResult({'ok': true, 'id': id});
      } catch (error) {
        return mcpErrorResult('$error');
      }
    },
  );

  server.registerTool(
    'configure_clients',
    description:
        '一键把全部 MCP 写入已登记的客户端（Cursor / Codex / Open Code）。'
        '会从各客户端移除 Hub 已删除的 MCP；导入未登记 MCP 请使用 import_from_clients。',
    inputSchema: JsonSchema.object(
      properties: {
        'target': JsonSchema.string(
          description:
              'all | cursor | codex | openCode | opencode，默认 all',
        ),
      },
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final target =
          mcpTrimmedString(args['target'])?.toLowerCase() ?? 'all';
      try {
        if (target == 'all') {
          final r = await hub.configureAllClients();
          return mcpJsonResult({'ok': r.ok, 'message': r.message});
        }
        final platform = AgentPlatformDefinition.tryParse(target);
        if (platform == null) {
          return mcpErrorResult('未知 target：$target');
        }
        final definition = AgentPlatforms.of(platform);
        if (!definition.supportsMcpConfigure) {
          return mcpErrorResult('${definition.label} 暂不支持 MCP 配置写入');
        }
        final r = await hub.configureClient(platform);
        return mcpJsonResult({'ok': r.ok, 'message': r.message, 'path': r.path});
      } catch (error) {
        return mcpErrorResult('$error');
      }
    },
  );

  server.registerTool(
    'import_from_clients',
    description:
        '从 Cursor / Codex / Open Code 配置文件导入 Hub 未登记的 MCP（不覆盖已有条目）',
    inputSchema: JsonSchema.object(properties: const {}),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      try {
        final r = await hub.importMissingFromClients();
        return mcpJsonResult({
          'ok': r.ok,
          'message': r.message,
          'imported': r.imported.map((s) => s.id).toList(),
          'skippedIds': r.skippedIds,
        });
      } catch (error) {
        return mcpErrorResult('$error');
      }
    },
  );

  server.registerTool(
    'get_hub_status',
    description: '查看内置 hubMCP 服务状态与端点',
    inputSchema: JsonSchema.object(properties: const {}),
    annotations:
        const ToolAnnotations(readOnlyHint: true, openWorldHint: false),
    callback: (args, extra) async {
      final host = hub.hubMcpHost;
      return mcpJsonResult({
        'id': HubMcpConstants.serverKey,
        'supported': host.isSupported,
        'status': host.status.name,
        'endpoint': hub.hubEndpointUrl,
        'port': host.boundPort,
        'lastError': host.lastError,
        'webdav': {
          'enabled': hub.webDavConfig.enabled,
          'status': hub.webDavSync.status.name,
          'lastError': hub.webDavSync.lastError,
          'lastSyncedAt': hub.webDavSync.lastSyncedAt?.toIso8601String(),
        },
      });
    },
  );

  server.registerTool(
    'sync_webdav',
    description: '立即把 MCP 清单与远端 catalog.zip 三路合并，再覆盖上传压缩包（需已配置）',
    inputSchema: JsonSchema.object(properties: const {}),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: true,
    ),
    callback: (args, extra) async {
      try {
        await hub.syncWebDavNow();
        return mcpJsonResult({
          'ok': hub.webDavSync.status.name != 'error',
          'status': hub.webDavSync.status.name,
          'message': hub.lastMessage,
          'lastError': hub.webDavSync.lastError,
        });
      } catch (error) {
        return mcpErrorResult('$error');
      }
    },
  );

  server.registerTool(
    'sync_skills',
    description:
        'WebDAV 仅下载/上传 Cursor Skill（固定名 skills.zip 覆盖）。'
        'direction=pull：远端压缩包解压覆盖到本机缓存（不覆盖正式目录）；'
        'direction=merge：远端压缩包解压后合并到缓存（覆盖同名，不删多余项）；'
        'direction=apply：缓存全量镜像到正式 Cursor 目录（本地多余删除）；'
        'direction=push：本机 Cursor 正式目录打包为 skills.zip 覆盖远端（不经缓存）。'
        'target=codex 且 direction=pull/apply/merge 时仅执行本机 Cursor→Codex 转换（不访问 WebDAV）。',
    inputSchema: JsonSchema.object(
      properties: {
        'target': JsonSchema.string(
          description: 'all | cursor | codex，默认 all',
        ),
        'direction': JsonSchema.string(
          description: 'pull（默认）| merge | apply | push',
        ),
      },
    ),
    annotations: const ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: true,
    ),
    callback: (args, extra) async {
      final targetRaw =
          mcpTrimmedString(args['target'])?.toLowerCase() ?? 'all';
      final direction =
          mcpTrimmedString(args['direction'])?.toLowerCase() ?? 'pull';
      final isPush = direction == 'push';
      final isApply = direction == 'apply';
      final isMerge = direction == 'merge';

      Map<String, Object?> pack(SkillSyncResult r) => {
            'ok': r.ok,
            'message': r.message,
            'pulledFiles': r.pulledFiles,
            'pushedFiles': r.pushedFiles,
            'deployedFiles': r.deployedFiles,
            'packageCount': r.packageCount,
          };

      try {
        if (targetRaw == 'codex') {
          if (isPush) {
            return mcpJsonResult({
              'ok': false,
              'message':
                  '远端仅保留 Cursor；Codex 不上传 WebDAV，请用本机 Cursor→Codex 转换',
            });
          }
          final r = await hub.convertResourceFromCursor(AgentResourceKind.skill);
          return mcpJsonResult(pack(r));
        }
        if (targetRaw == 'cursor') {
          final SkillSyncResult r;
          if (isPush) {
            r = await hub.pushSkillsToWebDav(SkillTarget.cursor);
          } else if (isApply) {
            r = await hub.applyResourceFromCache(AgentResourceKind.skill);
          } else if (isMerge) {
            r = await hub.mergeResourceToAllTargets(AgentResourceKind.skill);
          } else {
            r = await hub.syncSkillsFromWebDav(SkillTarget.cursor);
          }
          return mcpJsonResult(pack(r));
        }
        final SkillSyncResult r;
        if (isPush) {
          r = await hub.pushAllSkillsToWebDav();
        } else if (isApply) {
          r = await hub.applyResourceFromCache(AgentResourceKind.skill);
        } else if (isMerge) {
          r = await hub.mergeResourceToAllTargets(AgentResourceKind.skill);
        } else {
          r = await hub.syncAllSkillsFromWebDav();
        }
        return mcpJsonResult(pack(r));
      } catch (error) {
        return mcpErrorResult('$error');
      }
    },
  );
}
