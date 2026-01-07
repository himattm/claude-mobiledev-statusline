#!/bin/bash
# Prism Plugin: Gradle
# Shows Gradle daemon status in Gradle projects
#
# Output: daemon icon with count (e.g., 𓃰3) or ? if no daemon running
# Only shows in projects with build.gradle or settings.gradle

set -e

# Read input JSON
INPUT=$(cat)

# Parse input
PROJECT_DIR=$(echo "$INPUT" | jq -r '.prism.project_dir')
GREEN=$(echo "$INPUT" | jq -r '.colors.green')
RESET=$(echo "$INPUT" | jq -r '.colors.reset')

# Gradle icon
GRADLE_ICON='𓃰'

# Only check in Gradle projects
if [ ! -f "${PROJECT_DIR}/build.gradle" ] && \
   [ ! -f "${PROJECT_DIR}/build.gradle.kts" ] && \
   [ ! -f "${PROJECT_DIR}/settings.gradle" ] && \
   [ ! -f "${PROJECT_DIR}/settings.gradle.kts" ]; then
    exit 0
fi

# Count running Gradle daemons
daemon_count=$(pgrep -f "GradleDaemon" 2>/dev/null | wc -l | tr -d ' ')

if [ "$daemon_count" -gt 0 ]; then
    echo -e "${GREEN}${GRADLE_ICON}${daemon_count}${RESET}"
else
    echo -e "${GREEN}${GRADLE_ICON}?${RESET}"
fi
