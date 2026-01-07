#!/bin/bash
# @prism-plugin
# @name xcode
# @version 1.0.0
# @description Shows Xcode build status in Xcode projects
# @author Prism
# @source https://github.com/himattm/prism
# @update-url https://raw.githubusercontent.com/himattm/prism/main/plugins/xcode/prism-plugin-xcode.sh
#
# Output: hammer icon with count (e.g., ⚒2) or just icon if no builds
# Only shows in projects with .xcodeproj or .xcworkspace

set -e

# Read input JSON
INPUT=$(cat)

# Parse input
PROJECT_DIR=$(echo "$INPUT" | jq -r '.prism.project_dir')
CYAN=$(echo "$INPUT" | jq -r '.colors.cyan')
RESET=$(echo "$INPUT" | jq -r '.colors.reset')

# Xcode icon
XCODE_ICON='⚒'

# Only check in Xcode projects
if ! ls "${PROJECT_DIR}"/*.xcodeproj >/dev/null 2>&1 && \
   ! ls "${PROJECT_DIR}"/*.xcworkspace >/dev/null 2>&1; then
    exit 0
fi

# Count running xcodebuild processes
build_count=$(pgrep -f "xcodebuild" 2>/dev/null | wc -l | tr -d ' ')

if [ "$build_count" -gt 0 ]; then
    echo -e "${CYAN}${XCODE_ICON}${build_count}${RESET}"
else
    echo -e "${CYAN}${XCODE_ICON}${RESET}"
fi
