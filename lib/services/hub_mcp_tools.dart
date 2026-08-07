import 'package:mcp_dart/mcp_dart.dart';

import '../controllers/hub_controller.dart';
import '../features/skill_sync/skill_sync.dart';
import '../models/mcp_transport.dart';
import 'hub_mcp_constants.dart';
import 'hub_mcp_results.dart';
import 'mcp_client_configurator.dart';

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
          description: '仅 HTTP：Hub 启动时是否拉起进程',
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
          autoStart: mcpBool(args['autoStart']),
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
    description: '对指定 MCP 本地仓库执行 git pull --ff-only',
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
    description: '对所有有本地路径的 MCP 执行 git pull',
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
    description: '一键把已启用的 MCP 写入 Cursor 和/或 Codex',
    inputSchema: JsonSchema.object(
      properties: {
        'target': JsonSchema.string(
          description: 'all | cursor | codex，默认 all',
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
        if (target == 'cursor') {
          final r = await hub.configureClient(McpClientKind.cursor);
          return mcpJsonResult({'ok': r.ok, 'message': r.message, 'path': r.path});
        }
        if (target == 'codex') {
          final r = await hub.configureClient(McpClientKind.codex);
          return mcpJsonResult({'ok': r.ok, 'message': r.message, 'path': r.path});
        }
        final r = await hub.configureAllClients();
        return mcpJsonResult({'ok': r.ok, 'message': r.message});
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
    description: '立即拉取并推送 MCP 目录到 WebDAV（需已配置）',
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
        '从 WebDAV 拉取 Skill 文件夹并复制到 Cursor/Codex 目录；'
        'direction=push 则上传本机 Skill 到 WebDAV',
    inputSchema: JsonSchema.object(
      properties: {
        'target': JsonSchema.string(
          description: 'all | cursor | codex，默认 all',
        ),
        'direction': JsonSchema.string(
          description: 'pull（默认）或 push',
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

      Future<SkillSyncResult> runOne(SkillTarget target) {
        return isPush
            ? hub.pushSkillsToWebDav(target)
            : hub.syncSkillsFromWebDav(target);
      }

      try {
        if (targetRaw == 'cursor') {
          final r = await runOne(SkillTarget.cursor);
          return mcpJsonResult({
            'ok': r.ok,
            'message': r.message,
            'pulledFiles': r.pulledFiles,
            'pushedFiles': r.pushedFiles,
            'deployedFiles': r.deployedFiles,
            'packageCount': r.packageCount,
          });
        }
        if (targetRaw == 'codex') {
          final r = await runOne(SkillTarget.codex);
          return mcpJsonResult({
            'ok': r.ok,
            'message': r.message,
            'pulledFiles': r.pulledFiles,
            'pushedFiles': r.pushedFiles,
            'deployedFiles': r.deployedFiles,
            'packageCount': r.packageCount,
          });
        }
        final r = isPush
            ? await hub.pushAllSkillsToWebDav()
            : await hub.syncAllSkillsFromWebDav();
        return mcpJsonResult({
          'ok': r.ok,
          'message': r.message,
          'pulledFiles': r.pulledFiles,
          'pushedFiles': r.pushedFiles,
          'deployedFiles': r.deployedFiles,
          'packageCount': r.packageCount,
        });
      } catch (error) {
        return mcpErrorResult('$error');
      }
    },
  );
}
