#!/bin/bash
# Run Prism test suite
exec "$(dirname "$0")/tests/test_prism.sh" "$@"
