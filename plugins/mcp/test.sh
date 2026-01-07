#!/bin/bash
#
# Prism MCP Plugin Test Suite
# Run: ./tests/test_plugin_mcp.sh
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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$SCRIPT_DIR/prism-plugin-mcp.sh"

# Verify plugin exists
if [ ! -f "$PLUGIN" ]; then
    echo -e "${RED}Error: MCP plugin not found at $PLUGIN${RESET}"
    exit 1
fi

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
    "mcp": {}
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
# MCP Plugin Tests
# =============================================================================

test_no_mcp_config_no_output() {
    local test_home="$TEST_DIR/test1/home"
    local test_project="$TEST_DIR/test1/project"
    mkdir -p "$test_home" "$test_project"

    # No config files exist
    local input=$(build_plugin_input "$test_project")
    local output=$(echo "$input" | HOME="$test_home" "$PLUGIN" 2>&1)

    if [ -z "$output" ]; then
        pass "No MCP config = no output"
    else
        fail "No MCP config = no output" "Expected empty, got: '$output'"
    fi
}

test_global_config_detection() {
    local test_home="$TEST_DIR/test2/home"
    local test_project="$TEST_DIR/test2/project"
    mkdir -p "$test_home" "$test_project"

    # Create global config with mcpServers
    cat > "$test_home/.claude.json" << 'EOF'
{
  "mcpServers": {
    "server1": {"command": "test1"},
    "server2": {"command": "test2"}
  }
}
EOF

    local input=$(build_plugin_input "$test_project")
    local output=$(echo "$input" | HOME="$test_home" "$PLUGIN" 2>&1)

    if echo "$output" | grep -q "mcp:2"; then
        pass "Global config detection - shows mcp:2"
    else
        fail "Global config detection - shows mcp:2" "Got: '$output'"
    fi
}

test_project_config_detection() {
    local test_home="$TEST_DIR/test3/home"
    local test_project="$TEST_DIR/test3/project"
    mkdir -p "$test_home" "$test_project"

    # Create project config with mcpServers
    cat > "$test_project/.mcp.json" << 'EOF'
{
  "mcpServers": {
    "local-server": {"command": "test"}
  }
}
EOF

    local input=$(build_plugin_input "$test_project")
    local output=$(echo "$input" | HOME="$test_home" "$PLUGIN" 2>&1)

    if echo "$output" | grep -q "mcp:1"; then
        pass "Project config detection - shows mcp:1"
    else
        fail "Project config detection - shows mcp:1" "Got: '$output'"
    fi
}

test_server_count_correct() {
    local test_home="$TEST_DIR/test4/home"
    local test_project="$TEST_DIR/test4/project"
    mkdir -p "$test_home" "$test_project"

    # Create global config with 3 servers
    cat > "$test_home/.claude.json" << 'EOF'
{
  "mcpServers": {
    "server-a": {"command": "a"},
    "server-b": {"command": "b"},
    "server-c": {"command": "c"}
  }
}
EOF

    local input=$(build_plugin_input "$test_project")
    local output=$(echo "$input" | HOME="$test_home" "$PLUGIN" 2>&1)

    if echo "$output" | grep -q "mcp:3"; then
        pass "Server count is correct - 3 servers shows mcp:3"
    else
        fail "Server count is correct - 3 servers shows mcp:3" "Got: '$output'"
    fi
}

test_global_takes_precedence() {
    local test_home="$TEST_DIR/test5/home"
    local test_project="$TEST_DIR/test5/project"
    mkdir -p "$test_home" "$test_project"

    # Create global config with 2 servers
    cat > "$test_home/.claude.json" << 'EOF'
{
  "mcpServers": {
    "global1": {"command": "g1"},
    "global2": {"command": "g2"}
  }
}
EOF

    # Create project config with 5 servers
    cat > "$test_project/.mcp.json" << 'EOF'
{
  "mcpServers": {
    "proj1": {"command": "p1"},
    "proj2": {"command": "p2"},
    "proj3": {"command": "p3"},
    "proj4": {"command": "p4"},
    "proj5": {"command": "p5"}
  }
}
EOF

    local input=$(build_plugin_input "$test_project")
    local output=$(echo "$input" | HOME="$test_home" "$PLUGIN" 2>&1)

    if echo "$output" | grep -q "mcp:2"; then
        pass "Global takes precedence - shows global count (2) not project count (5)"
    else
        fail "Global takes precedence - shows global count (2) not project count (5)" "Got: '$output'"
    fi
}

test_empty_mcp_servers_no_output() {
    local test_home="$TEST_DIR/test6/home"
    local test_project="$TEST_DIR/test6/project"
    mkdir -p "$test_home" "$test_project"

    # Create global config with empty mcpServers
    cat > "$test_home/.claude.json" << 'EOF'
{
  "mcpServers": {}
}
EOF

    local input=$(build_plugin_input "$test_project")
    local output=$(echo "$input" | HOME="$test_home" "$PLUGIN" 2>&1)

    if [ -z "$output" ]; then
        pass "Empty mcpServers = no output"
    else
        fail "Empty mcpServers = no output" "Expected empty, got: '$output'"
    fi
}

test_output_format() {
    local test_home="$TEST_DIR/test7/home"
    local test_project="$TEST_DIR/test7/project"
    mkdir -p "$test_home" "$test_project"

    # Create global config
    cat > "$test_home/.claude.json" << 'EOF'
{
  "mcpServers": {
    "test": {"command": "test"}
  }
}
EOF

    local input=$(build_plugin_input "$test_project")
    local output=$(echo "$input" | HOME="$test_home" "$PLUGIN" 2>&1)

    # Check exact format "mcp:N"
    if [[ "$output" =~ mcp:[0-9]+ ]]; then
        pass "Output format is mcp:N"
    else
        fail "Output format is mcp:N" "Got: '$output'"
    fi
}

# =============================================================================
# Run All Tests
# =============================================================================

echo ""
echo "Prism MCP Plugin Test Suite"
echo "==========================="
echo ""

echo "MCP Plugin Tests:"
run_test test_no_mcp_config_no_output
run_test test_global_config_detection
run_test test_project_config_detection
run_test test_server_count_correct
run_test test_global_takes_precedence
run_test test_empty_mcp_servers_no_output
run_test test_output_format

echo ""
echo "==========================="
echo -e "Tests: $TESTS_RUN | ${GREEN}Passed: $TESTS_PASSED${RESET} | ${RED}Failed: $TESTS_FAILED${RESET}"
echo ""

if [ $TESTS_FAILED -gt 0 ]; then
    exit 1
fi
