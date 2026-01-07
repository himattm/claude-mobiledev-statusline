#!/bin/bash
#
# Prism Gradle Plugin Test Suite
# Run: ./tests/test_plugin_gradle.sh
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
PLUGIN="$HOME/.claude/prism-plugins/prism-plugin-gradle.sh"

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

# Build plugin input JSON
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
    "gradle": {}
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
# Gradle Project Detection Tests
# =============================================================================

test_detect_build_gradle() {
    local project="$TEST_DIR/gradle_build"
    mkdir -p "$project"
    touch "$project/build.gradle"

    local output=$(build_plugin_input "$project" | "$PLUGIN" 2>&1)

    if [ -n "$output" ]; then
        pass "Detection: build.gradle produces output"
    else
        fail "Detection: build.gradle produces output" "Got no output"
    fi
}

test_detect_build_gradle_kts() {
    local project="$TEST_DIR/gradle_build_kts"
    mkdir -p "$project"
    touch "$project/build.gradle.kts"

    local output=$(build_plugin_input "$project" | "$PLUGIN" 2>&1)

    if [ -n "$output" ]; then
        pass "Detection: build.gradle.kts produces output"
    else
        fail "Detection: build.gradle.kts produces output" "Got no output"
    fi
}

test_detect_settings_gradle() {
    local project="$TEST_DIR/gradle_settings"
    mkdir -p "$project"
    touch "$project/settings.gradle"

    local output=$(build_plugin_input "$project" | "$PLUGIN" 2>&1)

    if [ -n "$output" ]; then
        pass "Detection: settings.gradle produces output"
    else
        fail "Detection: settings.gradle produces output" "Got no output"
    fi
}

test_detect_settings_gradle_kts() {
    local project="$TEST_DIR/gradle_settings_kts"
    mkdir -p "$project"
    touch "$project/settings.gradle.kts"

    local output=$(build_plugin_input "$project" | "$PLUGIN" 2>&1)

    if [ -n "$output" ]; then
        pass "Detection: settings.gradle.kts produces output"
    else
        fail "Detection: settings.gradle.kts produces output" "Got no output"
    fi
}

test_non_gradle_no_output() {
    local project="$TEST_DIR/non_gradle"
    mkdir -p "$project"

    local output=$(build_plugin_input "$project" | "$PLUGIN" 2>&1)

    if [ -z "$output" ]; then
        pass "Detection: non-Gradle project produces no output"
    else
        fail "Detection: non-Gradle project produces no output" "Got: $output"
    fi
}

# =============================================================================
# Output Format Tests
# =============================================================================

test_output_contains_icon() {
    local project="$TEST_DIR/icon_test"
    mkdir -p "$project"
    touch "$project/build.gradle"

    local output=$(build_plugin_input "$project" | "$PLUGIN" 2>&1)

    if echo "$output" | grep -q "𓃰"; then
        pass "Output: contains gradle icon"
    else
        fail "Output: contains gradle icon" "Got: $output"
    fi
}

test_output_shows_question_mark_no_daemons() {
    local project="$TEST_DIR/question_test"
    mkdir -p "$project"
    touch "$project/build.gradle"

    local output=$(build_plugin_input "$project" | "$PLUGIN" 2>&1)

    # In test environment, there are likely no Gradle daemons running
    # so we should see either a number or ?
    if echo "$output" | grep -qE "𓃰[0-9?]+"; then
        pass "Output: shows count or ? after icon"
    else
        fail "Output: shows count or ? after icon" "Got: $output"
    fi
}

test_output_format_correct() {
    local project="$TEST_DIR/format_test"
    mkdir -p "$project"
    touch "$project/build.gradle"

    local output=$(build_plugin_input "$project" | "$PLUGIN" 2>&1)

    # Output should be icon followed by count or ?
    # Strip ANSI codes for checking
    local stripped=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')

    if echo "$stripped" | grep -qE "^𓃰[0-9?]+$"; then
        pass "Output: format is icon followed by count or ?"
    else
        fail "Output: format is icon followed by count or ?" "Got stripped: '$stripped'"
    fi
}

# =============================================================================
# Run All Tests
# =============================================================================

echo ""
echo "Prism Gradle Plugin Test Suite"
echo "==============================="
echo ""

# Check plugin exists
if [ ! -f "$PLUGIN" ]; then
    echo -e "${RED}Error: Plugin not found at $PLUGIN${RESET}"
    exit 1
fi

echo "Gradle Project Detection Tests:"
run_test test_detect_build_gradle
run_test test_detect_build_gradle_kts
run_test test_detect_settings_gradle
run_test test_detect_settings_gradle_kts
run_test test_non_gradle_no_output

echo ""
echo "Output Format Tests:"
run_test test_output_contains_icon
run_test test_output_shows_question_mark_no_daemons
run_test test_output_format_correct

echo ""
echo "==============================="
echo -e "Tests: $TESTS_RUN | ${GREEN}Passed: $TESTS_PASSED${RESET} | ${RED}Failed: $TESTS_FAILED${RESET}"
echo ""

if [ $TESTS_FAILED -gt 0 ]; then
    exit 1
fi
