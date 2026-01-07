#!/bin/bash
#
# Prism Test Suite
# Run: ./tests/test_prism.sh
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
PRISM="$SCRIPT_DIR/prism.sh"

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

# =============================================================================
# CLI Tests
# =============================================================================

test_cli_help() {
    local output=$("$PRISM" help 2>&1)
    if echo "$output" | grep -q "Prism - A fast, customizable status line"; then
        pass "CLI: help shows description"
    else
        fail "CLI: help shows description" "Got: $output"
    fi

    if echo "$output" | grep -q "prism init"; then
        pass "CLI: help shows init command"
    else
        fail "CLI: help shows init command"
    fi
}

test_cli_help_flags() {
    local output1=$("$PRISM" --help 2>&1)
    local output2=$("$PRISM" -h 2>&1)

    if echo "$output1" | grep -q "Usage:"; then
        pass "CLI: --help works"
    else
        fail "CLI: --help works"
    fi

    if echo "$output2" | grep -q "Usage:"; then
        pass "CLI: -h works"
    else
        fail "CLI: -h works"
    fi
}

test_cli_unknown_command() {
    local output=$("$PRISM" foobar 2>&1) || true
    if echo "$output" | grep -q "Unknown command"; then
        pass "CLI: unknown command shows error"
    else
        fail "CLI: unknown command shows error"
    fi
}

test_cli_init() {
    cd "$TEST_DIR"
    rm -f .prism.json

    local output=$("$PRISM" init 2>&1)

    if [ -f ".prism.json" ]; then
        pass "CLI: init creates .prism.json"
    else
        fail "CLI: init creates .prism.json"
    fi

    if grep -q '"icon"' .prism.json; then
        pass "CLI: init includes icon in config"
    else
        fail "CLI: init includes icon in config"
    fi

    if grep -q '"sections"' .prism.json; then
        pass "CLI: init includes sections in config"
    else
        fail "CLI: init includes sections in config"
    fi
}

test_cli_init_no_overwrite() {
    cd "$TEST_DIR"
    echo '{"existing": true}' > .prism.json

    local output=$("$PRISM" init 2>&1) || true

    if echo "$output" | grep -q "already exists"; then
        pass "CLI: init refuses to overwrite existing config"
    else
        fail "CLI: init refuses to overwrite existing config"
    fi

    if grep -q '"existing"' .prism.json; then
        pass "CLI: init preserves existing config"
    else
        fail "CLI: init preserves existing config"
    fi
}

test_cli_init_global() {
    local test_home="$TEST_DIR/home"
    mkdir -p "$test_home/.claude"

    # Temporarily override HOME
    HOME="$test_home" "$PRISM" init-global 2>&1

    if [ -f "$test_home/.claude/prism-config.json" ]; then
        pass "CLI: init-global creates global config"
    else
        fail "CLI: init-global creates global config"
    fi

    if grep -q '"sections"' "$test_home/.claude/prism-config.json"; then
        pass "CLI: init-global includes sections"
    else
        fail "CLI: init-global includes sections"
    fi
}

# =============================================================================
# Config Merge Tests
# =============================================================================

test_config_global_only() {
    local test_home="$TEST_DIR/config_test1"
    local test_project="$test_home/project"
    mkdir -p "$test_home/.claude" "$test_project"

    # Create global config
    echo '{"icon": "🌍", "sections": ["dir", "git"]}' > "$test_home/.claude/prism-config.json"

    # Run prism with test JSON input
    local input='{"session_id":"test","workspace":{"project_dir":"'"$test_project"'","current_dir":"'"$test_project"'"},"model":{"display_name":"Test"},"context_window":{"context_window_size":200000,"current_usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"cost":{"total_cost_usd":0.01}}'

    # Clear any cached config
    rm -f /tmp/prism-config-*

    local output=$(echo "$input" | HOME="$test_home" "$PRISM" 2>&1)

    if echo "$output" | grep -q "🌍"; then
        pass "Config: global icon is used"
    else
        fail "Config: global icon is used" "Output: $output"
    fi
}

test_config_repo_overrides_global() {
    local test_home="$TEST_DIR/config_test2"
    local test_project="$test_home/project"
    mkdir -p "$test_home/.claude" "$test_project"

    # Create global config
    echo '{"icon": "🌍"}' > "$test_home/.claude/prism-config.json"

    # Create repo config that overrides
    echo '{"icon": "🚀"}' > "$test_project/.prism.json"

    local input='{"session_id":"test2","workspace":{"project_dir":"'"$test_project"'","current_dir":"'"$test_project"'"},"model":{"display_name":"Test"},"context_window":{"context_window_size":200000,"current_usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"cost":{"total_cost_usd":0.01}}'

    rm -f /tmp/prism-config-*

    local output=$(echo "$input" | HOME="$test_home" "$PRISM" 2>&1)

    if echo "$output" | grep -q "🚀"; then
        pass "Config: repo overrides global icon"
    else
        fail "Config: repo overrides global icon" "Output: $output"
    fi
}

