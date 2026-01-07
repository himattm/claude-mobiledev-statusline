#!/bin/bash
# @prism-plugin
# @name mcp
# @version 1.0.0
# @description Shows MCP server count
# @author Prism
# @source https://github.com/himattm/prism
# @update-url https://raw.githubusercontent.com/himattm/prism/main/plugins/mcp/prism-plugin-mcp.sh
#
# Output: mcp:N where N is the number of configured servers
# Checks both global (~/.claude.json) and project (.mcp.json) configs

set -e

# Read input JSON
INPUT=$(cat)

# Parse input
PROJECT_DIR=$(echo "$INPUT" | jq -r '.prism.project_dir')
GRAY=$(echo "$INPUT" | jq -r '.colors.gray')
RESET=$(echo "$INPUT" | jq -r '.colors.reset')

# Check global MCP servers in ~/.claude.json
if [ -f "$HOME/.claude.json" ]; then
    global_mcp=$(jq -r '.mcpServers // empty | keys | length' "$HOME/.claude.json" 2>/dev/null)
    if [ -n "$global_mcp" ] && [ "$global_mcp" -gt 0 ]; then
        echo -e "${GRAY}mcp:${global_mcp}${RESET}"
        exit 0
    fi
fi

# Check project-level .mcp.json
if [ -f "${PROJECT_DIR}/.mcp.json" ]; then
    proj_mcp=$(jq -r '.mcpServers // empty | keys | length' "${PROJECT_DIR}/.mcp.json" 2>/dev/null)
    if [ -n "$proj_mcp" ] && [ "$proj_mcp" -gt 0 ]; then
        echo -e "${GRAY}mcp:${proj_mcp}${RESET}"
        exit 0
    fi
fi

# No MCP servers configured
exit 0
