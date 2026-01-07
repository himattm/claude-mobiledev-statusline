#!/bin/bash
# Prism - A fast, customizable status line for Claude Code
# https://github.com/himattm/prism

VERSION="0.1.0"

# CLI mode: handle commands when run directly (not as status line)
if [ -n "$1" ]; then
    case "$1" in
        init)
            mkdir -p .claude
            if [ -f ".claude/prism.json" ]; then
                echo "Error: .claude/prism.json already exists"
                exit 1
            fi
            cat > .claude/prism.json << 'EOF'
{
  "icon": "💎",
  "sections": ["dir", "model", "context", "cost", "git"]
}
EOF
            echo "Created .claude/prism.json"
            echo "Tip: Create .claude/prism.local.json for personal overrides (gitignored)"
            ;;
        init-global)
            mkdir -p ~/.claude
            if [ -f ~/.claude/prism-config.json ]; then
                echo "Error: ~/.claude/prism-config.json already exists"
                exit 1
            fi
            cat > ~/.claude/prism-config.json << 'EOF'
{
  "sections": ["dir", "model", "context", "cost", "git"]
}
EOF
            echo "Created ~/.claude/prism-config.json"
            ;;
        version|--version|-v)
            echo "Prism $VERSION"
            ;;
        plugin|plugins)
            # Plugin management commands
            PLUGIN_SUBCOMMAND="${2:-list}"
            PLUGIN_DIR="$HOME/.claude/prism-plugins"
            mkdir -p "$PLUGIN_DIR"

            # Helper: Parse plugin header metadata
            parse_plugin_meta() {
                local file="$1"
                local key="$2"
                grep "^# @${key} " "$file" 2>/dev/null | sed "s/^# @${key} //" | head -1
            }

            # Helper: Compare semver versions (returns 0 if $1 < $2)
            version_lt() {
                [ "$1" = "$2" ] && return 1
                local IFS=.
                local i v1=($1) v2=($2)
                for ((i=0; i<${#v1[@]} || i<${#v2[@]}; i++)); do
                    local n1=${v1[i]:-0} n2=${v2[i]:-0}
                    n1=$(echo "$n1" | sed 's/[^0-9].*//')
                    n2=$(echo "$n2" | sed 's/[^0-9].*//')
                    [ "${n1:-0}" -lt "${n2:-0}" ] && return 0
                    [ "${n1:-0}" -gt "${n2:-0}" ] && return 1
                done
                return 1
            }

            case "$PLUGIN_SUBCOMMAND" in
                list|ls)
                    # List installed plugins with version info
                    echo "Installed plugins:"
                    echo ""
                    printf "  %-12s %-10s %-20s %s\n" "NAME" "VERSION" "AUTHOR" "SOURCE"
                    printf "  %-12s %-10s %-20s %s\n" "----" "-------" "------" "------"

                    found=0
                    for plugin in "$PLUGIN_DIR"/prism-plugin-*; do
                        [ -x "$plugin" ] || continue
                        name=$(parse_plugin_meta "$plugin" "name")
                        [ -z "$name" ] && name=$(basename "$plugin" | sed 's/prism-plugin-//;s/\..*//')
                        version=$(parse_plugin_meta "$plugin" "version")
                        [ -z "$version" ] && version="?"
                        author=$(parse_plugin_meta "$plugin" "author")
                        [ -z "$author" ] && author="-"
                        source=$(parse_plugin_meta "$plugin" "source")
                        [ -z "$source" ] && source="-"
                        printf "  %-12s %-10s %-20s %s\n" "$name" "$version" "$author" "$source"
                        found=1
                    done

                    if [ "$found" -eq 0 ]; then
                        echo "  (no plugins installed)"
                    fi
                    echo ""
                    echo "Plugin directory: $PLUGIN_DIR"
                    ;;

                add|install)
                    # Install a plugin from URL
                    URL="$3"
                    if [ -z "$URL" ]; then
                        echo "Usage: prism plugin add <github-url|raw-url>"
                        echo ""
                        echo "Examples:"
                        echo "  prism plugin add https://github.com/user/prism-plugin-weather"
                        echo "  prism plugin add https://raw.githubusercontent.com/user/repo/main/prism-plugin-weather.sh"
                        exit 1
                    fi

                    # Detect URL type and normalize
                    if [[ "$URL" =~ ^https://github.com/([^/]+)/([^/]+)$ ]]; then
                        # GitHub repo URL - fetch from main branch
                        OWNER="${BASH_REMATCH[1]}"
                        REPO="${BASH_REMATCH[2]}"
                        # Try common plugin file locations
                        RAW_URL="https://raw.githubusercontent.com/$OWNER/$REPO/main/prism-plugin-${REPO#prism-plugin-}.sh"
                        # Also try just the repo name
                        if ! curl -fsSL --max-time 5 "$RAW_URL" >/dev/null 2>&1; then
                            RAW_URL="https://raw.githubusercontent.com/$OWNER/$REPO/main/${REPO}.sh"
                        fi
                    elif [[ "$URL" =~ ^https://raw.githubusercontent.com/ ]] || [[ "$URL" =~ \.sh$ ]]; then
                        # Direct raw URL
                        RAW_URL="$URL"
                    else
                        echo "Error: Unrecognized URL format"
                        echo "Provide a GitHub repo URL or direct raw URL to a .sh file"
                        exit 1
                    fi

                    echo "Fetching plugin from: $RAW_URL"

                    # Download to temp file first
                    TEMP_FILE=$(mktemp)
                    if ! curl -fsSL --max-time 10 "$RAW_URL" -o "$TEMP_FILE" 2>/dev/null; then
                        rm -f "$TEMP_FILE"
                        echo "Error: Failed to download plugin"
                        exit 1
                    fi

                    # Validate it's a prism plugin
                    if ! grep -q "@prism-plugin" "$TEMP_FILE"; then
                        rm -f "$TEMP_FILE"
                        echo "Error: File doesn't appear to be a Prism plugin (missing @prism-plugin header)"
                        exit 1
                    fi

                    # Extract plugin name
                    PLUGIN_NAME=$(parse_plugin_meta "$TEMP_FILE" "name")
                    if [ -z "$PLUGIN_NAME" ]; then
                        PLUGIN_NAME=$(basename "$RAW_URL" .sh | sed 's/prism-plugin-//')
                    fi

                    DEST_FILE="$PLUGIN_DIR/prism-plugin-${PLUGIN_NAME}.sh"

                    # Check if already installed
                    if [ -f "$DEST_FILE" ]; then
                        OLD_VERSION=$(parse_plugin_meta "$DEST_FILE" "version")
                        NEW_VERSION=$(parse_plugin_meta "$TEMP_FILE" "version")
                        echo "Plugin '$PLUGIN_NAME' already installed (version $OLD_VERSION)"
                        echo "New version: $NEW_VERSION"
                        read -p "Overwrite? [y/N] " -n 1 -r
                        echo ""
                        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                            rm -f "$TEMP_FILE"
                            echo "Cancelled."
                            exit 0
                        fi
                    fi

                    # Install
                    mv "$TEMP_FILE" "$DEST_FILE"
                    chmod +x "$DEST_FILE"

                    INSTALLED_VERSION=$(parse_plugin_meta "$DEST_FILE" "version")
                    echo "Installed: $PLUGIN_NAME v${INSTALLED_VERSION:-unknown}"
                    ;;

                check-updates|check)
                    # Check all plugins for updates
                    echo "Checking for plugin updates..."
                    echo ""

                    updates_available=0
                    for plugin in "$PLUGIN_DIR"/prism-plugin-*; do
                        [ -x "$plugin" ] || continue
                        name=$(parse_plugin_meta "$plugin" "name")
                        [ -z "$name" ] && continue
                        local_version=$(parse_plugin_meta "$plugin" "version")
                        update_url=$(parse_plugin_meta "$plugin" "update-url")

                        if [ -z "$update_url" ]; then
                            printf "  %-12s %-10s (no update URL)\n" "$name" "$local_version"
                            continue
                        fi

                        # Fetch remote version
                        remote_content=$(curl -fsSL --max-time 5 "$update_url" 2>/dev/null)
                        if [ -z "$remote_content" ]; then
                            printf "  %-12s %-10s (fetch failed)\n" "$name" "$local_version"
                            continue
                        fi

                        remote_version=$(echo "$remote_content" | grep "^# @version " | sed 's/^# @version //' | head -1)

                        if [ -z "$remote_version" ]; then
                            printf "  %-12s %-10s (no remote version)\n" "$name" "$local_version"
                        elif version_lt "$local_version" "$remote_version"; then
                            printf "  %-12s %-10s -> %-10s ${YELLOW}(update available)${RESET}\n" "$name" "$local_version" "$remote_version"
                            updates_available=1
                        else
                            printf "  %-12s %-10s (up to date)\n" "$name" "$local_version"
                        fi
                    done

                    echo ""
                    if [ "$updates_available" -eq 1 ]; then
                        echo "Run 'prism plugin update <name>' or 'prism plugin update --all' to update."
                    else
                        echo "All plugins are up to date."
                    fi
                    ;;

                update|upgrade)
                    # Update a specific plugin or all plugins
                    TARGET="$3"
                    if [ -z "$TARGET" ]; then
                        echo "Usage: prism plugin update <plugin-name|--all>"
                        exit 1
                    fi

                    update_plugin() {
                        local plugin_path="$1"
                        local name=$(parse_plugin_meta "$plugin_path" "name")
                        local local_version=$(parse_plugin_meta "$plugin_path" "version")
                        local update_url=$(parse_plugin_meta "$plugin_path" "update-url")

                        if [ -z "$update_url" ]; then
                            echo "  $name: no update URL configured"
                            return 1
                        fi

                        echo "  $name: checking..."

                        TEMP_FILE=$(mktemp)
                        if ! curl -fsSL --max-time 10 "$update_url" -o "$TEMP_FILE" 2>/dev/null; then
                            rm -f "$TEMP_FILE"
                            echo "  $name: fetch failed"
                            return 1
                        fi

                        remote_version=$(parse_plugin_meta "$TEMP_FILE" "version")

                        if [ -z "$remote_version" ]; then
                            rm -f "$TEMP_FILE"
                            echo "  $name: no version in remote file"
                            return 1
                        fi

                        if version_lt "$local_version" "$remote_version"; then
                            mv "$TEMP_FILE" "$plugin_path"
                            chmod +x "$plugin_path"
                            echo "  $name: updated $local_version -> $remote_version"
                        else
                            rm -f "$TEMP_FILE"
                            echo "  $name: already up to date ($local_version)"
                        fi
                    }

                    if [ "$TARGET" = "--all" ] || [ "$TARGET" = "-a" ]; then
                        echo "Updating all plugins..."
                        for plugin in "$PLUGIN_DIR"/prism-plugin-*; do
                            [ -x "$plugin" ] || continue
                            update_plugin "$plugin"
                        done
                    else
                        PLUGIN_PATH="$PLUGIN_DIR/prism-plugin-${TARGET}.sh"
                        if [ ! -f "$PLUGIN_PATH" ]; then
                            echo "Error: Plugin '$TARGET' not found"
                            exit 1
                        fi
                        update_plugin "$PLUGIN_PATH"
                    fi
                    ;;

                remove|uninstall|rm)
                    # Remove a plugin
                    PLUGIN_NAME="$3"
                    if [ -z "$PLUGIN_NAME" ]; then
                        echo "Usage: prism plugin remove <plugin-name>"
                        exit 1
                    fi

                    PLUGIN_PATH="$PLUGIN_DIR/prism-plugin-${PLUGIN_NAME}.sh"
                    if [ ! -f "$PLUGIN_PATH" ]; then
                        echo "Error: Plugin '$PLUGIN_NAME' not found"
                        exit 1
                    fi

                    rm "$PLUGIN_PATH"
                    echo "Removed: $PLUGIN_NAME"
                    ;;

                *)
                    echo "Usage: prism plugin <command>"
                    echo ""
                    echo "Commands:"
                    echo "  list                    List installed plugins"
                    echo "  add <url>               Install a plugin from GitHub or raw URL"
                    echo "  check-updates           Check all plugins for updates"
                    echo "  update <name|--all>     Update a plugin or all plugins"
                    echo "  remove <name>           Remove a plugin"
                    echo ""
                    echo "Examples:"
                    echo "  prism plugin list"
                    echo "  prism plugin add https://github.com/user/prism-plugin-weather"
                    echo "  prism plugin check-updates"
                    echo "  prism plugin update git"
                    echo "  prism plugin update --all"
                    ;;
            esac
            ;;
        test-plugin)
            # Test a plugin with sample input
            plugin_name="$2"
            if [ -z "$plugin_name" ]; then
                echo "Usage: prism test-plugin <plugin-name>"
                echo "Example: prism test-plugin weather"
                exit 1
            fi

            PROJECT_DIR="${3:-.}"
            PROJECT_DIR=$(cd "$PROJECT_DIR" 2>/dev/null && pwd)

            # Find plugin
            plugin_path=""
            for dir in "${PROJECT_DIR}/.claude/prism-plugins" "$HOME/.claude/prism-plugins"; do
                for ext in ".sh" ".py" ""; do
                    if [ -x "$dir/prism-plugin-${plugin_name}${ext}" ]; then
                        plugin_path="$dir/prism-plugin-${plugin_name}${ext}"
                        break 2
                    fi
                done
            done

            if [ -z "$plugin_path" ]; then
                echo "Plugin not found: $plugin_name"
                exit 1
            fi

            echo "Testing plugin: $plugin_path"
            echo ""

            # Build sample input
            sample_input=$(cat << EOF
{
  "prism": {
    "version": "$VERSION",
    "project_dir": "$PROJECT_DIR",
    "current_dir": "$PROJECT_DIR",
    "session_id": "test-session",
    "is_idle": true
  },
  "session": {
    "model": "Test Model",
    "context_pct": 50,
    "cost_usd": 1.23,
    "lines_added": 100,
    "lines_removed": 50
  },
  "config": {
    "$plugin_name": {}
  },
  "colors": {
    "cyan": "\u001b[36m",
    "green": "\u001b[32m",
    "yellow": "\u001b[33m",
    "red": "\u001b[31m",
    "magenta": "\u001b[35m",
    "blue": "\u001b[34m",
    "gray": "\u001b[90m",
    "dim": "\u001b[2m",
    "reset": "\u001b[0m"
  }
}
EOF
)
            echo "Input JSON:"
            echo "$sample_input" | jq .
            echo ""
            echo "Output:"
            output=$(echo "$sample_input" | timeout 2 "$plugin_path" 2>&1)
            exit_code=$?
            echo -e "$output"
            echo ""
            echo "Exit code: $exit_code"
            ;;
        help|--help|-h)
            echo "Prism $VERSION - A fast, customizable status line for Claude Code"
            echo ""
            echo "Usage:"
            echo "  prism init                  Create .claude/prism.json in current directory"
            echo "  prism init-global           Create ~/.claude/prism-config.json"
            echo "  prism update                Check for Prism updates and install"
            echo "  prism check-update          Check for Prism updates (no install)"
            echo "  prism version               Show version"
            echo "  prism help                  Show this help"
            echo ""
            echo "Plugin commands:"
            echo "  prism plugin list           List installed plugins with versions"
            echo "  prism plugin add <url>      Install plugin from GitHub/URL"
            echo "  prism plugin check-updates  Check plugins for updates"
            echo "  prism plugin update <name>  Update a plugin (or --all)"
            echo "  prism plugin remove <name>  Remove a plugin"
            echo "  prism test-plugin <name>    Test a plugin with sample input"
            echo ""
            echo "Config precedence (highest to lowest):"
            echo "  1. .claude/prism.local.json    Your personal overrides (gitignored)"
            echo "  2. .claude/prism.json          Repo config (commit for your team)"
            echo "  3. ~/.claude/prism-config.json Global defaults"
            ;;
        check-update)
            echo "Checking for Prism updates..."
            REMOTE_VERSION=$(curl -fsSL --max-time 5 \
              "https://raw.githubusercontent.com/himattm/prism/main/prism.sh" \
              2>/dev/null | head -10 | grep '^VERSION=' | cut -d'"' -f2)

            if [ -z "$REMOTE_VERSION" ]; then
                echo "Error: Could not fetch version from GitHub"
                exit 1
            fi

            echo "Local version:  $VERSION"
            echo "Remote version: $REMOTE_VERSION"

            if [ "$VERSION" = "$REMOTE_VERSION" ]; then
                echo ""
                echo "You're on the latest version."
            else
                echo ""
                echo "Update available: $VERSION -> $REMOTE_VERSION"
                echo "Run 'prism update' to install."
            fi
            ;;
        update)
            echo "Checking for Prism updates..."
            REMOTE_VERSION=$(curl -fsSL --max-time 5 \
              "https://raw.githubusercontent.com/himattm/prism/main/prism.sh" \
              2>/dev/null | head -10 | grep '^VERSION=' | cut -d'"' -f2)

            if [ -z "$REMOTE_VERSION" ]; then
                echo "Error: Could not fetch version from GitHub"
                exit 1
            fi

            echo "Local version:  $VERSION"
            echo "Remote version: $REMOTE_VERSION"

            if [ "$VERSION" = "$REMOTE_VERSION" ]; then
                echo ""
                echo "You're already on the latest version!"
                exit 0
            fi

            echo ""
            echo "Update available: $VERSION -> $REMOTE_VERSION"
            echo ""
            read -p "Would you like to update? [y/N] " -n 1 -r
            echo ""

            if [[ $REPLY =~ ^[Yy]$ ]]; then
                echo "Updating Prism..."
                curl -fsSL https://raw.githubusercontent.com/himattm/prism/main/install.sh | bash
                # Clear the update cache after successful update
                rm -f /tmp/prism-update-check /tmp/prism-update-prompted
            else
                echo "Update cancelled."
            fi
            ;;
        *)
            echo "Unknown command: $1"
            echo "Run 'prism help' for usage"
            exit 1
            ;;
    esac
    exit 0
