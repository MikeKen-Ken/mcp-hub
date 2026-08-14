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
  - OpenCode: `%USERPROFILE%\.config\opencode\opencode.json`（`mcp.<name>`；整值密钥用 `{env:NAME}`，路径内占位符写入时展开）
- 不覆盖你已有的其他 MCP 条目
- 一键 `git pull` 更新本地仓库
- **WebDAV 下载/上传/合并**：跨电脑用固定名压缩包传输 MCP 清单与 Agent 配置（坚果云等）；账号密码仅存本机
- **Agent 配置下载/上传**：WebDAV 只下载/上传 Cursor 侧 Skill / Command / Rule；Codex 由本机从 Cursor 转换生成
- **分层管理界面**：首页只展示功能入口；本地 MCP 收纳在「客户端 MCP」二级菜单中

内置端点默认：`http://127.0.0.1:18766/mcp`（需桌面端运行；Web 预览无法真正起服务）

### WebDAV 换机流程
1. 旧电脑启用 WebDAV，远端目录例如 `/AgentHub`，上传生成固定名压缩包
2. 新电脑安装 Agent Hub，填同一 WebDAV → 下载（覆盖）或合并清单
3. 清单恢复后，按需对仓库执行 clone/更新，再一键写入 Cursor/Codex
4. 在「Agent 配置下载/上传」中下载或合并 Cursor 资源（Skill / Command / Rule）；Skill 与 Rule 会自动本机转换为 Codex

下载/上传：仓库 URL、command/args 等。  

不下载/上传：WebDAV 密码、本机路径、`cwd`、`env` 密钥、MCP 开/关状态、内置 hubMCP。

远端每次覆盖同名文件，不按日期堆积：

| 文件 | 内容 |
|------|------|
| `{remotePath}/catalog.zip` | MCP 清单（包内 `catalog.json`） |
| `{remotePath}/skills.zip` | Cursor Skill 目录 |
| `{remotePath}/commands.zip` | Cursor Command 目录 |
| `{remotePath}/rules.zip` | Cursor Rule 目录 |

**下载**把压缩包解压后覆盖对应缓存或清单；**合并**先解压再与本机合并（清单三路合并；资源覆盖同名、保留本地多余项）。自动拉取使用合并，避免定时整包覆盖本机。旧版 `catalog.json` 与 `{skills\|commands\|rules}/cursor/` 仅在对应 zip 不存在时回退读取，上传不再写入目录树。

### Agent 配置下载/上传约定（Cursor-only 远端）
**远端权威源只保留 Cursor 目录**，不再把 Codex 当作 WebDAV 上下行目标：

| 角色 | 路径 |
|------|------|
| WebDAV（权威） | `{remotePath}/{skills\|commands\|rules}.zip` |
| 本机缓存 | `~/.mcp-hub/skills/cursor/` 或 `~/.mcp-hub/agent-resources/{commands\|rules}/cursor/` |
| 部署 Cursor | `~/.cursor/skills/`、`~/.cursor/commands/`、`~/.cursor/rules/` |
| 本机 Codex（转换产物） | `~/.codex/skills/`、`~/.codex/AGENTS.md` |

每个 Skill 是一个含 `SKILL.md` 的子文件夹。下载为压缩包解压覆盖缓存；合并为解压后覆盖同名、不删除缓存多余项。应用到 Cursor 仍为全量镜像。跳过 `.` 开头目录。

**迁移说明**：若旧远端仍有 `catalog.json` 或 `{remotePath}/{skills\|commands\|rules}/cursor/`（以及历史 `codex/` 目录），新版本仅在对应 zip 不存在时回退读取目录树/`catalog.json`；上传只覆盖固定名 zip，不会自动删除旧目录。可手工清理，或以 Cursor 为准重新「上传全部」。本机 Codex / Open Code 请用「一键转换」从 Cursor 生成。

### Command / Rule

| 类型 | WebDAV | 本机 |
|------|--------|------|
| Cursor Command | `{remotePath}/commands.zip` | `~/.cursor/commands/` |
| Cursor Rule | `{remotePath}/rules.zip` | `~/.cursor/rules/` |
| Codex Rule | （不通过 WebDAV） | 由 Cursor Rule 转换写入 `~/.codex/AGENTS.md` |

Cursor Command 使用 Markdown 文件。Codex 暂无与 Cursor 全局 Command 对等的入口，因此 Command 不下载/上传、不转换到 Codex。

### 一键转换（Cursor → Codex / OpenCode）

以本机 Cursor 目录为唯一编辑源，批量转换到 Codex / OpenCode（不依赖 WebDAV）。
「更新/覆盖」只负责缓存 → Cursor；转换请使用各资源卡片或顶部的「一键转换」：

| 资源 | 源 | 目标 | 转换内容 |
|------|----|------|----------|
| Skill | `~/.cursor/skills/` | `~/.codex/skills/` 与 `%USERPROFILE%\\.config\\opencode\\skills/` | 整包镜像后按目标格式转换：Codex 生成 `agents/openai.yaml`；OpenCode 改写 `SKILL.md` frontmatter（`disable-model-invocation` → `metadata.opencode/autoinvoke`） |
| Rule | `~/.cursor/rules/**/*.mdc` | `~/.codex/AGENTS.md` 与 `%USERPROFILE%\\.config\\opencode\\AGENTS.md` | 去掉 frontmatter，整文件覆盖对应全局 `AGENTS.md` |
| Command | `~/.cursor/commands/` | OpenCode `%USERPROFILE%\\.config\\opencode\\commands/<name>.md` | Codex 无对等目录；OpenCode 按 Cursor 镜像写入并删除多余命令文件 |

界面在推荐流程提供「一键转换全部目标」，并在 Skill / Command / Rule 卡片各提供「一键转换」。转换产物以本机 Cursor 为准全量对齐附件后，再写成各客户端格式：Skill 整包镜像（多余文件与多余包会删除），Codex 写入 `agents/openai.yaml`，OpenCode 改写 `SKILL.md` 为其所识别的 frontmatter；Rule 整文件覆盖 `AGENTS.md`；OpenCode Command 删除 Cursor 中已不存在的命令文件。OpenCode **不读取、合并或覆盖** 其余 JSON/JSONC 配置。Skill 的正文与 `scripts/`、`references/` 两边共用。Codex `allow_implicit_invocation` **每次以 Cursor 的 `disable-model-invocation` 为准覆盖**（`true` → 禁止隐式调用；缺省则允许），不保留 Codex 旧值。`short_description` 从 description 生成，长度 25–64。OpenCode 将同一字段映射为 `metadata.opencode/autoinvoke`。

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
| `~/.mcp-hub/skills/` | Skill WebDAV 本地缓存（兼容已有目录） |
| `~/.mcp-hub/agent-resources/` | Command / Rule WebDAV 本地缓存 |

仓库内的 `servers/` 目录预留给「开发时作为 git submodule 镜像」；运行时默认写用户目录，避免打包后的安装目录不可写。

## 后续

- 从 Hub 仓库 `.gitmodules` 批量同步
- 健康检查 / 日志面板
- Agent 配置自动拉取（跟随 WebDAV poll）
