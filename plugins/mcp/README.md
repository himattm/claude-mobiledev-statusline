# MCP Plugin

Shows count of configured MCP (Model Context Protocol) servers.

## Output Format

```
mcp:N
```

## Examples

| Output | Meaning |
|--------|---------|
| `mcp:1` | 1 MCP server configured |
| `mcp:3` | 3 MCP servers configured |
| (none) | No servers configured |

## Config Locations

Checked in order:
1. `~/.claude.json` - Global MCP servers
2. `PROJECT_DIR/.mcp.json` - Project-level servers

First file with servers wins.

## What is MCP?

Model Context Protocol allows Claude Code to connect to external tools:
- Database access
- API integrations
- File system tools
- Custom capabilities

This indicator shows how many tool providers are available.

## Installation

```bash
cp prism-plugin-mcp.sh ~/.claude/prism-plugins/
```

## Testing

```bash
./test.sh
```
