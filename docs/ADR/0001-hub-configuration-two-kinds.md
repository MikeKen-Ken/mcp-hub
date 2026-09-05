# Hub configuration has two kinds; WebDAV All moves both

Status: accepted

The Catalog (MCP server list) and Folder resources (Skill, Command, Rule, Hook) are different kinds. They stay in one product: Hub configuration.

Manual WebDAV Download, Merge, and Upload All must move the Catalog and the Folder resources together. A user who taps Upload All must not leave MCP only on this machine.

We rejected two alternatives: treat MCP as a fifth Folder resource (the steps are not the same), and keep Catalog out of All (the home screen then lies).

Apply, automatic WebDAV, backup, and home layout are in ADR 0002.
