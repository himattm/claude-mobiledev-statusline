#!/bin/bash
# Prism Update Hook
# Shows a one-time notification when an update is available
# Called by Claude Code's UserPromptSubmit hook
#
# This hook checks the update cache and notifies the user once per day
# if a new version is available. It runs quickly and exits silently
# if no update is available or if the user has already been notified.

set -e

# Cache files
UPDATE_CACHE="/tmp/prism-update-check"
PROMPTED_CACHE="/tmp/prism-update-prompted"
PROMPTED_MAX_AGE=86400  # 24 hours - only prompt once per day

# ANSI colors for hook output
CYAN='\033[36m'
YELLOW='\033[33m'
RESET='\033[0m'

# Check if we've already prompted recently
already_prompted() {
    [ -f "$PROMPTED_CACHE" ] || return 1

    local cache_mtime
    if [[ "$OSTYPE" == "darwin"* ]]; then
        cache_mtime=$(stat -f %m "$PROMPTED_CACHE" 2>/dev/null || echo 0)
    else
        cache_mtime=$(stat -c %Y "$PROMPTED_CACHE" 2>/dev/null || echo 0)
    fi

    local now=$(date +%s)
    local cache_age=$((now - cache_mtime))

    [ "$cache_age" -lt "$PROMPTED_MAX_AGE" ]
}

# Main logic
main() {
    # Exit early if we've already prompted today
    if already_prompted; then
        exit 0
    fi

    # Check if update cache exists and indicates an update is available
    if [ ! -f "$UPDATE_CACHE" ]; then
        exit 0
    fi

    # Read update status from cache
    local update_available
    update_available=$(jq -r '.update_available // false' "$UPDATE_CACHE" 2>/dev/null || echo "false")

    if [ "$update_available" != "true" ]; then
        exit 0
    fi

    # Get version info from cache
    local local_version remote_version
    local_version=$(jq -r '.local_version // "unknown"' "$UPDATE_CACHE" 2>/dev/null || echo "unknown")
    remote_version=$(jq -r '.remote_version // "unknown"' "$UPDATE_CACHE" 2>/dev/null || echo "unknown")

    # Mark as prompted
    touch "$PROMPTED_CACHE"

    # Output the notification
    # Note: Hook output is shown to the user by Claude Code
    echo -e "${CYAN}Prism update available${RESET} (${local_version} → ${remote_version}). Run ${YELLOW}prism update${RESET} to upgrade."
}

main "$@"