fi

# Status line mode: read JSON from stdin
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
CONFIG_CACHE="/tmp/prism-config"

# Cache settings for app versions (expensive queries)
ANDROID_VERSION_CACHE="/tmp/prism-android-versions"
IOS_VERSION_CACHE="/tmp/prism-ios-versions"
APP_VERSION_CACHE_MAX_AGE=30  # seconds

# Cache settings for git info (refreshed only when session is idle)
GIT_INFO_CACHE="/tmp/prism-git-info"
GIT_DIFF_CACHE="/tmp/prism-git-diff"
GIT_CACHE_MAX_AGE=2  # seconds


# Default section order (gradle/xcode before devices since devices go on new line)
# Note: "update" plugin is always run first (hardcoded) - not included in configurable sections
DEFAULT_SECTIONS='["dir", "model", "context", "linesChanged", "cost", "git", "gradle", "xcode", "mcp", "devices"]'

# Load config from .claude/prism.json (cached per session)
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
    if [ -f "$HOME/.claude/prism-config.json" ]; then
        global_config=$(cat "$HOME/.claude/prism-config.json")
    fi

    # Per-repo overrides global (check .claude/prism.json)
    if [ -f "${PROJECT_DIR}/.claude/prism.json" ]; then
        local repo_config=$(cat "${PROJECT_DIR}/.claude/prism.json")
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
    if [ -f "${PROJECT_DIR}/.claude/prism.local.json" ]; then
        local local_config=$(cat "${PROJECT_DIR}/.claude/prism.local.json")
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

