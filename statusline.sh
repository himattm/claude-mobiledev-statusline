#!/bin/bash
# Claude Code status line script for Android & iOS development
# Features: context bar, lines changed, multi-device with versions, MCP status

# ANSI color codes
CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
MAGENTA='\033[35m'
BLUE='\033[34m'
GRAY='\033[90m'
DIM='\033[2m'
RESET='\033[0m'

# Unicode symbols
ANDROID_ICON_ACTIVE='⬢'    # Filled hexagon - targeted by ANDROID_SERIAL
ANDROID_ICON_INACTIVE='⬡'  # Hollow hexagon - not targeted
IOS_ICON=$(printf '\xEF\xA3\xBF')  # Apple logo (U+F8FF) - Option+Shift+K on Mac, only renders on Apple devices
GRADLE_ICON='𓃰'
XCODE_ICON='⚒'
DEVICE_DIVIDER=' · '

# Cache for config (read once per session)
CONFIG_CACHE="/tmp/claude-statusline-config"

# Cache settings for app versions (expensive queries)
ANDROID_VERSION_CACHE="/tmp/claude-statusline-android-versions"
IOS_VERSION_CACHE="/tmp/claude-statusline-ios-versions"
APP_VERSION_CACHE_MAX_AGE=30  # seconds


# Default section order (gradle/xcode before devices since devices go on new line)
DEFAULT_SECTIONS='["dir", "model", "context", "linesChanged", "cost", "git", "gradle", "xcode", "mcp", "devices"]'

# Load config from .claude-statusline.json (cached per session)
# Precedence: local override > per-repo config > global config > defaults
get_config() {
    local cache_key=$(echo "$PROJECT_DIR" | md5 -q)
    local cache_file="${CONFIG_CACHE}-${cache_key}"

    if [ -f "$cache_file" ]; then
        cat "$cache_file"
        return
    fi

    local config="{}"
    local global_config="{}"

    # Load global defaults first
    if [ -f "$HOME/.claude/statusline-config.json" ]; then
        global_config=$(cat "$HOME/.claude/statusline-config.json")
    fi

    # Per-repo overrides global
    if [ -f "${PROJECT_DIR}/.claude-statusline.json" ]; then
        local repo_config=$(cat "${PROJECT_DIR}/.claude-statusline.json")
        # Merge: repo config takes precedence
        config=$(echo "$global_config $repo_config" | jq -s '.[0] * .[1]')
    elif [ -f "${PROJECT_DIR}/.claude-icon" ]; then
        # Backwards compatibility: convert .claude-icon to config
        local icon=$(head -1 "${PROJECT_DIR}/.claude-icon" | tr -d '\n')
        config=$(echo "$global_config" | jq --arg icon "$icon" '. + {icon: $icon}')
    else
        config="$global_config"
    fi

    # Local override takes highest precedence (not committed to git)
    if [ -f "${PROJECT_DIR}/.claude-statusline.local.json" ]; then
        local local_config=$(cat "${PROJECT_DIR}/.claude-statusline.local.json")
        config=$(echo "$config $local_config" | jq -s '.[0] * .[1]')
    fi

    # Fallback to empty object if no config found
    if [ -z "$config" ] || [ "$config" = "{}" ]; then
        config="{}"
    fi

    echo "$config" > "$cache_file"
    echo "$config"
}

# Get config value with default
config_get() {
    local key=$1
    local default=$2
    local config=$(get_config)
    local value=$(echo "$config" | jq -r "$key // empty")
    if [ -z "$value" ] || [ "$value" = "null" ]; then
        echo "$default"
    else
        echo "$value"
    fi
}

# Estimated system overhead (system prompt, tools, MCP, agents, memory)
# Adjust this based on your setup - check /context for actual values
SYSTEM_OVERHEAD_TOKENS=23000

# Read and store full JSON input for later use
INPUT=$(cat)

# Debug: uncomment to save raw JSON for troubleshooting
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')
# echo "$INPUT" > "/tmp/statusline-debug-${SESSION_ID}.json"

