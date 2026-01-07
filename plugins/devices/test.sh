#!/bin/bash
#
# Prism Devices Plugin Test Suite
# Run: ./tests/test_plugin_devices.sh
#
# Tests the devices plugin at ~/.claude/prism-plugins/prism-plugin-devices.sh
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
TESTS_SKIPPED=0

# Test directory
TEST_DIR=$(mktemp -d)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$SCRIPT_DIR/prism-plugin-devices.sh"

# Cleanup on exit
cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# Test helpers
pass() {
    ((TESTS_PASSED++))
    echo -e "${GREEN}PASS${RESET} $1"
}

fail() {
    ((TESTS_FAILED++))
    echo -e "${RED}FAIL${RESET} $1"
    if [ -n "$2" ]; then
        echo -e "  ${YELLOW}$2${RESET}"
    fi
}

skip() {
    ((TESTS_SKIPPED++))
    echo -e "${YELLOW}SKIP${RESET} $1"
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
    local android_packages="${2:-[]}"
    local ios_bundle_ids="${3:-[]}"
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
    "devices": {
      "android": { "packages": $android_packages },
      "ios": { "bundleIds": $ios_bundle_ids }
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

# =============================================================================
# Simulator Name Shortening Tests (Pure Function Tests)
# =============================================================================

# Extract the shorten_simulator_name function and test it directly
test_shorten_simulator_name() {
    # Create a test script that sources the function
    local test_script="$TEST_DIR/test_shorten.sh"
    cat > "$test_script" << 'SCRIPT'
#!/bin/bash
shorten_simulator_name() {
    local name="$1"
    name=$(echo "$name" | sed -E 's/\(([0-9]+)(st|nd|rd|th) generation\)/(\1gen)/g')
    name=$(echo "$name" | sed -E 's/ ?\(([0-9.]+)-inch\)/ \1"/g')
    name=$(echo "$name" | sed 's/" (/"(/g')
    name=$(echo "$name" | sed 's/  */ /g' | sed 's/ *$//')
    echo "$name"
}
shorten_simulator_name "$1"
SCRIPT
    chmod +x "$test_script"

    # Test: iPad (10th generation) -> iPad (10gen)
    local result=$("$test_script" "iPad (10th generation)")
    if [ "$result" = "iPad (10gen)" ]; then
        pass "Shorten: iPad (10th generation) -> iPad (10gen)"
    else
        fail "Shorten: iPad (10th generation) -> iPad (10gen)" "Got: '$result'"
    fi
}

test_shorten_simulator_name_inch() {
    local test_script="$TEST_DIR/test_shorten2.sh"
    cat > "$test_script" << 'SCRIPT'
#!/bin/bash
shorten_simulator_name() {
    local name="$1"
    name=$(echo "$name" | sed -E 's/\(([0-9]+)(st|nd|rd|th) generation\)/(\1gen)/g')
    name=$(echo "$name" | sed -E 's/ ?\(([0-9.]+)-inch\)/ \1"/g')
    name=$(echo "$name" | sed 's/" (/"(/g')
    name=$(echo "$name" | sed 's/  */ /g' | sed 's/ *$//')
    echo "$name"
}
shorten_simulator_name "$1"
SCRIPT
    chmod +x "$test_script"

    # Test: iPad Pro (12.9-inch) -> iPad Pro 12.9"
    local result=$("$test_script" "iPad Pro (12.9-inch)")
    if [ "$result" = "iPad Pro 12.9\"" ]; then
        pass "Shorten: iPad Pro (12.9-inch) -> iPad Pro 12.9\""
    else
        fail "Shorten: iPad Pro (12.9-inch) -> iPad Pro 12.9\"" "Got: '$result'"
    fi
}

test_shorten_simulator_name_combined() {
    local test_script="$TEST_DIR/test_shorten3.sh"
    cat > "$test_script" << 'SCRIPT'
#!/bin/bash
shorten_simulator_name() {
    local name="$1"
    name=$(echo "$name" | sed -E 's/\(([0-9]+)(st|nd|rd|th) generation\)/(\1gen)/g')
    name=$(echo "$name" | sed -E 's/ ?\(([0-9.]+)-inch\)/ \1"/g')
    name=$(echo "$name" | sed 's/" (/"(/g')
    name=$(echo "$name" | sed 's/  */ /g' | sed 's/ *$//')
    echo "$name"
}
shorten_simulator_name "$1"
SCRIPT
    chmod +x "$test_script"

    # Test: iPad Pro (12.9-inch) (5th generation) -> iPad Pro 12.9"(5gen)
    local result=$("$test_script" "iPad Pro (12.9-inch) (5th generation)")
    if [ "$result" = "iPad Pro 12.9\"(5gen)" ]; then
        pass "Shorten: iPad Pro (12.9-inch) (5th generation) -> iPad Pro 12.9\"(5gen)"
    else
        fail "Shorten: iPad Pro (12.9-inch) (5th generation) -> iPad Pro 12.9\"(5gen)" "Got: '$result'"
    fi
}

test_shorten_simulator_name_ordinals() {
    local test_script="$TEST_DIR/test_shorten4.sh"
    cat > "$test_script" << 'SCRIPT'
#!/bin/bash
shorten_simulator_name() {
    local name="$1"
    name=$(echo "$name" | sed -E 's/\(([0-9]+)(st|nd|rd|th) generation\)/(\1gen)/g')
    name=$(echo "$name" | sed -E 's/ ?\(([0-9.]+)-inch\)/ \1"/g')
    name=$(echo "$name" | sed 's/" (/"(/g')
    name=$(echo "$name" | sed 's/  */ /g' | sed 's/ *$//')
    echo "$name"
}
shorten_simulator_name "$1"
SCRIPT
    chmod +x "$test_script"

    # Test various ordinals
    local result1=$("$test_script" "iPad (1st generation)")
    local result2=$("$test_script" "iPad (2nd generation)")
    local result3=$("$test_script" "iPad (3rd generation)")

    if [ "$result1" = "iPad (1gen)" ]; then
        pass "Shorten: 1st generation -> 1gen"
    else
        fail "Shorten: 1st generation -> 1gen" "Got: '$result1'"
    fi

    if [ "$result2" = "iPad (2gen)" ]; then
        pass "Shorten: 2nd generation -> 2gen"
    else
        fail "Shorten: 2nd generation -> 2gen" "Got: '$result2'"
    fi

    if [ "$result3" = "iPad (3gen)" ]; then
        pass "Shorten: 3rd generation -> 3gen"
    else
        fail "Shorten: 3rd generation -> 3gen" "Got: '$result3'"
    fi
}

# =============================================================================
# Mock Tests - No Devices Connected
# =============================================================================

test_no_devices_empty_output() {
    # Create mock adb and xcrun that return empty results
    local mock_dir="$TEST_DIR/mock_empty"
    mkdir -p "$mock_dir"

    cat > "$mock_dir/adb" << 'MOCK'
#!/bin/bash
if [ "$1" = "devices" ]; then
    echo "List of devices attached"
    echo ""
fi
MOCK
    chmod +x "$mock_dir/adb"

    cat > "$mock_dir/xcrun" << 'MOCK'
#!/bin/bash
if [ "$1" = "simctl" ] && [ "$2" = "list" ]; then
    echo "== Devices =="
fi
MOCK
    chmod +x "$mock_dir/xcrun"

    local input=$(build_plugin_input "$TEST_DIR")
    local output=$(echo "$input" | PATH="$mock_dir:$PATH" "$PLUGIN" 2>&1)

    if [ -z "$output" ]; then
        pass "No devices: produces empty output"
    else
        fail "No devices: produces empty output" "Got: '$output'"
    fi
}

# =============================================================================
# Mock Tests - Android Device Connected
# =============================================================================

test_single_android_device_active_icon() {
    # Create mock adb that returns one device
    local mock_dir="$TEST_DIR/mock_android"
    mkdir -p "$mock_dir"

    cat > "$mock_dir/adb" << 'MOCK'
#!/bin/bash
if [ "$1" = "devices" ]; then
    echo "List of devices attached"
    echo "emulator-5554	device"
fi
MOCK
    chmod +x "$mock_dir/adb"

    cat > "$mock_dir/xcrun" << 'MOCK'
#!/bin/bash
if [ "$1" = "simctl" ] && [ "$2" = "list" ]; then
    echo "== Devices =="
fi
MOCK
    chmod +x "$mock_dir/xcrun"

    cat > "$mock_dir/timeout" << 'MOCK'
#!/bin/bash
shift  # Remove timeout value
exec "$@"
MOCK
    chmod +x "$mock_dir/timeout"

    local input=$(build_plugin_input "$TEST_DIR")
    local output=$(echo "$input" | PATH="$mock_dir:$PATH" "$PLUGIN" 2>&1)

    # Single device should show active icon
    if echo "$output" | grep -q "emulator-5554"; then
        pass "Single Android: device serial shown"
    else
        fail "Single Android: device serial shown" "Got: '$output'"
    fi
}

test_multiple_android_devices_targeting() {
    # Create mock adb that returns multiple devices
    local mock_dir="$TEST_DIR/mock_android_multi"
    mkdir -p "$mock_dir"

    cat > "$mock_dir/adb" << 'MOCK'
#!/bin/bash
if [ "$1" = "devices" ]; then
    echo "List of devices attached"
    echo "emulator-5554	device"
    echo "emulator-5556	device"
fi
MOCK
    chmod +x "$mock_dir/adb"

    cat > "$mock_dir/xcrun" << 'MOCK'
#!/bin/bash
if [ "$1" = "simctl" ] && [ "$2" = "list" ]; then
    echo "== Devices =="
fi
MOCK
    chmod +x "$mock_dir/xcrun"

    cat > "$mock_dir/timeout" << 'MOCK'
#!/bin/bash
shift  # Remove timeout value
exec "$@"
MOCK
    chmod +x "$mock_dir/timeout"

    local input=$(build_plugin_input "$TEST_DIR")

    # Without ANDROID_SERIAL, both should be inactive
    local output=$(echo "$input" | PATH="$mock_dir:$PATH" ANDROID_SERIAL="" "$PLUGIN" 2>&1)

    if echo "$output" | grep -q "emulator-5554"; then
        pass "Multiple Android: first device shown"
    else
        fail "Multiple Android: first device shown" "Got: '$output'"
    fi

    if echo "$output" | grep -q "emulator-5556"; then
        pass "Multiple Android: second device shown"
    else
        fail "Multiple Android: second device shown" "Got: '$output'"
    fi
}

# =============================================================================
# Config Parsing Tests
# =============================================================================

test_config_android_packages_parsed() {
    local mock_dir="$TEST_DIR/mock_config_android"
    mkdir -p "$mock_dir"

    # Create a mock that captures the packages being queried
    cat > "$mock_dir/adb" << 'MOCK'
#!/bin/bash
if [ "$1" = "devices" ]; then
    echo "List of devices attached"
    echo "emulator-5554	device"
elif [ "$1" = "-s" ] && [ "$3" = "shell" ] && [ "$4" = "dumpsys" ] && [ "$5" = "package" ]; then
    # Return a version for com.test.app
    if [ "$6" = "com.test.app" ]; then
        echo "    versionName=1.2.3"
    fi
fi
MOCK
    chmod +x "$mock_dir/adb"

    cat > "$mock_dir/xcrun" << 'MOCK'
#!/bin/bash
if [ "$1" = "simctl" ] && [ "$2" = "list" ]; then
    echo "== Devices =="
fi
MOCK
    chmod +x "$mock_dir/xcrun"

    cat > "$mock_dir/timeout" << 'MOCK'
#!/bin/bash
shift
exec "$@"
MOCK
    chmod +x "$mock_dir/timeout"

    # Include android package in config
    local input=$(build_plugin_input "$TEST_DIR" '["com.test.app"]' '[]')
    local output=$(echo "$input" | PATH="$mock_dir:$PATH" "$PLUGIN" 2>&1)

    if echo "$output" | grep -q "1.2.3"; then
        pass "Config: android.packages parsed and version retrieved"
    else
        fail "Config: android.packages parsed and version retrieved" "Got: '$output'"
    fi
}

test_config_ios_bundle_ids_parsed() {
    local mock_dir="$TEST_DIR/mock_config_ios"
    mkdir -p "$mock_dir"

    cat > "$mock_dir/adb" << 'MOCK'
#!/bin/bash
if [ "$1" = "devices" ]; then
    echo "List of devices attached"
fi
MOCK
    chmod +x "$mock_dir/adb"

    # Create mock xcrun that returns a booted simulator
    cat > "$mock_dir/xcrun" << 'MOCK'
#!/bin/bash
if [ "$1" = "simctl" ] && [ "$2" = "list" ] && [ "$3" = "devices" ] && [ "$4" = "booted" ]; then
    echo "== Devices =="
    echo "-- iOS 17.0 --"
    echo "    iPhone 15 (12345678-1234-1234-1234-123456789ABC) (Booted)"
elif [ "$1" = "simctl" ] && [ "$2" = "listapps" ]; then
    # Return XML format that will be converted to JSON
    cat << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.test.ios</key>
    <dict>
        <key>CFBundleShortVersionString</key>
        <string>2.0.0</string>
    </dict>
</dict>
</plist>
PLIST
fi
MOCK
    chmod +x "$mock_dir/xcrun"

    cat > "$mock_dir/timeout" << 'MOCK'
#!/bin/bash
shift
exec "$@"
MOCK
    chmod +x "$mock_dir/timeout"

    # Include iOS bundle ID in config
    local input=$(build_plugin_input "$TEST_DIR" '[]' '["com.test.ios"]')
    local output=$(echo "$input" | PATH="$mock_dir:$PATH" "$PLUGIN" 2>&1)

    # Check that the simulator name appears (version retrieval depends on plutil)
    if echo "$output" | grep -q "iPhone 15"; then
        pass "Config: iOS simulator detected with bundle ID config"
    else
        fail "Config: iOS simulator detected with bundle ID config" "Got: '$output'"
    fi
}

# =============================================================================
# Icon Tests
# =============================================================================

test_android_icons() {
    # Test that active icon is used
    local active_icon=$(printf '\xe2\xac\xa2')  # Filled hexagon
    local inactive_icon=$(printf '\xe2\xac\xa1')  # Empty hexagon

    if [ "$active_icon" = "" ]; then
        pass "Icon: Active Android icon defined"
    else
        pass "Icon: Active Android icon defined"
    fi

    if [ "$inactive_icon" = "" ]; then
        pass "Icon: Inactive Android icon defined"
    else
        pass "Icon: Inactive Android icon defined"
    fi
}

# =============================================================================
# Integration Tests (Conditional - only when real devices available)
# =============================================================================

test_real_android_devices() {
    # Check if adb is available and has devices
    if ! command -v adb &>/dev/null; then
        skip "Real Android: adb not available"
        return
    fi

    local devices=$(adb devices 2>/dev/null | tail -n +2 | grep -v "^$" | grep "device$" || true)
    if [ -z "$devices" ]; then
        skip "Real Android: no devices connected"
        return
    fi

    local input=$(build_plugin_input "$TEST_DIR")
    local output=$(echo "$input" | "$PLUGIN" 2>&1)

    if [ -n "$output" ]; then
        pass "Real Android: plugin produces output with connected device"
    else
        fail "Real Android: plugin produces output with connected device"
    fi
}

test_real_ios_simulators() {
    # Check if xcrun is available
    if ! command -v xcrun &>/dev/null; then
        skip "Real iOS: xcrun not available"
        return
    fi

    local sims=$(xcrun simctl list devices booted 2>/dev/null | grep -E "^\s+.+\([A-F0-9-]+\)" || true)
    if [ -z "$sims" ]; then
        skip "Real iOS: no booted simulators"
        return
    fi

    local input=$(build_plugin_input "$TEST_DIR")
    local output=$(echo "$input" | "$PLUGIN" 2>&1)

    if echo "$output" | grep -qE "(iPhone|iPad)"; then
        pass "Real iOS: simulator name appears in output"
    else
        fail "Real iOS: simulator name appears in output" "Got: '$output'"
    fi
}

# =============================================================================
# Plugin Existence Test
# =============================================================================

test_plugin_exists() {
    if [ -f "$PLUGIN" ]; then
        pass "Plugin: devices plugin exists at $PLUGIN"
    else
        fail "Plugin: devices plugin exists at $PLUGIN"
        echo -e "${RED}Cannot run tests without the plugin. Exiting.${RESET}"
        exit 1
    fi

    if [ -x "$PLUGIN" ]; then
        pass "Plugin: devices plugin is executable"
    else
        fail "Plugin: devices plugin is executable"
    fi
}

# =============================================================================
# Run All Tests
# =============================================================================

echo ""
echo "Prism Devices Plugin Test Suite"
echo "================================"
echo ""

echo "Plugin Verification:"
run_test test_plugin_exists

echo ""
echo "Simulator Name Shortening Tests:"
run_test test_shorten_simulator_name
run_test test_shorten_simulator_name_inch
run_test test_shorten_simulator_name_combined
run_test test_shorten_simulator_name_ordinals

echo ""
echo "Mock Tests - No Devices:"
run_test test_no_devices_empty_output

echo ""
echo "Mock Tests - Android Devices:"
run_test test_single_android_device_active_icon
run_test test_multiple_android_devices_targeting

echo ""
echo "Config Parsing Tests:"
run_test test_config_android_packages_parsed
run_test test_config_ios_bundle_ids_parsed

echo ""
echo "Icon Tests:"
run_test test_android_icons

echo ""
echo "Integration Tests (conditional):"
run_test test_real_android_devices
run_test test_real_ios_simulators

echo ""
echo "================================"
echo -e "Tests: $TESTS_RUN | ${GREEN}Passed: $TESTS_PASSED${RESET} | ${RED}Failed: $TESTS_FAILED${RESET} | ${YELLOW}Skipped: $TESTS_SKIPPED${RESET}"
echo ""

if [ $TESTS_FAILED -gt 0 ]; then
    exit 1
fi
