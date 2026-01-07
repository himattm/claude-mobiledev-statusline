#!/bin/bash
#
# Git Plugin Test Suite
# Run: ./tests/test_plugin_git.sh
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
PLUGIN="$HOME/.claude/prism-plugins/prism-plugin-git.sh"

# Cleanup on exit
cleanup() {
    rm -rf "$TEST_DIR"
    # Clean up any git caches we created
    rm -f /tmp/prism-git-info-*
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
# Colors are empty strings for easier assertion matching
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
    "git": {}
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

# Helper to create a fresh git repo
create_test_repo() {
    local repo_dir="$1"
    mkdir -p "$repo_dir"
    cd "$repo_dir"
    git init --initial-branch=main > /dev/null 2>&1
    git config user.email "test@test.com"
    git config user.name "Test User"
    # Create initial commit so we have a valid HEAD
    echo "initial" > README.md
    git add README.md
    git commit -m "Initial commit" > /dev/null 2>&1
}

# Helper to clear git cache for a directory
clear_git_cache() {
    local project_dir="$1"
    local cache_file="/tmp/prism-git-info-$(echo "$project_dir" | md5 -q)"
    rm -f "$cache_file"
}

# =============================================================================
# Git Plugin Tests
# =============================================================================

test_branch_name_detection() {
    local repo_dir="$TEST_DIR/branch_test"
    create_test_repo "$repo_dir"
    clear_git_cache "$repo_dir"

    local output=$(build_plugin_input "$repo_dir" | "$PLUGIN" 2>&1)

    if echo "$output" | grep -q "main"; then
        pass "Git: branch name 'main' appears in output"
    else
        fail "Git: branch name 'main' appears in output" "Got: '$output'"
    fi
}

test_staged_changes_indicator() {
    local repo_dir="$TEST_DIR/staged_test"
    create_test_repo "$repo_dir"
    clear_git_cache "$repo_dir"

    # Create and stage a file
    echo "staged content" > "$repo_dir/staged.txt"
    cd "$repo_dir"
    git add staged.txt

    local output=$(build_plugin_input "$repo_dir" | "$PLUGIN" 2>&1)

    if echo "$output" | grep -q '\*'; then
        pass "Git: staged changes indicator (*) appears"
    else
        fail "Git: staged changes indicator (*) appears" "Got: '$output'"
    fi
}

test_unstaged_changes_indicator() {
    local repo_dir="$TEST_DIR/unstaged_test"
    create_test_repo "$repo_dir"
    clear_git_cache "$repo_dir"

    # Modify a tracked file without staging
    echo "modified content" >> "$repo_dir/README.md"

    local output=$(build_plugin_input "$repo_dir" | "$PLUGIN" 2>&1)

    # Plugin adds * for unstaged changes (second column in git status --porcelain)
    if echo "$output" | grep -q '\*'; then
        pass "Git: unstaged changes indicator (*) appears"
    else
        fail "Git: unstaged changes indicator (*) appears" "Got: '$output'"
    fi
}

test_untracked_files_indicator() {
    local repo_dir="$TEST_DIR/untracked_test"
    create_test_repo "$repo_dir"
    clear_git_cache "$repo_dir"

    # Create an untracked file
    echo "untracked content" > "$repo_dir/untracked.txt"

    local output=$(build_plugin_input "$repo_dir" | "$PLUGIN" 2>&1)

    if echo "$output" | grep -q '+'; then
        pass "Git: untracked files indicator (+) appears"
    else
        fail "Git: untracked files indicator (+) appears" "Got: '$output'"
    fi
}

test_combined_indicators() {
    local repo_dir="$TEST_DIR/combined_test"
    create_test_repo "$repo_dir"
    clear_git_cache "$repo_dir"

    # Create all three states:
    # 1. Stage a new file
    echo "staged" > "$repo_dir/staged.txt"
    cd "$repo_dir"
    git add staged.txt

    # 2. Modify tracked file without staging (unstaged)
    echo "modified" >> "$repo_dir/README.md"

    # 3. Create untracked file
    echo "untracked" > "$repo_dir/untracked.txt"

    local output=$(build_plugin_input "$repo_dir" | "$PLUGIN" 2>&1)

    # Should have * for staged, * for unstaged, + for untracked = main**+
    if echo "$output" | grep -q 'main\*\*+'; then
        pass "Git: combined indicators (main**+) appear correctly"
    else
        fail "Git: combined indicators (main**+) appear correctly" "Got: '$output'"
    fi
}

test_detached_head() {
    local repo_dir="$TEST_DIR/detached_test"
    create_test_repo "$repo_dir"

    # Create another commit so we have something to detach to
    echo "second commit" > "$repo_dir/second.txt"
    cd "$repo_dir"
    git add second.txt
    git commit -m "Second commit" > /dev/null 2>&1

    # Get the first commit hash
    local first_commit=$(git rev-parse HEAD~1)
    local short_hash=$(git rev-parse --short HEAD~1)

    # Checkout the first commit (detached HEAD)
    git checkout "$first_commit" > /dev/null 2>&1

    clear_git_cache "$repo_dir"

    local output=$(build_plugin_input "$repo_dir" | "$PLUGIN" 2>&1)

    if echo "$output" | grep -q "$short_hash"; then
        pass "Git: detached HEAD shows short hash ($short_hash)"
    else
        fail "Git: detached HEAD shows short hash ($short_hash)" "Got: '$output'"
    fi
}

test_non_git_directory() {
    local non_git_dir="$TEST_DIR/not_a_repo"
    mkdir -p "$non_git_dir"
    clear_git_cache "$non_git_dir"

    local output=$(build_plugin_input "$non_git_dir" | "$PLUGIN" 2>&1)

    if [ -z "$output" ]; then
        pass "Git: non-git directory produces empty output"
    else
        fail "Git: non-git directory produces empty output" "Got: '$output'"
    fi
}

test_clean_working_tree() {
    local repo_dir="$TEST_DIR/clean_test"
    create_test_repo "$repo_dir"
    clear_git_cache "$repo_dir"

    # Repo is clean after initial commit, no modifications
    local output=$(build_plugin_input "$repo_dir" | "$PLUGIN" 2>&1)

    # Should just be "main" with no indicators
    if [ "$output" = "main" ]; then
        pass "Git: clean working tree shows only branch name"
    else
        fail "Git: clean working tree shows only branch name" "Got: '$output' (expected 'main')"
    fi
}

# =============================================================================
# Run All Tests
# =============================================================================

echo ""
echo "Git Plugin Test Suite"
echo "====================="
echo ""

# Check plugin exists
if [ ! -f "$PLUGIN" ]; then
    echo -e "${RED}Error: Git plugin not found at $PLUGIN${RESET}"
    exit 1
fi

if [ ! -x "$PLUGIN" ]; then
    echo -e "${RED}Error: Git plugin is not executable${RESET}"
    exit 1
fi

echo "Plugin: $PLUGIN"
echo ""

echo "Git Status Tests:"
run_test test_branch_name_detection
run_test test_staged_changes_indicator
run_test test_unstaged_changes_indicator
run_test test_untracked_files_indicator
run_test test_combined_indicators
run_test test_detached_head
run_test test_non_git_directory
run_test test_clean_working_tree

echo ""
echo "====================="
echo -e "Tests: $TESTS_RUN | ${GREEN}Passed: $TESTS_PASSED${RESET} | ${RED}Failed: $TESTS_FAILED${RESET}"
echo ""

if [ $TESTS_FAILED -gt 0 ]; then
    exit 1
fi
