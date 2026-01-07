#!/bin/bash
# Prism Plugin: Devices
# Shows connected Android devices and iOS simulators with optional app versions
#
# Config in prism.json:
#   "plugins": {
#     "devices": {
#       "android": { "packages": ["com.myapp.debug", "com.myapp.*"] },
#       "ios": { "bundleIds": ["com.myapp.debug"] }
#     }
#   }
#
# Output: ⬢ device:version · ⬡ device2 ·  iPhone:version

set -e

# Read input JSON
INPUT=$(cat)

# Parse input
PROJECT_DIR=$(echo "$INPUT" | jq -r '.prism.project_dir')
BLUE=$(echo "$INPUT" | jq -r '.colors.blue')
RESET=$(echo "$INPUT" | jq -r '.colors.reset')

# Get device config (check both old location and new plugins location)
ANDROID_PACKAGES=$(echo "$INPUT" | jq -r '.config.devices.android.packages // [] | .[]' 2>/dev/null)
IOS_BUNDLE_IDS=$(echo "$INPUT" | jq -r '.config.devices.ios.bundleIds // [] | .[]' 2>/dev/null)

# Icons
ANDROID_ICON_ACTIVE='⬢'
ANDROID_ICON_INACTIVE='⬡'
IOS_ICON=$(printf '\xEF\xA3\xBF')  # Apple logo
DEVICE_DIVIDER=' · '

# Cache settings
ANDROID_VERSION_CACHE="/tmp/prism-android-versions"
IOS_VERSION_CACHE="/tmp/prism-ios-versions"
CACHE_MAX_AGE=30

# Get version for Android package
get_android_version() {
    local serial=$1
    local pkg=$2
    timeout 2 adb -s "$serial" shell dumpsys package "$pkg" 2>/dev/null | grep "versionName=" | head -1 | sed 's/.*versionName=//' | tr -d '[:space:]'
}

# Find packages matching glob pattern
find_matching_packages() {
    local serial=$1
    local pattern=$2
    local regex=$(echo "$pattern" | sed 's/\./\\./g' | sed 's/\*/.*/g')
    timeout 2 adb -s "$serial" shell pm list packages 2>/dev/null | sed 's/package://' | grep -E "^${regex}$"
}

# Get app version for Android device
get_android_app_version() {
    local serial=$1
    [ -z "$ANDROID_PACKAGES" ] && return

    for pattern in $ANDROID_PACKAGES; do
        if [[ "$pattern" == *"*"* ]]; then
            local matches=$(find_matching_packages "$serial" "$pattern")
            for pkg in $matches; do
                local ver=$(get_android_version "$serial" "$pkg")
                [ -n "$ver" ] && echo "$ver" && return
            done
        else
            local ver=$(get_android_version "$serial" "$pattern")
            [ -n "$ver" ] && echo "$ver" && return
        fi
    done
    echo "--"
}

# Shorten simulator names
shorten_simulator_name() {
    local name="$1"
    name=$(echo "$name" | sed -E 's/\(([0-9]+)(st|nd|rd|th) generation\)/(\1gen)/g')
    name=$(echo "$name" | sed -E 's/ ?\(([0-9.]+)-inch\)/ \1"/g')
    name=$(echo "$name" | sed 's/" (/"(/g')
    name=$(echo "$name" | sed 's/  */ /g' | sed 's/ *$//')
    echo "$name"
}

# Get iOS app version
get_ios_app_version() {
    local udid=$1
    [ -z "$IOS_BUNDLE_IDS" ] && return

    local apps_json=$(xcrun simctl listapps "$udid" 2>/dev/null | plutil -convert json -o - -)

    for pattern in $IOS_BUNDLE_IDS; do
        if [[ "$pattern" == *"*"* ]]; then
            local regex=$(echo "$pattern" | sed 's/\./\\./g' | sed 's/\*/.*/g')
            local matching_ids=$(echo "$apps_json" | jq -r 'keys[]' 2>/dev/null | grep -E "^${regex}$")
            for bid in $matching_ids; do
                local ver=$(echo "$apps_json" | jq -r --arg bid "$bid" '.[$bid].CFBundleShortVersionString // .[$bid].CFBundleVersion // empty' 2>/dev/null)
                [ -n "$ver" ] && echo "$ver" && return
            done
        else
            local ver=$(echo "$apps_json" | jq -r --arg bid "$pattern" '.[$bid].CFBundleShortVersionString // .[$bid].CFBundleVersion // empty' 2>/dev/null)
            [ -n "$ver" ] && echo "$ver" && return
        fi
    done
    echo "--"
}

# Build Android device list
build_android_devices() {
    local android_lines=$(timeout 1 adb devices 2>/dev/null | tail -n +2 | grep -v "^$" | grep "device$")
    local serials=$(echo "$android_lines" | cut -f1 | grep -v "^$")
    local serial_count=$(echo "$serials" | grep -c . 2>/dev/null || echo 0)

    [ -z "$serials" ] && return

    local result=""
    for serial in $serials; do
        local icon="$ANDROID_ICON_INACTIVE"
        if [ "$serial" = "$ANDROID_SERIAL" ] || [ "$serial_count" -eq 1 ]; then
            icon="$ANDROID_ICON_ACTIVE"
        fi
        local ver=$(get_android_app_version "$serial")
        local device_info="${icon} ${serial}"
        [ -n "$ver" ] && device_info="${device_info}:${ver}"

        [ -n "$result" ] && result="${result}${DEVICE_DIVIDER}"
        result="${result}${device_info}"
    done
    echo "$result"
}

# Build iOS simulator list
build_ios_simulators() {
    local sims=$(xcrun simctl list devices booted 2>/dev/null | grep -E "^\s+.+\([A-F0-9-]+\)" | sed 's/^[[:space:]]*//' | sed 's/ (Booted)//')
    [ -z "$sims" ] && return

    echo "$sims" | while read -r line; do
        local name=$(echo "$line" | sed 's/ ([A-F0-9-]*)$//')
        name=$(shorten_simulator_name "$name")
        local udid=$(echo "$line" | sed 's/.*(\([A-F0-9-]*\))$/\1/')

        local ver=$(get_ios_app_version "$udid")
        if [ -n "$ver" ]; then
            echo "${IOS_ICON} ${name}:${ver}"
        else
            echo "${IOS_ICON} ${name}"
        fi
    done | tr '\n' '|' | sed 's/|$//; s/|/ · /g'
}

# Build device list
android_devices=$(build_android_devices)
ios_devices=$(build_ios_simulators)

output=""
[ -n "$android_devices" ] && output="$android_devices"
if [ -n "$ios_devices" ]; then
    [ -n "$output" ] && output="${output}${DEVICE_DIVIDER}"
    output="${output}${ios_devices}"
fi

if [ -n "$output" ]; then
    echo -e "${BLUE}${output}${RESET}"
fi
