#!/bin/bash
# Prism Plugin: Xcode
# Shows Xcode build status in Xcode projects
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
