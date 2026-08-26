#!/usr/bin/env bash
#
# install.sh - installs whoswho as a system-wide command
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="${REPO_DIR}/whoswho.sh"
LINK_PATH="/usr/local/bin/whoswho"

if [[ ! -f "$SCRIPT_PATH" ]]; then
    echo "Error: whoswho.sh not found in $REPO_DIR"
    exit 1
fi

chmod +x "$SCRIPT_PATH"

echo "Installing whoswho to $LINK_PATH ..."
if [[ -w /usr/local/bin ]]; then
    ln -sf "$SCRIPT_PATH" "$LINK_PATH"
else
    sudo ln -sf "$SCRIPT_PATH" "$LINK_PATH"
fi

if command -v whoswho >/dev/null 2>&1; then
    echo "Done. Run it from anywhere with: whoswho"
    echo "(use 'sudo whoswho' for full SYN-scan / OS-detection capability)"
else
    echo "Install finished, but 'whoswho' isn't on your PATH yet."
    echo "Make sure /usr/local/bin is in your PATH, or run directly with: $SCRIPT_PATH"
fi
