#!/bin/bash
# Prism hook: Mark session as idle when Claude stops responding
SESSION_ID=$(jq -r '.session_id // empty' 2>/dev/null)
if [ -n "$SESSION_ID" ]; then
    touch "/tmp/prism-idle-${SESSION_ID}"
fi
