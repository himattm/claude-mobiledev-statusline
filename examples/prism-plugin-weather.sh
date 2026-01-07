#!/bin/bash
# Prism Plugin: Weather (Example)
# Shows current temperature for a configured location
#
# This is an example plugin demonstrating the Prism plugin interface.
# Copy to ~/.claude/prism-plugins/ and customize for your needs.
#
# Config in .claude/prism.json:
#   {
#     "sections": ["dir", "model", "weather", "git"],
#     "plugins": {
#       "weather": {
#         "location": "San Francisco",
#         "units": "imperial"
#       }
#     }
#   }
#
# Plugin Interface:
# - INPUT:  JSON on stdin with prism context, session info, config, and colors
# - OUTPUT: Formatted text with ANSI codes on stdout
# - Exit 0 with output to show section
# - Exit 0 with no output to hide section
# - Exit non-zero on error (section hidden, error logged)

set -e

# Read full input JSON from stdin
INPUT=$(cat)

# Parse plugin config (with defaults)
LOCATION=$(echo "$INPUT" | jq -r '.config.weather.location // "New York"')
UNITS=$(echo "$INPUT" | jq -r '.config.weather.units // "imperial"')

# Parse colors for consistent styling
CYAN=$(echo "$INPUT" | jq -r '.colors.cyan')
GRAY=$(echo "$INPUT" | jq -r '.colors.gray')
RESET=$(echo "$INPUT" | jq -r '.colors.reset')

# Check if session is idle (safe to run expensive operations)
IS_IDLE=$(echo "$INPUT" | jq -r '.prism.is_idle')

# Cache file for weather data (avoid hitting API on every status update)
CACHE="/tmp/prism-weather-cache"
CACHE_MAX_AGE=300  # 5 minutes

# Check cache first
if [ -f "$CACHE" ]; then
    cache_age=$(($(date +%s) - $(stat -f %m "$CACHE" 2>/dev/null || echo 0)))
    if [ "$cache_age" -lt "$CACHE_MAX_AGE" ]; then
        cat "$CACHE"
        exit 0
    fi
fi

# Only fetch new data when session is idle
if [ "$IS_IDLE" != "true" ]; then
    # Return cached value or nothing when busy
    [ -f "$CACHE" ] && cat "$CACHE"
    exit 0
fi

# Fetch weather (using wttr.in for simplicity)
# In a real plugin, you might use a proper weather API
TEMP=$(timeout 2 curl -sf "wttr.in/${LOCATION}?format=%t" 2>/dev/null || echo "")

# Exit silently if fetch failed (section will be hidden)
[ -z "$TEMP" ] && exit 0

# Format and cache the output
OUTPUT="${CYAN}${TEMP}${RESET}"
echo "$OUTPUT" > "$CACHE"

# Output the formatted section
echo -e "$OUTPUT"