# =============================================================================
# Plugin System
# =============================================================================

# Plugin directories (searched in order)
PLUGIN_DIR_USER="$HOME/.claude/prism-plugins"
PLUGIN_DIR_PROJECT=""  # Set after PROJECT_DIR is parsed
PLUGIN_CACHE="/tmp/prism-plugins"
PLUGIN_TIMEOUT_MS=500

# Discover plugins from all plugin directories
# Returns space-separated list of "name:path" pairs
discover_plugins() {
    local cache_key=$(echo "${PROJECT_DIR:-global}" | md5 -q)
    local cache_file="${PLUGIN_CACHE}-${cache_key}"

    # Return cached if exists
    if [ -f "$cache_file" ]; then
        cat "$cache_file"
        return
    fi

    local plugins=""
    local seen_names=""

    # Scan directories (project takes precedence over user)
    for dir in "${PROJECT_DIR}/.claude/prism-plugins" "$PLUGIN_DIR_USER"; do
        [ -d "$dir" ] || continue
        for plugin in "$dir"/prism-plugin-*; do
            [ -x "$plugin" ] || continue
            # Extract name: prism-plugin-weather.sh -> weather
            local basename=$(basename "$plugin")
            local name="${basename#prism-plugin-}"
            name="${name%%.*}"  # Remove extension

            # Skip if we've already seen this name (project wins)
            if [[ " $seen_names " != *" $name "* ]]; then
                seen_names+=" $name"
                plugins+="${name}:${plugin} "
            fi
        done
    done

    echo "$plugins" > "$cache_file"
    echo "$plugins"
}

