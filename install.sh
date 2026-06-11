#!/usr/bin/env bash
# shai installer bootstrapper
#
# Usage:
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/zeddius1983/shell-assistant/main/install.sh)"
#
#   Silent / Non-interactive:
#   curl -fsSL https://raw.githubusercontent.com/zeddius1983/shell-assistant/main/install.sh | bash -s -- --all

set -euo pipefail

REPO_URL="https://raw.githubusercontent.com/zeddius1983/shell-assistant/main"
TMP_DIR="$(mktemp -d)"

# Cleanup on exit
trap 'rm -rf "$TMP_DIR"' EXIT

echo "==> Downloading Shai Toolbox Installer..."
mkdir -p "$TMP_DIR/shell"

curl -sSLo "$TMP_DIR/shell/setup.sh" "$REPO_URL/shell/setup.sh"
chmod +x "$TMP_DIR/shell/setup.sh"

"$TMP_DIR/shell/setup.sh" "$@"
