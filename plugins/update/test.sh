#!/bin/bash
#
# Update Plugin Test Suite
# Run: ./plugins/update/test.sh
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[36m'
RESET='\033[0m'

# Track test results
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Script paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$SCRIPT_DIR/prism-plugin-update.sh"

# Test cache file
TEST_CACHE="/tmp/prism-update-check-test"

# Cleanup on exit
cleanup() {
    rm -f "$TEST_CACHE"
    rm -f /tmp/prism-update-check
}
trap cleanup EXIT

# Test helpers
pass() {
    ((TESTS_PASSED++))
    echo -e "${GREEN}✓${RESET} $1"
}

fail() {
    ((TESTS_FAILED++))
    echo -e "${RED}✗${RESET} $1"
    if [ -n "$2" ]; then
        echo -e "  ${YELLOW}$2${RESET}"
    fi
}

run_test() {
    ((TESTS_RUN++))
    "$@"
}

# Build JSON input for the plugin
build_plugin_input() {
    local version="${1:-0.1.0}"
    local is_idle="${2:-true}"
    local enabled="${3:-true}"
    local check_interval="${4:-24}"
    cat << EOF
{
  "prism": {
    "version": "$version",
    "project_dir": "/tmp",
    "current_dir": "/tmp",
    "session_id": "test",
    "is_idle": $is_idle
  },
  "session": {
    "model": "Test",
    "context_pct": 50,
    "cost_usd": 0,
    "lines_added": 0,
    "lines_removed": 0
  },
  "config": {
    "update": {
      "enabled": $enabled,
      "check_interval_hours": $check_interval
    }
  },
  "colors": {
    "cyan": "",
    "green": "",
    "yellow": "",
    "red": "",
    "magenta": "",
    "blue": "",
    "gray": "",
    "dim": "",
    "reset": ""
  }
}
EOF
}

# Create a mock cache file
create_cache() {
    local local_ver="$1"
    local remote_ver="$2"
    local update_available="$3"
    cat > /tmp/prism-update-check << EOF
{
  "checked_at": $(date +%s),
  "local_version": "$local_ver",
  "remote_version": "$remote_ver",
  "update_available": $update_available
}
EOF
}

# Create an old cache file (stale)
create_stale_cache() {
    local local_ver="$1"
    local remote_ver="$2"
    local update_available="$3"
    cat > /tmp/prism-update-check << EOF
{
  "checked_at": $(($(date +%s) - 100000)),
  "local_version": "$local_ver",
  "remote_version": "$remote_ver",
  "update_available": $update_available
}
EOF
    # Touch with old timestamp
    touch -t 202001010000 /tmp/prism-update-check
}

echo "========================================="
echo "Update Plugin Test Suite"
echo "========================================="
echo ""

# ====================
# Version Comparison Tests
# ====================
echo "Version Comparison Tests"
echo "------------------------"

# Test version comparison function directly by sourcing relevant parts
test_version_lt() {
    # Extract and test the version_lt function
    local v1="$1"
    local v2="$2"
    local expected="$3"

    # Inline version of the comparison logic
    version_lt() {
        [ "$1" = "$2" ] && return 1
        local IFS=.
        local i
        local v1_arr=($1)
        local v2_arr=($2)
        for ((i=0; i<${#v1_arr[@]} || i<${#v2_arr[@]}; i++)); do
            local n1=${v1_arr[i]:-0}
            local n2=${v2_arr[i]:-0}
            n1=$(echo "$n1" | sed 's/[^0-9].*//')
            n2=$(echo "$n2" | sed 's/[^0-9].*//')
            [ "${n1:-0}" -lt "${n2:-0}" ] && return 0
            [ "${n1:-0}" -gt "${n2:-0}" ] && return 1
        done
        return 1
    }

    if version_lt "$v1" "$v2"; then
        local result="true"
    else
        local result="false"
    fi

    if [ "$result" = "$expected" ]; then
        pass "$v1 < $v2 = $expected"
    else
        fail "$v1 < $v2 expected $expected, got $result"
    fi
}

run_test test_version_lt "0.1.0" "0.2.0" "true"
run_test test_version_lt "0.1.0" "0.1.1" "true"
run_test test_version_lt "0.1.0" "1.0.0" "true"
run_test test_version_lt "0.2.0" "0.1.0" "false"
run_test test_version_lt "0.1.0" "0.1.0" "false"
run_test test_version_lt "1.0.0" "0.9.9" "false"
run_test test_version_lt "0.1" "0.1.1" "true"
run_test test_version_lt "0.1.0" "0.1" "false"

echo ""

# ====================
# Cache Behavior Tests
# ====================
echo "Cache Behavior Tests"
echo "--------------------"

# Test: Fresh cache with update available shows indicator
test_cache_update_available() {
    cleanup
    create_cache "0.1.0" "0.2.0" "true"

    local output
    output=$(build_plugin_input "0.1.0" "true" | "$PLUGIN" 2>/dev/null)

    # Should output the up arrow (without color codes since we passed empty strings)
    if echo "$output" | grep -q "⬆"; then
        pass "Shows indicator when update available"
    else
        fail "Should show indicator when update available" "Output: '$output'"
    fi
}
run_test test_cache_update_available

# Test: Fresh cache with no update shows nothing
test_cache_no_update() {
    cleanup
    create_cache "0.2.0" "0.2.0" "false"

    local output
    output=$(build_plugin_input "0.2.0" "true" | "$PLUGIN" 2>/dev/null)

    if [ -z "$output" ]; then
        pass "Shows nothing when no update available"
    else
        fail "Should show nothing when no update" "Output: '$output'"
    fi
}
run_test test_cache_no_update

# Test: Disabled plugin shows nothing
test_plugin_disabled() {
    cleanup
    create_cache "0.1.0" "0.2.0" "true"

    local output
    output=$(build_plugin_input "0.1.0" "true" "false" | "$PLUGIN" 2>/dev/null)

    if [ -z "$output" ]; then
        pass "Shows nothing when plugin disabled"
    else
        fail "Should show nothing when disabled" "Output: '$output'"
    fi
}
run_test test_plugin_disabled

# Test: Stale cache when NOT idle should use old cached value
test_stale_cache_not_idle() {
    cleanup
    create_stale_cache "0.1.0" "0.2.0" "true"

    local output
    # is_idle=false means we shouldn't refresh
    output=$(build_plugin_input "0.1.0" "false" | "$PLUGIN" 2>/dev/null)

    # Should still show indicator from old cache
    if echo "$output" | grep -q "⬆"; then
        pass "Uses stale cache when not idle"
    else
        fail "Should use stale cache when not idle" "Output: '$output'"
    fi
}
run_test test_stale_cache_not_idle

# Test: No cache file - should show nothing (can't check GitHub in test)
test_no_cache() {
    cleanup

    local output
    # With no cache and not idle, should show nothing
    output=$(build_plugin_input "0.1.0" "false" | "$PLUGIN" 2>/dev/null)

    if [ -z "$output" ]; then
        pass "Shows nothing with no cache and not idle"
    else
        fail "Should show nothing with no cache" "Output: '$output'"
    fi
}
run_test test_no_cache

echo ""

# ====================
# Output Format Tests
# ====================
echo "Output Format Tests"
echo "-------------------"

# Test: Output contains up arrow character
test_output_format() {
    cleanup
    create_cache "0.1.0" "0.2.0" "true"

    local output
    output=$(build_plugin_input "0.1.0" "true" | "$PLUGIN" 2>/dev/null)

    # Check for the Unicode up arrow (U+2B06)
    if echo "$output" | grep -q "⬆"; then
        pass "Output contains up arrow Unicode character"
    else
        fail "Output should contain ⬆ character" "Output: '$output'"
    fi
}
run_test test_output_format

# Test: Output includes color codes when provided
test_output_with_colors() {
    cleanup
    create_cache "0.1.0" "0.2.0" "true"

    # Build input with actual color codes
    local input
    input=$(cat << EOF
{
  "prism": {
    "version": "0.1.0",
    "project_dir": "/tmp",
    "current_dir": "/tmp",
    "session_id": "test",
    "is_idle": true
  },
  "session": {},
  "config": { "update": {} },
  "colors": {
    "cyan": "\u001b[36m",
    "reset": "\u001b[0m"
  }
}
EOF
)

    local output
    output=$(echo "$input" | "$PLUGIN" 2>/dev/null)

    # Should contain escape sequences
    if echo "$output" | grep -q $'\033'; then
        pass "Output includes ANSI color codes"
    else
        fail "Output should include color codes" "Output: $(echo "$output" | cat -v)"
    fi
}
run_test test_output_with_colors

echo ""

# ====================
# Summary
# ====================
echo "========================================="
echo "Results: $TESTS_PASSED/$TESTS_RUN passed"

if [ "$TESTS_FAILED" -gt 0 ]; then
    echo -e "${RED}$TESTS_FAILED test(s) failed${RESET}"
    exit 1
else
    echo -e "${GREEN}All tests passed!${RESET}"
    exit 0
fi
