#!/bin/bash
# Setup script to configure git hooks for this repository

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

echo "Setting up git hooks..."

# Configure git to use .githooks directory
git config core.hooksPath .githooks

# Make hooks executable
chmod +x "$SCRIPT_DIR"/*

echo "Git hooks configured successfully!"
echo "Hooks will run automatically on commit."
