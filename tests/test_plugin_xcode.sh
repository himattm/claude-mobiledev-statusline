#!/bin/bash
#
# Prism Xcode Plugin Test Suite
# Run: ./tests/test_plugin_xcode.sh
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RESET='\033[0m'

# Track test results
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test directory
TEST_DIR=$(mktemp -d)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN="$HOME/.claude/prism-plugins/prism-plugin-xcode.sh"

# Cleanup on exit
cleanup() {
    rm -rf "$TEST_DIR"
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
    local project_dir="$1"
    cat << EOF
{
  "prism": {
    "version": "0.1.0",
    "project_dir": "$project_dir",
    "current_dir": "$project_dir",
    "session_id": "test",
    "is_idle": true
  },
  "session": {
    "model": "Test",
    "context_pct": 50,
    "cost_usd": 0,
    "lines_added": 0,
    "lines_removed": 0
  },
  "config": {
    "xcode": {}
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

# =============================================================================
# Xcode Plugin Tests
# =============================================================================

test_xcodeproj_detection() {
    local test_project="$TEST_DIR/xcodeproj_test"
    mkdir -p "$test_project"

    # Create .xcodeproj directory (not file)
    mkdir -p "$test_project/MyApp.xcodeproj"

    local output=$(build_plugin_input "$test_project" | "$PLUGIN" 2>&1)

    if [ -n "$output" ]; then
        pass "Xcode: .xcodeproj detection produces output"
    else
        fail "Xcode: .xcodeproj detection produces output" "Got no output"
    fi
}

test_xcworkspace_detection() {
    local test_project="$TEST_DIR/xcworkspace_test"
    mkdir -p "$test_project"

    # Create .xcworkspace directory (not file)
    mkdir -p "$test_project/MyApp.xcworkspace"

    local output=$(build_plugin_input "$test_project" | "$PLUGIN" 2>&1)

    if [ -n "$output" ]; then
        pass "Xcode: .xcworkspace detection produces output"
    else
        fail "Xcode: .xcworkspace detection produces output" "Got no output"
    fi
}

test_non_xcode_project_no_output() {
    local test_project="$TEST_DIR/non_xcode_test"
    mkdir -p "$test_project"

    # Empty directory - no Xcode project files
    local output=$(build_plugin_input "$test_project" | "$PLUGIN" 2>&1)

    if [ -z "$output" ]; then
        pass "Xcode: non-Xcode project produces no output"
    else
        fail "Xcode: non-Xcode project produces no output" "Got: $output"
    fi
}

test_output_contains_xcode_icon() {
    local test_project="$TEST_DIR/icon_test"
    mkdir -p "$test_project"
    mkdir -p "$test_project/MyApp.xcodeproj"

    local output=$(build_plugin_input "$test_project" | "$PLUGIN" 2>&1)

    if echo "$output" | grep -q "⚒"; then
        pass "Xcode: output contains xcode icon"
    else
        fail "Xcode: output contains xcode icon" "Got: $output"
    fi
}

test_output_shows_icon_when_no_builds() {
    local test_project="$TEST_DIR/no_builds_test"
    mkdir -p "$test_project"
    mkdir -p "$test_project/MyApp.xcodeproj"

    # In test environment, likely no xcodebuild processes running
    local output=$(build_plugin_input "$test_project" | "$PLUGIN" 2>&1)

    # Should just be the icon (possibly with color codes stripped)
    if echo "$output" | grep -q "⚒"; then
        pass "Xcode: shows icon when no builds running"
    else
        fail "Xcode: shows icon when no builds running" "Got: $output"
    fi
}

test_output_format_correct() {
    local test_project="$TEST_DIR/format_test"
    mkdir -p "$test_project"
    mkdir -p "$test_project/MyApp.xcodeproj"

    local output=$(build_plugin_input "$test_project" | "$PLUGIN" 2>&1)

    # Output should either be just the icon or icon + number
    # Pattern: icon alone OR icon followed by digits
    if echo "$output" | grep -qE "^⚒[0-9]*$"; then
        pass "Xcode: output format is correct (icon or icon+count)"
    else
        fail "Xcode: output format is correct (icon or icon+count)" "Got: $output"
    fi
}

# =============================================================================
# Run All Tests
# =============================================================================

echo ""
echo "Prism Xcode Plugin Test Suite"
echo "=============================="
echo ""

# Check if plugin exists
if [ ! -f "$PLUGIN" ]; then
    echo -e "${RED}Error: Plugin not found at $PLUGIN${RESET}"
    exit 1
fi

if [ ! -x "$PLUGIN" ]; then
    echo -e "${RED}Error: Plugin is not executable${RESET}"
    exit 1
fi

echo "Xcode Plugin Tests:"
run_test test_xcodeproj_detection
run_test test_xcworkspace_detection
run_test test_non_xcode_project_no_output
run_test test_output_contains_xcode_icon
run_test test_output_shows_icon_when_no_builds
run_test test_output_format_correct

echo ""
echo "=============================="
echo -e "Tests: $TESTS_RUN | ${GREEN}Passed: $TESTS_PASSED${RESET} | ${RED}Failed: $TESTS_FAILED${RESET}"
echo ""

if [ $TESTS_FAILED -gt 0 ]; then
    exit 1
fi