# Get plugin path by name (returns empty if not found)
get_plugin_path() {
    local name="$1"
    local plugins=$(discover_plugins)
    for entry in $plugins; do
        local plugin_name="${entry%%:*}"
        local plugin_path="${entry#*:}"
        if [ "$plugin_name" = "$name" ]; then
            echo "$plugin_path"
            return
        fi
    done
}

# Build JSON input for plugins
build_plugin_input() {
    local plugin_name="$1"
    local config=$(get_config)
    local plugin_config=$(echo "$config" | jq -c --arg name "$plugin_name" '.plugins[$name] // {}' 2>/dev/null)

    # Check if session is idle
    local is_idle="false"
    is_session_idle && is_idle="true"

    cat << EOF
{
  "prism": {
    "version": "$VERSION",
    "project_dir": "$PROJECT_DIR",
    "current_dir": "$CURRENT_DIR",
    "session_id": "$SESSION_ID",
    "is_idle": $is_idle
  },
  "session": {
    "model": "$MODEL",
    "context_pct": $PCT,
    "cost_usd": $COST,
    "lines_added": $GIT_LINES_ADDED,
    "lines_removed": $GIT_LINES_REMOVED
  },
  "config": {
    "$plugin_name": $plugin_config
  },
  "colors": {
    "cyan": "\u001b[36m",
    "green": "\u001b[32m",
    "yellow": "\u001b[33m",
    "red": "\u001b[31m",
    "magenta": "\u001b[35m",
    "blue": "\u001b[34m",
    "gray": "\u001b[90m",
    "dim": "\u001b[2m",
    "reset": "\u001b[0m"
  }
}
EOF
}