# Parse all JSON fields in a single jq call
# Use tab delimiter explicitly to handle spaces in model names (e.g., "Opus 4.5")
IFS=$'\t' read -r CURRENT_DIR MODEL PCT COST LINES_ADDED LINES_REMOVED PROJECT_DIR < <(echo "$INPUT" | jq -r --argjson overhead "$SYSTEM_OVERHEAD_TOKENS" '[
    (.workspace.current_dir // ""),
    .model.display_name,
    (if .context_window.current_usage then
        # Add estimated overhead (system prompt, tools, MCP, agents, memory)
        (((.context_window.current_usage.input_tokens + .context_window.current_usage.output_tokens + .context_window.current_usage.cache_creation_input_tokens + .context_window.current_usage.cache_read_input_tokens + $overhead) * 100 / .context_window.context_window_size) | floor)
    else 0 end),
    (.cost.total_cost_usd // 0 | . * 100 | floor / 100),
    (.cost.total_lines_added // 0),
    (.cost.total_lines_removed // 0),
    (.workspace.project_dir // "")
] | @tsv')

# Get project name (basename of project_dir, where Claude was started)
PROJECT_NAME=$(basename "$PROJECT_DIR")

# Calculate subdirectory path if current_dir differs from project_dir
SUBDIR=""
if [ -n "$CURRENT_DIR" ] && [ -n "$PROJECT_DIR" ] && [ "$CURRENT_DIR" != "$PROJECT_DIR" ]; then
    # Get relative path from project dir to current dir
    SUBDIR="${CURRENT_DIR#$PROJECT_DIR}"
fi

# Abbreviate project name for display when in subdirectory
abbreviate_name() {
    local name="$1"
    local len=${#name}

    if [ "$len" -le 6 ]; then
        echo "$name"
        return
    fi

    # Check if name contains hyphens
    if [[ "$name" == *-* ]]; then
        # Take first letter of each hyphen-separated segment
        echo "$name" | sed 's/-/ /g' | awk '{for(i=1;i<=NF;i++) printf substr($i,1,1)}'
    else
        # Take first 3 characters
        echo "${name:0:3}"
    fi
}

# Compact subdirectory path: show last 3 dirs, abbreviate all but the last
# e.g., /foo/bar/baz/qux/final -> b/q/final
compact_subdir() {
    local subdir="$1"
    # Remove leading slash
    subdir="${subdir#/}"

    # Split into array
    IFS='/' read -ra parts <<< "$subdir"
    local count=${#parts[@]}

    if [ "$count" -le 1 ]; then
        # Single dir, just return with leading slash
        echo "/${subdir}"
        return
    fi

    # Take last 3 dirs max
    local start=0
    if [ "$count" -gt 3 ]; then
        start=$((count - 3))
    fi

    local result=""
    for ((i=start; i<count; i++)); do
        local part="${parts[$i]}"
        if [ $i -lt $((count - 1)) ]; then
            # Not the last part - abbreviate to first char
            result+="/${part:0:1}"
        else
            # Last part - show full name
            result+="/${part}"
        fi
    done

    echo "$result"
}

# Function to generate visual context bar with color
# Shows: █ used, ░ free, ▒ auto-compact buffer
get_context_bar() {
    local pct=${1:-0}
    local width=10
    local buffer_pct=22  # Auto-compact buffer is ~22.5% (45k/200k)
    local usable_pct=$((100 - buffer_pct))  # 78% usable

    # Calculate blocks for each segment based on percentage
    local filled=$(( (pct * width + 50) / 100 ))  # Round to nearest
    if [ "$filled" -gt "$width" ]; then filled=$width; fi

    # How many blocks are in the usable zone vs buffer zone
    local usable_blocks=$(( (usable_pct * width + 50) / 100 ))  # ~8 blocks
    local buffer_blocks=$((width - usable_blocks))              # ~2 blocks

    # Split filled between usable and buffer zones
    local filled_usable=$filled
    local filled_buffer=0
    if [ "$filled" -gt "$usable_blocks" ]; then
        filled_usable=$usable_blocks
        filled_buffer=$((filled - usable_blocks))
    fi

    # Free space in usable zone
    local free=$((usable_blocks - filled_usable))

    # Remaining buffer (not yet filled)
    local buffer_free=$((buffer_blocks - filled_buffer))

    # Build bar: [████░░▒▒] = filled_usable, free, filled_buffer, buffer_free
    local bar="["
    for ((i=0; i<filled_usable; i++)); do bar+="█"; done
    for ((i=0; i<free; i++)); do bar+="░"; done
    for ((i=0; i<filled_buffer; i++)); do bar+="█"; done
    for ((i=0; i<buffer_free; i++)); do bar+="▒"; done
    bar+="]"

    # Color based on usage level
    local color
    if [ "$pct" -ge "$usable_pct" ]; then
        color="$RED"      # Into buffer zone
    elif [ "$pct" -ge 50 ]; then
        color="$YELLOW"
    else
        color=""  # normal/white text
    fi

    echo "${color}${bar} ${pct}%${RESET}"
}

# Function to get git info with register branch indicator
get_git_info() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo ""
        return
    fi

    BRANCH=$(git branch --show-current 2>/dev/null)
    if [ -z "$BRANCH" ]; then
        BRANCH=$(git rev-parse --short HEAD 2>/dev/null)
    fi

    # Use git status --porcelain for efficiency (single command)
    STATUS=$(git status --porcelain 2>/dev/null | head -20)
    DIRTY=""
    if echo "$STATUS" | grep -q "^[MADRC]"; then
        DIRTY="*"  # staged changes
    fi
    if echo "$STATUS" | grep -q "^.[MADRC]"; then
        DIRTY="${DIRTY}*"  # unstaged changes
    fi
    if echo "$STATUS" | grep -q "^??"; then
        DIRTY="${DIRTY}+"  # untracked
    fi

    echo "${BRANCH}${DIRTY}"
}

# Function to get git diff stats (lines added/removed since last commit)
get_git_diff_stats() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "0 0"
        return
    fi

    # Get stats for both staged and unstaged changes (with timeout to avoid blocking)
    local stats=$(timeout 1 git diff --numstat HEAD 2>/dev/null | awk '{add+=$1; del+=$2} END {print add+0, del+0}')
    echo "${stats:-0 0}"
}

# Get version for a specific package
get_package_version() {
    local serial=$1
    local pkg=$2
    timeout 2 adb -s "$serial" shell dumpsys package "$pkg" 2>/dev/null | grep "versionName=" | head -1 | sed 's/.*versionName=//' | tr -d '[:space:]'
}

# Find packages matching a glob pattern
find_matching_packages() {
    local serial=$1
    local pattern=$2
    # Convert glob to regex: com.app.* -> ^com\.app\..*$
    local regex=$(echo "$pattern" | sed 's/\./\\./g' | sed 's/\*/.*/g')
    timeout 2 adb -s "$serial" shell pm list packages 2>/dev/null | sed 's/package://' | grep -E "^${regex}$"
}

# Function to get app version for a single Android device
# Uses packages from config, supports glob patterns
# Returns: version if found, "--" if packages configured but not found, empty if no packages configured
get_android_app_version() {
    local serial=$1
    local packages_json=$(config_get '.android.packages' '[]')
    local packages=$(echo "$packages_json" | jq -r '.[]' 2>/dev/null)

    # If no packages configured, return empty (don't show version)
    if [ -z "$packages" ]; then
        return
    fi

    for pattern in $packages; do
        if [[ "$pattern" == *"*"* ]]; then
            # Glob pattern - find matching packages
            local matches=$(find_matching_packages "$serial" "$pattern")
            for pkg in $matches; do
                local ver=$(get_package_version "$serial" "$pkg")
                if [ -n "$ver" ]; then
                    echo "$ver"
                    return
                fi
            done
        else
            # Exact package name
            local ver=$(get_package_version "$serial" "$pattern")
            if [ -n "$ver" ]; then
                echo "$ver"
                return
            fi
        fi
    done
    # Packages configured but not found
    echo "--"
}

# Function to refresh Android app version cache in background
refresh_android_version_cache() {
    local serials="$1"
    local versions=""
    local serial_count=$(echo "$serials" | wc -w | tr -d ' ')

    for serial in $serials; do
        local ver=$(get_android_app_version "$serial")
        # Use filled hexagon for targeted device, hollow for others
        # If only one device, treat it as targeted by default
        local icon="$ANDROID_ICON_INACTIVE"
        if [ "$serial" = "$ANDROID_SERIAL" ] || [ "$serial_count" -eq 1 ]; then
            icon="$ANDROID_ICON_ACTIVE"
        fi
        # Only show :version if version is available
        local device_info="${icon} ${serial}"
        if [ -n "$ver" ]; then
            device_info="${device_info}:${ver}"
        fi
        if [ -n "$versions" ]; then
            versions="${versions}${DEVICE_DIVIDER}${device_info}"
        else
            versions="${device_info}"
        fi
    done

    echo "$versions" > "$ANDROID_VERSION_CACHE"
}

# Function to get Android app versions (with caching)
get_android_versions() {
    local serials="$1"

    # Check if cache exists and is fresh
    if [ -f "$ANDROID_VERSION_CACHE" ]; then
        local cache_age=$(($(date +%s) - $(stat -f %m "$ANDROID_VERSION_CACHE" 2>/dev/null || echo 0)))
        if [ "$cache_age" -lt "$APP_VERSION_CACHE_MAX_AGE" ]; then
            cat "$ANDROID_VERSION_CACHE"
            return
        fi
    fi

    # Cache is stale or missing
    if [ -f "$ANDROID_VERSION_CACHE" ]; then
        cat "$ANDROID_VERSION_CACHE"
        if ! pgrep -f "statusline.*android.*refresh" > /dev/null 2>&1; then
            (refresh_android_version_cache "$serials") &
        fi
    else
        refresh_android_version_cache "$serials"
        cat "$ANDROID_VERSION_CACHE" 2>/dev/null || echo "--"
    fi
}

# Get iOS app version for a simulator (no caching - called by refresh function)
# Returns: version if found, "--" if bundleIds configured but not found, empty if no bundleIds configured
get_ios_app_version() {
    local udid=$1
    local bundle_ids_json=$(config_get '.ios.bundleIds' '[]')
    local bundle_ids=$(echo "$bundle_ids_json" | jq -r '.[]' 2>/dev/null)

    # If no bundleIds configured, return empty (don't show version)
    if [ -z "$bundle_ids" ]; then
        return
    fi

    # Get list of installed apps (JSON format)
    local apps_json=$(xcrun simctl listapps "$udid" 2>/dev/null | plutil -convert json -o - -)

    for pattern in $bundle_ids; do
        if [[ "$pattern" == *"*"* ]]; then
            # Glob pattern - convert to regex and search
            local regex=$(echo "$pattern" | sed 's/\./\\./g' | sed 's/\*/.*/g')
            local matching_ids=$(echo "$apps_json" | jq -r 'keys[]' 2>/dev/null | grep -E "^${regex}$")
            for bid in $matching_ids; do
                local ver=$(echo "$apps_json" | jq -r --arg bid "$bid" '.[$bid].CFBundleShortVersionString // .[$bid].CFBundleVersion // empty' 2>/dev/null)
                if [ -n "$ver" ]; then
                    echo "$ver"
                    return
                fi
            done
        else
            # Exact bundle ID
            local ver=$(echo "$apps_json" | jq -r --arg bid "$pattern" '.[$bid].CFBundleShortVersionString // .[$bid].CFBundleVersion // empty' 2>/dev/null)
            if [ -n "$ver" ]; then
                echo "$ver"
                return
            fi
        fi
    done
    # bundleIds configured but not found
    echo "--"
}

# Shorten simulator names for compact display
shorten_simulator_name() {
    local name="$1"
    # "(10th generation)" → "(10gen)"
    name=$(echo "$name" | sed -E 's/\(([0-9]+)(st|nd|rd|th) generation\)/(\1gen)/g')
    # "(12.9-inch)" → "12.9" or remove
    name=$(echo "$name" | sed -E 's/ ?\(([0-9.]+)-inch\)/ \1"/g')
    # "iPad Pro 12.9" (6gen)" → "iPad Pro 12.9(6gen)"
    name=$(echo "$name" | sed 's/" (/"(/g')
    # Clean up extra spaces
    name=$(echo "$name" | sed 's/  */ /g' | sed 's/ *$//')
    echo "$name"
}

# Build iOS simulator info string (no caching - called by refresh function)
build_ios_simulators_info() {
    local sims=$(xcrun simctl list devices booted 2>/dev/null | grep -E "^\s+.+\([A-F0-9-]+\)" | sed 's/^[[:space:]]*//' | sed 's/ (Booted)//')
    if [ -n "$sims" ]; then
        echo "$sims" | while read -r line; do
            # Get device name (everything before the UUID in parentheses)
            local name=$(echo "$line" | sed 's/ ([A-F0-9-]*)$//')
            name=$(shorten_simulator_name "$name")
            # Get UDID (inside parentheses)
            local udid=$(echo "$line" | sed 's/.*(\([A-F0-9-]*\))$/\1/')

            # Get app version if bundleIds configured
            local ver=$(get_ios_app_version "$udid")
            if [ -n "$ver" ]; then
                echo "${IOS_ICON} ${name}:${ver}"
            else
                echo "${IOS_ICON} ${name}"
            fi
        done | tr '\n' '|' | sed 's/|$//; s/|/ · /g'
    fi
}

# Function to refresh iOS version cache in background
refresh_ios_version_cache() {
    local ios_info=$(build_ios_simulators_info)
    echo "$ios_info" > "$IOS_VERSION_CACHE"
}

# Get iOS simulators (with caching)
get_ios_simulators() {
    # Check if cache exists and is fresh
    if [ -f "$IOS_VERSION_CACHE" ]; then
        local cache_age=$(($(date +%s) - $(stat -f %m "$IOS_VERSION_CACHE" 2>/dev/null || echo 0)))
        if [ "$cache_age" -lt "$APP_VERSION_CACHE_MAX_AGE" ]; then
            cat "$IOS_VERSION_CACHE"
            return
        fi
    fi

    # Cache is stale or missing
    if [ -f "$IOS_VERSION_CACHE" ]; then
        cat "$IOS_VERSION_CACHE"
        if ! pgrep -f "statusline.*ios.*refresh" > /dev/null 2>&1; then
            (refresh_ios_version_cache) &
        fi
    else
        refresh_ios_version_cache
        cat "$IOS_VERSION_CACHE" 2>/dev/null
    fi
}

# Get iOS physical devices
get_ios_physical_devices() {
    # Use xcrun xctrace to list physical devices
    local devices=$(xcrun xctrace list devices 2>/dev/null | grep -v "Simulator" | grep -v "^==" | grep -v "^$" | head -10)
    if [ -n "$devices" ]; then
        echo "$devices" | while read -r line; do
            # Extract device name (first part before parentheses)
            local name=$(echo "$line" | sed 's/ (.*$//')
            if [ -n "$name" ] && [ "$name" != "Devices" ]; then
                echo "${IOS_ICON} ${name}"
            fi
        done | grep -v "^$" | tr '\n' '|' | sed 's/|$//; s/|/ · /g'
    fi
}

# Get all device info (Android + iOS)
get_device_info() {
    local output=""
    local android_count=0
    local ios_count=0

    # Get Android devices
    local android_lines=$(timeout 1 adb devices 2>/dev/null | tail -n +2 | grep -v "^$" | grep "device$")
    local android_serials=$(echo "$android_lines" | cut -f1 | grep -v "^$" | tr '\n' ' ' | sed 's/ $//')
    if [ -n "$android_serials" ]; then
        android_count=$(echo "$android_serials" | wc -w | tr -d ' ')
    fi

    # Get iOS simulators
    local ios_sims=$(get_ios_simulators)
    local ios_sim_count=0
    if [ -n "$ios_sims" ]; then
        ios_sim_count=$(echo "$ios_sims" | sed 's/ · /\n/g' | wc -l | tr -d ' ')
    fi

    # Get iOS physical devices (skip for now as it's slower, can be enabled later)
    # local ios_physical=$(get_ios_physical_devices)

    ios_count=$ios_sim_count

    local total_count=$((android_count + ios_count))

    if [ "$total_count" -eq 0 ]; then
        return
    fi

    # Build device list
    local device_list=""

    # Add Android devices with versions (filled hexagon = targeted, hollow = not)
    if [ "$android_count" -gt 0 ]; then
        device_list=$(get_android_versions "$android_serials")
    fi

    # Add iOS devices
    if [ -n "$ios_sims" ]; then
        if [ -n "$device_list" ]; then
            device_list="${device_list}${DEVICE_DIVIDER}${ios_sims}"
        else
            device_list="$ios_sims"
        fi
    fi

    echo "${device_list}"
}

# Check Gradle daemon status (only in Gradle projects)
get_gradle_status() {
    # Only check in Gradle projects
    if [ ! -f "${PROJECT_DIR}/build.gradle" ] && \
       [ ! -f "${PROJECT_DIR}/build.gradle.kts" ] && \
       [ ! -f "${PROJECT_DIR}/settings.gradle" ] && \
       [ ! -f "${PROJECT_DIR}/settings.gradle.kts" ]; then
        return
    fi

    # Count running Gradle daemons (fast pgrep check)
    local daemon_count=$(pgrep -f "GradleDaemon" 2>/dev/null | wc -l | tr -d ' ')

    if [ "$daemon_count" -gt 0 ]; then
        echo "${GRADLE_ICON}${daemon_count}"  # daemon(s) running
    else
        echo "${GRADLE_ICON}?"  # no daemon = cold start
    fi
}

# Check Xcode build status (only in Xcode projects)
get_xcode_status() {
    # Only check in Xcode projects
    if ! ls "${PROJECT_DIR}"/*.xcodeproj >/dev/null 2>&1 && \
       ! ls "${PROJECT_DIR}"/*.xcworkspace >/dev/null 2>&1; then
        return
    fi

    # Count running xcodebuild processes
    local build_count=$(pgrep -f "xcodebuild" 2>/dev/null | wc -l | tr -d ' ')

    if [ "$build_count" -gt 0 ]; then
        echo "${XCODE_ICON}${build_count}"  # build(s) running
    else
        echo "${XCODE_ICON}"  # no builds running, but project exists
    fi
}

# Check for MCP configuration
get_mcp_status() {
    # Check global MCP servers in ~/.claude.json
    if [ -f "$HOME/.claude.json" ]; then
        local global_mcp=$(jq -r '.mcpServers // empty | keys | length' "$HOME/.claude.json" 2>/dev/null)
        if [ -n "$global_mcp" ] && [ "$global_mcp" -gt 0 ]; then
            echo "mcp:${global_mcp}"
            return
        fi
    fi

    # Check project-level .mcp.json
    if [ -f "${PROJECT_DIR}/.mcp.json" ]; then
        local proj_mcp=$(jq -r '.mcpServers // empty | keys | length' "${PROJECT_DIR}/.mcp.json" 2>/dev/null)
        if [ -n "$proj_mcp" ] && [ "$proj_mcp" -gt 0 ]; then
            echo "mcp:${proj_mcp}"
            return
        fi
    fi
}

# Get all dynamic info
CONTEXT_BAR=$(get_context_bar "$PCT")
GIT_INFO=$(get_git_info)
GIT_DIFF_STATS=$(get_git_diff_stats)
GIT_LINES_ADDED=$(echo "$GIT_DIFF_STATS" | awk '{print $1}')
GIT_LINES_REMOVED=$(echo "$GIT_DIFF_STATS" | awk '{print $2}')
DEVICE_INFO=$(get_device_info)
GRADLE_STATUS=$(get_gradle_status)
XCODE_STATUS=$(get_xcode_status)
MCP_STATUS=$(get_mcp_status)

# Build colorized output based on config sections order
OUTPUT=""
SEPARATOR=""

# Get icon from config
DIR_ICON=$(config_get '.icon' '')
if [ -n "$DIR_ICON" ]; then
    DIR_ICON="${DIR_ICON} "
fi

# Get sections order from config (or use defaults)
SECTIONS_JSON=$(config_get '.sections' "$DEFAULT_SECTIONS")

# Check if sections is array of arrays (multi-line) or single array
IS_MULTILINE=$(echo "$SECTIONS_JSON" | jq -r 'if type == "array" and (.[0] | type) == "array" then "true" else "false" end' 2>/dev/null)

# Function to build output for a single line of sections
build_line() {
    local sections_for_line="$1"
    local line_output=""
    local sep=""

    for section in $sections_for_line; do
        case "$section" in
            dir)
                # Show project name and intermediate dirs in dim cyan, final dir in bright cyan
                if [ -n "$SUBDIR" ]; then
                    ABBREV_NAME=$(abbreviate_name "$PROJECT_NAME")
                    COMPACT_SUBDIR=$(compact_subdir "$SUBDIR")
                    # Split: everything up to last / is dim, final segment is bright
                    SUBDIR_PREFIX="${COMPACT_SUBDIR%/*}"
                    SUBDIR_FINAL="${COMPACT_SUBDIR##*/}"
                    if [ "$SUBDIR_PREFIX" != "$COMPACT_SUBDIR" ]; then
                        # Has intermediate dirs
                        line_output+="${sep}${DIR_ICON}${DIM}${CYAN}${ABBREV_NAME}${SUBDIR_PREFIX}/${RESET}${CYAN}${SUBDIR_FINAL}${RESET}"
                    else
                        # Single subdir (COMPACT_SUBDIR is like "/screenshots")
                        line_output+="${sep}${DIR_ICON}${DIM}${CYAN}${ABBREV_NAME}/${RESET}${CYAN}${SUBDIR_FINAL}${RESET}"
                    fi
                else
                    line_output+="${sep}${DIR_ICON}${CYAN}${PROJECT_NAME}${RESET}"
                fi
                sep=" ${DIM}·${RESET} "
                ;;
            model)
                line_output+="${sep}${MAGENTA}${MODEL}${RESET}"
                sep=" ${DIM}·${RESET} "
                ;;
            context)
                line_output+="${sep}${CONTEXT_BAR}"
                sep=" ${DIM}·${RESET} "
                ;;
            linesChanged)
                # Use git diff stats (net change since last commit) instead of session totals
                line_output+="${sep}${GREEN}+${GIT_LINES_ADDED}${RESET} ${RED}-${GIT_LINES_REMOVED}${RESET}"
                sep=" ${DIM}·${RESET} "
                ;;
            cost)
                line_output+="${sep}${GRAY}\$${COST}${RESET}"
                sep=" ${DIM}·${RESET} "
                ;;
            git)
                if [ -n "$GIT_INFO" ]; then
                    line_output+="${sep}${YELLOW}${GIT_INFO}${RESET}"
                    sep=" ${DIM}·${RESET} "
                fi
                ;;
            devices)
                # Show connected devices (versions shown if packages/bundleIds configured)
                if [ -n "$DEVICE_INFO" ]; then
                    line_output+="${sep}${BLUE}${DEVICE_INFO}${RESET}"
                    sep=" ${DIM}·${RESET} "
                fi
                ;;
            gradle)
                if [ -n "$GRADLE_STATUS" ]; then
                    line_output+="${sep}${GREEN}${GRADLE_STATUS}${RESET}"
                    sep=" ${DIM}·${RESET} "
                fi
                ;;
            xcode)
                if [ -n "$XCODE_STATUS" ]; then
                    line_output+="${sep}${CYAN}${XCODE_STATUS}${RESET}"
                    sep=" ${DIM}·${RESET} "
                fi
                ;;
            mcp)
                if [ -n "$MCP_STATUS" ]; then
                    line_output+="${sep}${GRAY}${MCP_STATUS}${RESET}"
                    sep=" ${DIM}·${RESET} "
                fi
                ;;
        esac
    done

    echo "$line_output"
}

# Build output based on single or multi-line config
if [ "$IS_MULTILINE" = "true" ]; then
    # Multi-line: sections is array of arrays
    LINE_COUNT=$(echo "$SECTIONS_JSON" | jq -r 'length' 2>/dev/null)
    for ((i=0; i<LINE_COUNT; i++)); do
        SECTIONS_FOR_LINE=$(echo "$SECTIONS_JSON" | jq -r ".[$i][]" 2>/dev/null)
        LINE_OUTPUT=$(build_line "$SECTIONS_FOR_LINE")
        if [ -n "$LINE_OUTPUT" ]; then
            if [ -n "$OUTPUT" ]; then
                OUTPUT+="\n"
            fi
            OUTPUT+="$LINE_OUTPUT"
        fi
    done
else
    # Single line: sections is flat array
    SECTIONS=$(echo "$SECTIONS_JSON" | jq -r '.[]' 2>/dev/null)
    OUTPUT=$(build_line "$SECTIONS")
fi

echo -e "$OUTPUT"
