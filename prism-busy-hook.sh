#!/bin/bash
# Prism hook: Mark session as busy when user submits a prompt
SESSION_ID=$(jq -r '.session_id // empty' 2>/dev/null)
if [ -n "$SESSION_ID" ]; then
    rm -f "/tmp/prism-idle-${SESSION_ID}"
fi