# Run a plugin and capture its output
# Returns: plugin output on stdout, exits 0 on success
run_plugin() {
    local name="$1"
    local plugin_path=$(get_plugin_path "$name")

    [ -z "$plugin_path" ] && return 1

    # Get timeout from config or use default (convert ms to seconds for timeout command)
    local config=$(get_config)
    local timeout_ms=$(echo "$config" | jq -r --arg name "$name" '.plugins[$name].timeout_ms // .plugins.timeout_ms // 500' 2>/dev/null)
    local timeout_sec=$(echo "scale=2; $timeout_ms / 1000" | bc)

    # Build input and run plugin with timeout
    local input=$(build_plugin_input "$name")
    local output
    output=$(echo "$input" | timeout "$timeout_sec" "$plugin_path" 2>/dev/null)
    local exit_code=$?

    if [ $exit_code -eq 0 ] && [ -n "$output" ]; then
        echo "$output"
        return 0
    fi

    return 1
}

# Read and store full JSON input for later use
INPUT=$(cat)

# Debug: uncomment to save raw JSON for troubleshooting
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')
# echo "$INPUT" > "/tmp/prism-debug-${SESSION_ID}.json"

# Idle detection: hooks touch this file when Claude stops responding
IDLE_FILE="/tmp/prism-idle-${SESSION_ID}"

