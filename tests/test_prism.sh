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
    if echo "$output" | grep -q "A fast, customizable status line"; then
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

test_cli_version() {
    local output=$("$PRISM" version 2>&1)
    if echo "$output" | grep -q "Prism [0-9]"; then
        pass "CLI: version shows version number"
    else
        fail "CLI: version shows version number" "Got: $output"
    fi

    local output2=$("$PRISM" --version 2>&1)
    if echo "$output2" | grep -q "Prism [0-9]"; then
        pass "CLI: --version works"
    else
        fail "CLI: --version works"
    fi

    local output3=$("$PRISM" -v 2>&1)
    if echo "$output3" | grep -q "Prism [0-9]"; then
        pass "CLI: -v works"
    else
        fail "CLI: -v works"
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
    rm -rf .claude

    local output=$("$PRISM" init 2>&1)

    if [ -f ".claude/prism.json" ]; then
        pass "CLI: init creates .claude/prism.json"
    else
        fail "CLI: init creates .claude/prism.json"
    fi

    if grep -q '"icon"' .claude/prism.json; then
        pass "CLI: init includes icon in config"
    else
        fail "CLI: init includes icon in config"
    fi

    if grep -q '"sections"' .claude/prism.json; then
        pass "CLI: init includes sections in config"
    else
        fail "CLI: init includes sections in config"
    fi
}

test_cli_init_no_overwrite() {
    cd "$TEST_DIR"
    mkdir -p .claude
    echo '{"existing": true}' > .claude/prism.json

    local output=$("$PRISM" init 2>&1) || true

    if echo "$output" | grep -q "already exists"; then
        pass "CLI: init refuses to overwrite existing config"
    else
        fail "CLI: init refuses to overwrite existing config"
    fi

    if grep -q '"existing"' .claude/prism.json; then
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
    mkdir -p "$test_home/.claude" "$test_project/.claude"

    # Create global config
    echo '{"icon": "🌍"}' > "$test_home/.claude/prism-config.json"

    # Create repo config that overrides
    echo '{"icon": "🚀"}' > "$test_project/.claude/prism.json"

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
    mkdir -p "$test_home/.claude" "$test_project/.claude"

    # Create all three tiers
    echo '{"icon": "🌍"}' > "$test_home/.claude/prism-config.json"
    echo '{"icon": "🚀"}' > "$test_project/.claude/prism.json"
    echo '{"icon": "🔧"}' > "$test_project/.claude/prism.local.json"

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
# Plugin Tests
# =============================================================================

test_cli_plugins() {
    # Test the plugin list command
    local output=$("$PRISM" plugin list 2>&1)

    # Check that it shows the table header
    if echo "$output" | grep -q "NAME"; then
        pass "CLI: plugins lists discovered plugins"
    else
        fail "CLI: plugins lists discovered plugins" "Output: $output"
    fi

    # Check that it shows plugin directory info
    if echo "$output" | grep -q "Plugin directory"; then
        pass "CLI: plugins shows directory info"
    else
        fail "CLI: plugins shows directory info"
    fi
}

test_cli_test_plugin() {
    # Create a test plugin
    local plugin_dir="$TEST_DIR/test_plugin_test/.claude/prism-plugins"
    mkdir -p "$plugin_dir"
    cat > "$plugin_dir/prism-plugin-hello.sh" << 'EOF'
#!/bin/bash
INPUT=$(cat)
CYAN=$(echo "$INPUT" | jq -r '.colors.cyan')
RESET=$(echo "$INPUT" | jq -r '.colors.reset')
echo -e "${CYAN}hello${RESET}"
EOF
    chmod +x "$plugin_dir/prism-plugin-hello.sh"

    cd "$TEST_DIR/test_plugin_test"
    local output=$("$PRISM" test-plugin hello . 2>&1)

    if echo "$output" | grep -q "hello"; then
        pass "CLI: test-plugin runs plugin and shows output"
    else
        fail "CLI: test-plugin runs plugin and shows output" "Output: $output"
    fi

    if echo "$output" | grep -q "Exit code: 0"; then
        pass "CLI: test-plugin shows exit code"
    else
        fail "CLI: test-plugin shows exit code"
    fi
}

test_plugin_in_status_line() {
    # Create a test plugin that outputs a marker
    local test_home="$TEST_DIR/plugin_output_test"
    local test_project="$test_home/project"
    mkdir -p "$test_project/.claude/prism-plugins"
    mkdir -p "$test_home/.claude"

    # Create a simple plugin
    cat > "$test_project/.claude/prism-plugins/prism-plugin-marker.sh" << 'EOF'
#!/bin/bash
INPUT=$(cat)
echo "PLUGIN_MARKER"
EOF
    chmod +x "$test_project/.claude/prism-plugins/prism-plugin-marker.sh"

    # Create config that uses the plugin
    echo '{"sections": ["dir", "marker"]}' > "$test_project/.claude/prism.json"

    # Clear caches
    rm -f /tmp/prism-config-* /tmp/prism-plugins-*

    local input='{"session_id":"plugin-test","workspace":{"project_dir":"'"$test_project"'","current_dir":"'"$test_project"'"},"model":{"display_name":"Test"},"context_window":{"context_window_size":200000,"current_usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"cost":{"total_cost_usd":0.01}}'

    local output=$(echo "$input" | HOME="$test_home" "$PRISM" 2>&1)

    if echo "$output" | grep -q "PLUGIN_MARKER"; then
        pass "Plugin: custom plugin output appears in status line"
    else
        fail "Plugin: custom plugin output appears in status line" "Output: $output"
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
run_test test_cli_version
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
echo "Plugin Tests:"
run_test test_cli_plugins
run_test test_cli_test_plugin
run_test test_plugin_in_status_line

echo ""
echo "================"
echo -e "Tests: $TESTS_RUN | ${GREEN}Passed: $TESTS_PASSED${RESET} | ${RED}Failed: $TESTS_FAILED${RESET}"
echo ""

if [ $TESTS_FAILED -gt 0 ]; then
    exit 1
fi