test_config_local_overrides_repo() {
    local test_home="$TEST_DIR/config_test3"
    local test_project="$test_home/project"
    mkdir -p "$test_home/.claude" "$test_project"

    # Create all three tiers
    echo '{"icon": "🌍"}' > "$test_home/.claude/prism-config.json"
    echo '{"icon": "🚀"}' > "$test_project/.prism.json"
    echo '{"icon": "🔧"}' > "$test_project/.prism.local.json"

    local input='{"session_id":"test3","workspace":{"project_dir":"'"$test_project"'","current_dir":"'"$test_project"'"},"model":{"display_name":"Test"},"context_window":{"context_window_size":200000,"current_usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"cost":{"total_cost_usd":0.01}}'

    rm -f /tmp/prism-config-*

    local output=$(echo "$input" | HOME="$test_home" "$PRISM" 2>&1)

    if echo "$output" | grep -q "🔧"; then
        pass "Config: local overrides repo icon"
    else
        fail "Config: local overrides repo icon" "Output: $output"
    fi
}

# =============================================================================
# Status Line Output Tests
# =============================================================================

test_output_contains_model() {
    local test_project="$TEST_DIR/output_test"
    mkdir -p "$test_project"

    local input='{"session_id":"output1","workspace":{"project_dir":"'"$test_project"'","current_dir":"'"$test_project"'"},"model":{"display_name":"Opus 4.5"},"context_window":{"context_window_size":200000,"current_usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"cost":{"total_cost_usd":0.15}}'

    rm -f /tmp/prism-config-*

    local output=$(echo "$input" | "$PRISM" 2>&1)

    if echo "$output" | grep -q "Opus 4.5"; then
        pass "Output: contains model name"
    else
        fail "Output: contains model name" "Output: $output"
    fi
}

test_output_contains_cost() {
    local test_project="$TEST_DIR/output_test2"
    mkdir -p "$test_project"

    local input='{"session_id":"output2","workspace":{"project_dir":"'"$test_project"'","current_dir":"'"$test_project"'"},"model":{"display_name":"Test"},"context_window":{"context_window_size":200000,"current_usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"cost":{"total_cost_usd":1.23}}'

    rm -f /tmp/prism-config-*

    local output=$(echo "$input" | "$PRISM" 2>&1)

    if echo "$output" | grep -q "\$1.23"; then
        pass "Output: contains cost"
    else
        fail "Output: contains cost" "Output: $output"
    fi
}

test_output_contains_context_bar() {
    local test_project="$TEST_DIR/output_test3"
    mkdir -p "$test_project"

    local input='{"session_id":"output3","workspace":{"project_dir":"'"$test_project"'","current_dir":"'"$test_project"'"},"model":{"display_name":"Test"},"context_window":{"context_window_size":200000,"current_usage":{"input_tokens":50000,"output_tokens":10000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"cost":{"total_cost_usd":0.01}}'

    rm -f /tmp/prism-config-*

    local output=$(echo "$input" | "$PRISM" 2>&1)

    if echo "$output" | grep -q "%"; then
        pass "Output: contains context percentage"
    else
        fail "Output: contains context percentage" "Output: $output"
    fi
}

test_output_project_name() {
    local test_project="$TEST_DIR/my-cool-project"
    mkdir -p "$test_project"

    local input='{"session_id":"output4","workspace":{"project_dir":"'"$test_project"'","current_dir":"'"$test_project"'"},"model":{"display_name":"Test"},"context_window":{"context_window_size":200000,"current_usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"cost":{"total_cost_usd":0.01}}'

    rm -f /tmp/prism-config-*

    local output=$(echo "$input" | "$PRISM" 2>&1)

    if echo "$output" | grep -q "my-cool-project"; then
        pass "Output: contains project name"
    else
        fail "Output: contains project name" "Output: $output"
    fi
}

# =============================================================================
# Run All Tests
# =============================================================================

echo ""
echo "Prism Test Suite"
echo "================"
echo ""

echo "CLI Tests:"
run_test test_cli_help
run_test test_cli_help_flags
run_test test_cli_unknown_command
run_test test_cli_init
run_test test_cli_init_no_overwrite
run_test test_cli_init_global

echo ""
echo "Config Merge Tests:"
run_test test_config_global_only
run_test test_config_repo_overrides_global
run_test test_config_local_overrides_repo

echo ""
echo "Status Line Output Tests:"
run_test test_output_contains_model
run_test test_output_contains_cost
run_test test_output_contains_context_bar
run_test test_output_project_name

echo ""
echo "================"
echo -e "Tests: $TESTS_RUN | ${GREEN}Passed: $TESTS_PASSED${RESET} | ${RED}Failed: $TESTS_FAILED${RESET}"
echo ""

if [ $TESTS_FAILED -gt 0 ]; then
    exit 1
fi
