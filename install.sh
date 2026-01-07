#!/bin/bash
#
# Prism Installer
# A fast, customizable status line for Claude Code
#
# Usage: curl -fsSL https://raw.githubusercontent.com/himattm/prism/main/install.sh | bash
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
RESET='\033[0m'

REPO="himattm/prism"
BRANCH="main"
CLAUDE_DIR="$HOME/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"

info() { echo -e "${CYAN}$1${RESET}"; }
success() { echo -e "${GREEN}$1${RESET}"; }
warn() { echo -e "${YELLOW}$1${RESET}"; }
error() { echo -e "${RED}$1${RESET}"; exit 1; }

echo ""
echo -e "${CYAN}💎 Prism Installer${RESET}"
echo -e "${DIM}A fast, customizable status line for Claude Code${RESET}"
echo ""

# Check for dependencies
if ! command -v jq &> /dev/null; then
    error "jq is required but not installed. Install it with: brew install jq"
fi

if ! command -v curl &> /dev/null; then
    error "curl is required but not installed."
fi

# Create ~/.claude if it doesn't exist
if [ ! -d "$CLAUDE_DIR" ]; then
    info "Creating $CLAUDE_DIR..."
    mkdir -p "$CLAUDE_DIR"
fi

# Download scripts
info "Downloading Prism scripts..."

curl -fsSL "https://raw.githubusercontent.com/$REPO/$BRANCH/prism.sh" -o "$CLAUDE_DIR/prism.sh"
curl -fsSL "https://raw.githubusercontent.com/$REPO/$BRANCH/prism-idle-hook.sh" -o "$CLAUDE_DIR/prism-idle-hook.sh"
curl -fsSL "https://raw.githubusercontent.com/$REPO/$BRANCH/prism-busy-hook.sh" -o "$CLAUDE_DIR/prism-busy-hook.sh"

chmod +x "$CLAUDE_DIR/prism.sh"
chmod +x "$CLAUDE_DIR/prism-idle-hook.sh"
chmod +x "$CLAUDE_DIR/prism-busy-hook.sh"

success "  Downloaded prism.sh"
success "  Downloaded prism-idle-hook.sh"
success "  Downloaded prism-busy-hook.sh"

# Download bundled plugins
info "Downloading plugins..."

PLUGIN_DIR="$CLAUDE_DIR/prism-plugins"
mkdir -p "$PLUGIN_DIR"

for plugin in git gradle xcode mcp devices; do
    curl -fsSL "https://raw.githubusercontent.com/$REPO/$BRANCH/plugins/prism-plugin-${plugin}.sh" -o "$PLUGIN_DIR/prism-plugin-${plugin}.sh"
    chmod +x "$PLUGIN_DIR/prism-plugin-${plugin}.sh"
    success "  Downloaded prism-plugin-${plugin}.sh"
done

# Update settings.json
info "Configuring Claude Code settings..."

if [ ! -f "$SETTINGS_FILE" ]; then
    # Create new settings file
    cat > "$SETTINGS_FILE" << 'EOF'
{
  "statusLine": {
    "type": "command",
    "command": "$HOME/.claude/prism.sh"
  },
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/prism-busy-hook.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/prism-idle-hook.sh"
          }
        ]
      }
    ]
  }
}
EOF
    success "  Created $SETTINGS_FILE"
else
    # Merge with existing settings
    BACKUP_FILE="$SETTINGS_FILE.backup.$(date +%s)"
    cp "$SETTINGS_FILE" "$BACKUP_FILE"

    # Build the new config to merge
    NEW_CONFIG=$(cat << 'EOF'
{
  "statusLine": {
    "type": "command",
    "command": "$HOME/.claude/prism.sh"
  },
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/prism-busy-hook.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/prism-idle-hook.sh"
          }
        ]
      }
    ]
  }
}
EOF
)

    # Merge: existing settings + new Prism config (Prism config wins for statusLine/hooks)
    MERGED=$(jq -s '.[0] * .[1]' "$SETTINGS_FILE" <(echo "$NEW_CONFIG"))
    echo "$MERGED" > "$SETTINGS_FILE"

    success "  Updated $SETTINGS_FILE"
    echo -e "  ${DIM}Backup saved to $BACKUP_FILE${RESET}"
fi

echo ""
success "Prism installed successfully!"
echo ""
echo "Restart Claude Code or start a new session to activate."
echo ""
echo -e "${CYAN}Configuration${RESET} (highest to lowest priority):"
echo -e "  ${DIM}1.${RESET} .claude/prism.local.json    ${DIM}Your personal overrides (gitignored)${RESET}"
echo -e "  ${DIM}2.${RESET} .claude/prism.json          ${DIM}Repo config (commit for your team)${RESET}"
echo -e "  ${DIM}3.${RESET} ~/.claude/prism-config.json ${DIM}Your global defaults${RESET}"
echo ""
echo -e "${CYAN}Quick setup:${RESET}"
echo -e "  ${DIM}# Create global defaults${RESET}"
echo "  ~/.claude/prism.sh init-global"
echo ""
echo -e "  ${DIM}# Create repo config${RESET}"
echo "  ~/.claude/prism.sh init"
echo ""
echo -e "See examples: ${DIM}https://github.com/himattm/prism/tree/main/examples${RESET}"
echo ""
