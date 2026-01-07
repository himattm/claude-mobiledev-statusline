#!/bin/bash
# @prism-plugin
# @name update
# @version 1.0.0
# @description Shows indicator when Prism update is available
# @author Prism
# @source https://github.com/himattm/prism
# @update-url https://raw.githubusercontent.com/himattm/prism/main/plugins/update/prism-plugin-update.sh
#
# Output: Up arrow when update available, empty otherwise
# Example: ⬆

set -e

# Read input JSON from stdin
INPUT=$(cat)

# Parse input
VERSION=$(echo "$INPUT" | jq -r '.prism.version // "0.0.0"')
IS_IDLE=$(echo "$INPUT" | jq -r '.prism.is_idle // false')
CYAN=$(echo "$INPUT" | jq -r '.colors.cyan // ""')
RESET=$(echo "$INPUT" | jq -r '.colors.reset // ""')

# Plugin config (optional overrides)
CONFIG_CHECK_INTERVAL=$(echo "$INPUT" | jq -r '.config.update.check_interval_hours // 24')
# Note: jq's // treats false as falsy, so we need explicit null check
CONFIG_ENABLED=$(echo "$INPUT" | jq -r 'if .config.update.enabled == false then "false" else "true" end')

# Exit if plugin is disabled
if [ "$CONFIG_ENABLED" = "false" ]; then
    exit 0
fi

# Cache settings
UPDATE_CACHE="/tmp/prism-update-check"
UPDATE_CACHE_MAX_AGE=$((CONFIG_CHECK_INTERVAL * 3600))  # Convert hours to seconds
GITHUB_RAW_URL="https://raw.githubusercontent.com/himattm/prism/main/prism.sh"

# Semver comparison: returns 0 if $1 < $2
version_lt() {
    [ "$1" = "$2" ] && return 1

    local IFS=.
    local i
    local v1=($1)
    local v2=($2)

    # Compare each component
    for ((i=0; i<${#v1[@]} || i<${#v2[@]}; i++)); do
        local n1=${v1[i]:-0}
        local n2=${v2[i]:-0}

        # Remove any non-numeric suffix (e.g., "1-beta" -> "1")
        n1=$(echo "$n1" | sed 's/[^0-9].*//')
        n2=$(echo "$n2" | sed 's/[^0-9].*//')

        [ "${n1:-0}" -lt "${n2:-0}" ] && return 0
        [ "${n1:-0}" -gt "${n2:-0}" ] && return 1
    done
    return 1
}

# Check if cache exists and is still valid
cache_is_valid() {
    [ -f "$UPDATE_CACHE" ] || return 1

    # Get cache file modification time
    local cache_mtime
    if [[ "$OSTYPE" == "darwin"* ]]; then
        cache_mtime=$(stat -f %m "$UPDATE_CACHE" 2>/dev/null || echo 0)
    else
        cache_mtime=$(stat -c %Y "$UPDATE_CACHE" 2>/dev/null || echo 0)
    fi

    local now=$(date +%s)
    local cache_age=$((now - cache_mtime))

    [ "$cache_age" -lt "$UPDATE_CACHE_MAX_AGE" ]
}

# Read cached result
read_cache() {
    if [ -f "$UPDATE_CACHE" ]; then
        jq -r '.update_available // "false"' "$UPDATE_CACHE" 2>/dev/null || echo "false"
    else
        echo "false"
    fi
}

# Fetch remote version and update cache
refresh_cache() {
    local remote_version
    remote_version=$(curl -fsSL --max-time 3 "$GITHUB_RAW_URL" 2>/dev/null | \
                     head -10 | grep '^VERSION=' | cut -d'"' -f2)

    if [ -z "$remote_version" ]; then
        # Network error - don't update cache, keep old value
        return 1
    fi

    local update_available="false"
    if version_lt "$VERSION" "$remote_version"; then
        update_available="true"
    fi

    # Write cache as JSON
    cat > "$UPDATE_CACHE" << EOF
{
  "checked_at": $(date +%s),
  "local_version": "$VERSION",
  "remote_version": "$remote_version",
  "update_available": $update_available
}
EOF

    return 0
}

# Main logic
UPDATE_AVAILABLE="false"
CACHE_EXISTS=false
[ -f "$UPDATE_CACHE" ] && CACHE_EXISTS=true

if cache_is_valid; then
    # Use cached result
    UPDATE_AVAILABLE=$(read_cache)
elif [ "$CACHE_EXISTS" = "false" ]; then
    # No cache at all - do initial check regardless of idle status
    # This ensures first-run users see the update indicator
    refresh_cache 2>/dev/null || true
    UPDATE_AVAILABLE=$(read_cache)
else
    # Cache exists but is stale - only refresh when idle to avoid blocking
    if [ "$IS_IDLE" = "true" ]; then
        refresh_cache 2>/dev/null || true
    fi
    # Read whatever is in cache (may be old or just updated)
    UPDATE_AVAILABLE=$(read_cache)
fi

# Output indicator if update available
if [ "$UPDATE_AVAILABLE" = "true" ]; then
    printf '%b' "${CYAN}⬆${RESET}"
    echo ""
fi
