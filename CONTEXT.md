# Agent Hub

Agent Hub keeps two kinds of configuration for Cursor, Codex, Open Code, WorkBuddy, WorkBuddy AI, DeepSeek Harness, Antigravity, and Doubao. They belong to one product. They do not use the same steps. WorkBuddy and WorkBuddy AI receive Skill and Rule copies. DeepSeek Harness receives Skill copies, a managed section of `~/.dsh/AGENTS.md`, and MCP rows in `~/.dsh/cordis.patch.yml`. Antigravity receives Skill copies, a managed section of `~/.gemini/GEMINI.md`, and MCP rows in `~/.gemini/config/mcp_config.json`. Doubao receives Skill copies in its workspace `.user_skills` folder; its connectors are configured inside the app, so no local MCP file is written. Command and Hook are not written for those clients.

## Language

**Hub configuration**:
The Catalog and the Folder resources together. This is the full set the Hub can move between machines.
_Avoid_: Agent configuration, All, everything

**Catalog**:
The Hub list of MCP servers that can move between machines. It does not include secrets, local paths, or enabled state.
_Avoid_: MCP (as the name of the list), MCP resource, Agent resource

**MCP**:
One server the Hub manages. One row in the Catalog.
_Avoid_: resource, package

**Folder resource**:
Skill, Command, Rule, or Hook files that live in client folders.
_Avoid_: Agent configuration, Agent resource, MCP

**Skill**:
A Folder resource of Skill files.

**Command**:
A Folder resource of Command files.

**Rule**:
A Folder resource of Rule files.

**Hook**:
A Folder resource of Hook files.

**Hub cache**:
The Hub local copy of Folder resources. It is not the official Cursor folders.
_Avoid_: official directory, client folder (for this copy)

**Client MCP config**:
The MCP server entries stored by Cursor, Codex, Open Code, WorkBuddy, WorkBuddy AI, DeepSeek Harness, or Antigravity. This is not the Catalog.
_Avoid_: Catalog, mcp.json (as the name of the concept)
