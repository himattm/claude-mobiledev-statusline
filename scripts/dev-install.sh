#!/bin/bash
# Install prism from local source (for development testing)

set -e

CLAUDE_DIR="$HOME/.claude"
BINARY_PATH="$CLAUDE_DIR/prism"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Ensure claude directory exists
mkdir -p "$CLAUDE_DIR"

# Backup current binary if exists
if [ -f "$BINARY_PATH" ]; then
    BACKUP="$BINARY_PATH.backup.$(date +%s)"
    cp "$BINARY_PATH" "$BACKUP"
    echo "Backed up current binary to: $BACKUP"
fi

# Build from local source
echo "Building from local source..."
cd "$REPO_ROOT"
go build -ldflags="-s -w" -o "$BINARY_PATH.new" ./cmd/prism/
chmod +x "$BINARY_PATH.new"
mv "$BINARY_PATH.new" "$BINARY_PATH"

echo "Installed local build: $($BINARY_PATH version)"
