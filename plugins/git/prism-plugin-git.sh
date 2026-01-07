#!/bin/bash
# @prism-plugin
# @name git
# @version 1.0.0
# @description Shows git branch and dirty status indicators
# @author Prism
# @source https://github.com/himattm/prism
# @update-url https://raw.githubusercontent.com/himattm/prism/main/plugins/git/prism-plugin-git.sh
#
# Output: branch_name with indicators (* staged, ** unstaged, + untracked, ⇣ behind, ⇡ ahead)
# Example: main*+⇣⇡

set -e

# Read input JSON
INPUT=$(cat)

# Parse input
PROJECT_DIR=$(echo "$INPUT" | jq -r '.prism.project_dir')
IS_IDLE=$(echo "$INPUT" | jq -r '.prism.is_idle')
YELLOW=$(echo "$INPUT" | jq -r '.colors.yellow')
RESET=$(echo "$INPUT" | jq -r '.colors.reset')

# Cache settings
GIT_CACHE="/tmp/prism-git-info-$(echo "$PROJECT_DIR" | md5 -q)"
GIT_CACHE_MAX_AGE=2

# Get git info (uncached)
get_git_info_uncached() {
    cd "$PROJECT_DIR" 2>/dev/null || return

    if ! timeout 1 git rev-parse --git-dir > /dev/null 2>&1; then
        return
    fi

    local branch=$(timeout 1 git branch --show-current 2>/dev/null)
    if [ -z "$branch" ]; then
        branch=$(timeout 1 git rev-parse --short HEAD 2>/dev/null)
    fi

    # Use git status --porcelain for efficiency
    local status=$(timeout 1 git status --porcelain 2>/dev/null | head -20)
    local dirty=""
    if echo "$status" | grep -q "^[MADRC]"; then
        dirty="*"  # staged changes
    fi
    if echo "$status" | grep -q "^.[MADRC]"; then
        dirty="${dirty}*"  # unstaged changes
    fi
    if echo "$status" | grep -q "^??"; then
        dirty="${dirty}+"  # untracked
    fi

    # Check ahead/behind upstream
    local arrows=""
    local behind=$(timeout 1 git rev-list --count HEAD..@{upstream} 2>/dev/null || echo "0")
    local ahead=$(timeout 1 git rev-list --count @{upstream}..HEAD 2>/dev/null || echo "0")
    if [ "$behind" -gt 0 ] 2>/dev/null; then
        arrows="⇣"  # commits to pull
    fi
    if [ "$ahead" -gt 0 ] 2>/dev/null; then
        arrows="${arrows}⇡"  # commits to push
    fi

    echo "${branch}${dirty}${arrows}"
}

# Check cache
if [ -f "$GIT_CACHE" ]; then
    cache_age=$(($(date +%s) - $(stat -f %m "$GIT_CACHE" 2>/dev/null || echo 0)))
    if [ "$cache_age" -lt "$GIT_CACHE_MAX_AGE" ]; then
        GIT_INFO=$(cat "$GIT_CACHE")
        if [ -n "$GIT_INFO" ]; then
            echo -e "${YELLOW}${GIT_INFO}${RESET}"
        fi
        exit 0
    fi
fi

# Only refresh when idle
if [ "$IS_IDLE" != "true" ]; then
    if [ -f "$GIT_CACHE" ]; then
        GIT_INFO=$(cat "$GIT_CACHE")
        if [ -n "$GIT_INFO" ]; then
            echo -e "${YELLOW}${GIT_INFO}${RESET}"
        fi
    fi
    exit 0
fi

# Refresh cache
GIT_INFO=$(get_git_info_uncached)
echo "$GIT_INFO" > "$GIT_CACHE"

if [ -n "$GIT_INFO" ]; then
    echo -e "${YELLOW}${GIT_INFO}${RESET}"
fi