# Check if session is idle (safe to run git)
# Falls back to "idle" if hooks haven't been set up yet (no idle files exist)
is_session_idle() {
    # If our idle file exists, we're idle
    [ -f "$IDLE_FILE" ] && return 0

    # If ANY idle file exists, hooks are active but we're not idle
    ls /tmp/prism-idle-* &>/dev/null && return 1

    # No idle files at all = hooks not set up yet, assume idle (backwards compatible)
    return 0
}

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

# Function to get git info with register branch indicator (cached)
get_git_info_uncached() {
    cd "$PROJECT_DIR" 2>/dev/null || return

    if ! timeout 1 git rev-parse --git-dir > /dev/null 2>&1; then
        echo ""
        return
    fi

    BRANCH=$(timeout 1 git branch --show-current 2>/dev/null)
    if [ -z "$BRANCH" ]; then
        BRANCH=$(timeout 1 git rev-parse --short HEAD 2>/dev/null)
    fi

    # Use git status --porcelain for efficiency (single command, with timeout)
    STATUS=$(timeout 1 git status --porcelain 2>/dev/null | head -20)
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

    # Check ahead/behind upstream
    local arrows=""
    local behind=$(timeout 1 git rev-list --count HEAD..@{upstream} 2>/dev/null || echo "0")
    local ahead=$(timeout 1 git rev-list --count @{upstream}..HEAD 2>/dev/null || echo "0")
    if [ "$behind" -gt 0 ] 2>/dev/null; then
        arrows="⇣"
    fi
    if [ "$ahead" -gt 0 ] 2>/dev/null; then
        arrows="${arrows}⇡"
    fi

    echo "${BRANCH}${DIRTY}${arrows}"
}

