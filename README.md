# Agent Hub

轻量桌面应用：集中管理 Cursor / Codex 的 Agent 相关配置（当前以 **MCP** 为主，后续可扩展 Skill 等），用开关启用，并一键写入客户端。

技术栈与配置写法参考 [kanban](https://github.com/MikeKen-Ken) 项目里的 Windows MCP 一键配置实现，但职责独立——看板继续只做看板。

## 能做什么（MVP）

- **内置 `hubMCP`**：始终存在；AI 可用工具添加仓库、开关、一键配置 Cursor/Codex
- 粘贴 Git URL，clone 到 `~/.mcp-hub/servers/<id>`（名称可留空，自动取仓库名）
- 列表开关：控制是否写入客户端配置
- 支持 **stdio**（客户端按需拉起）与 **HTTP**（Hub 可启停进程）
- 一键合并写入：
  - Cursor: `%USERPROFILE%\.cursor\mcp.json`
  - Codex: `%USERPROFILE%\.codex\config.toml`（并确保 `features.rmcp_client = true`）
- 不覆盖你已有的其他 MCP 条目
- 一键 `git pull` 更新本地仓库
- **WebDAV 同步**：跨电脑同步 MCP 清单（坚果云等）；账号密码仅存本机
- **Skill 同步**：分别同步 Cursor / Codex 的 Skill 文件夹（WebDAV 拉取后复制到本机目录）

内置端点默认：`http://127.0.0.1:18766/mcp`（需桌面端运行；Web 预览无法真正起服务）

### WebDAV 换机流程

1. 旧电脑启用 WebDAV，远端目录例如 `/McpHub`
2. 新电脑安装 Agent Hub，填同一 WebDAV → 拉取
3. 清单恢复后，按需对仓库执行 clone/更新，再一键写入 Cursor/Codex
4. 在首页分别「同步 Cursor / Codex Skill」（从 WebDAV 文件夹部署到本机）

同步：仓库 URL、command/args 等。  
不同步：WebDAV 密码、本机路径、`cwd`、`env` 密钥、MCP 开/关状态、内置 hubMCP。

### Skill 目录约定

| 角色 | 路径 |
|------|------|
| WebDAV Cursor | `{remotePath}/skills/cursor/` |
| WebDAV Codex | `{remotePath}/skills/codex/` |
| 本机缓存 | `~/.mcp-hub/skills/{cursor\|codex}/` |
| 部署 Cursor | `~/.cursor/skills/` |
| 部署 Codex | `~/.codex/skills/` |

每个 Skill 是一个含 `SKILL.md` 的子文件夹。同步为合并复制（覆盖同名，不删除目标多余项；跳过 `.` 开头目录）。

## 发布 / 更新

推送到 `main` 会触发 GitHub Actions（`Push Build`）：

- 自动解析下一版本号（相对最新正式 Release 升 patch，或沿用已抬高的 `pubspec`）
- 构建 **Windows zip** + **Linux x64 tar.gz**
- 以正式 Release 发布（资产名如 `McpHub-x.y.z-windows-x86-64.zip`）
- 写回 `pubspec.yaml` 版本（`[skip ci]`）

也可在 Actions 里手动跑 `Release Build`。客户端（Windows）可从 GitHub Release 检查并安装更新。

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
| `~/.mcp-hub/skills/` | Skill WebDAV 本地缓存（再部署到 Cursor/Codex） |

仓库内的 `servers/` 目录预留给「开发时作为 git submodule 镜像」；运行时默认写用户目录，避免打包后的安装目录不可写。

## 后续

- 从 Hub 仓库 `.gitmodules` 批量同步
- 健康检查 / 日志面板
- Skill 自动拉取（跟随 WebDAV poll）
