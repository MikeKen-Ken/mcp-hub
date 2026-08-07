# MCP Hub

轻量桌面应用：把多个 MCP 仓库管理在本机，用开关启用，并一键写入 **Cursor** / **Codex** 配置。

技术栈与配置写法参考 [kanban](https://github.com/MikeKen-Ken) 项目里的 Windows MCP 一键配置实现，但职责独立——看板继续只做看板。

## 能做什么（MVP）

- 粘贴 Git URL，clone 到 `~/.mcp-hub/servers/<id>`
- 列表开关：控制是否写入客户端配置
- 支持 **stdio**（客户端按需拉起）与 **HTTP**（Hub 可启停进程）
- 一键合并写入：
  - Cursor: `%USERPROFILE%\.cursor\mcp.json`
  - Codex: `%USERPROFILE%\.codex\config.toml`（并确保 `features.rmcp_client = true`）
- 不覆盖你已有的其他 MCP 条目

## 开发

```powershell
$env:Path = "C:\Users\Administrator\AppData\Local\flutter\bin;" + $env:Path
flutter pub get
flutter run -d windows
flutter test
```

## 数据目录

| 路径 | 用途 |
|------|------|
| `~/.mcp-hub/catalog.json` | MCP 清单（开关、transport、command/url） |
| `~/.mcp-hub/servers/` | 各 MCP 仓库 checkout |

仓库内的 `servers/` 目录预留给「开发时作为 git submodule 镜像」；运行时默认写用户目录，避免打包后的安装目录不可写。

## 后续

- 从 Hub 仓库 `.gitmodules` 批量同步
- 健康检查 / 日志面板
- 多机清单同步