get_git_info() {
    local cache_file="${GIT_INFO_CACHE}-$(echo "$PROJECT_DIR" | md5 -q)"

    # Always return cache if it exists and fresh
    if [ -f "$cache_file" ]; then
        local cache_age=$(($(date +%s) - $(stat -f %m "$cache_file" 2>/dev/null || echo 0)))
        if [ "$cache_age" -lt "$GIT_CACHE_MAX_AGE" ]; then
            cat "$cache_file"
            return
        fi
        # Cache is stale - only refresh when idle
        if ! is_session_idle; then
            cat "$cache_file"
            return
        fi
    fi

    # No cache or cache is stale and we're idle - run git
    local info=$(get_git_info_uncached)
    echo "$info" > "$cache_file"
    cat "$cache_file" 2>/dev/null
}

# Function to get git diff stats (lines added/removed since last commit, cached)
get_git_diff_stats_uncached() {
    cd "$PROJECT_DIR" 2>/dev/null || { echo "0 0"; return; }

    if ! timeout 1 git rev-parse --git-dir > /dev/null 2>&1; then
        echo "0 0"
        return
    fi

    # Get stats for both staged and unstaged changes (with timeout to avoid blocking)
    local stats=$(timeout 1 git diff --numstat HEAD 2>/dev/null | awk '{add+=$1; del+=$2} END {print add+0, del+0}')
    echo "${stats:-0 0}"
}

get_git_diff_stats() {
    local cache_file="${GIT_DIFF_CACHE}-$(echo "$PROJECT_DIR" | md5 -q)"

    # Always return cache if it exists and fresh
    if [ -f "$cache_file" ]; then
        local cache_age=$(($(date +%s) - $(stat -f %m "$cache_file" 2>/dev/null || echo 0)))
        if [ "$cache_age" -lt "$GIT_CACHE_MAX_AGE" ]; then
            cat "$cache_file"
            return
        fi
        # Cache is stale - only refresh when idle
        if ! is_session_idle; then
            cat "$cache_file"
            return
        fi
    fi

    # No cache or cache is stale and we're idle - run git
    local stats=$(get_git_diff_stats_uncached)
    echo "$stats" > "$cache_file"
    cat "$cache_file" 2>/dev/null || echo "0 0"
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
        if ! pgrep -f "prism.*android.*refresh" > /dev/null 2>&1; then
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
        if ! pgrep -f "prism.*ios.*refresh" > /dev/null 2>&1; then
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
                # Always show git diff stats (uncommitted changes) for consistency
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
            *)
                # Try to run as a plugin
                local plugin_output=$(run_plugin "$section")
                if [ -n "$plugin_output" ]; then
                    line_output+="${sep}${plugin_output}"
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

# Always run update plugin first (not configurable - always shown when update available)
UPDATE_OUTPUT=$(run_plugin "update" 2>/dev/null || true)
if [ -n "$UPDATE_OUTPUT" ]; then
    # Prepend update indicator to first line
    if [ "$IS_MULTILINE" = "true" ]; then
        # For multiline, prepend to first line only
        FIRST_LINE="${OUTPUT%%\\n*}"
        REST="${OUTPUT#*\\n}"
        if [ "$FIRST_LINE" = "$OUTPUT" ]; then
            # Only one line
            OUTPUT="${UPDATE_OUTPUT} ${DIM}·${RESET} ${OUTPUT}"
        else
            OUTPUT="${UPDATE_OUTPUT} ${DIM}·${RESET} ${FIRST_LINE}\n${REST}"
        fi
    else
        OUTPUT="${UPDATE_OUTPUT} ${DIM}·${RESET} ${OUTPUT}"
    fi
fi

echo -e "$OUTPUT"
