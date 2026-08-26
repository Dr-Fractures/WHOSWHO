#!/usr/bin/env bash
#
# install.sh - installs (or removes) whoswho as a system-wide command
#
# USAGE:
#   ./install.sh            install
#   ./install.sh --remove   uninstall
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="${REPO_DIR}/whoswho.sh"
LINK_PATH="/usr/local/bin/whoswho"

do_link() {
    if [[ -w /usr/local/bin ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

if [[ "${1:-}" == "--remove" ]]; then
    if [[ -L "$LINK_PATH" || -f "$LINK_PATH" ]]; then
        do_link rm -f "$LINK_PATH"
        echo "Removed $LINK_PATH"
    else
        echo "Nothing to remove at $LINK_PATH"
    fi
    exit 0
fi

if [[ ! -f "$SCRIPT_PATH" ]]; then
    echo "Error: whoswho.sh not found in $REPO_DIR"
    exit 1
fi

chmod +x "$SCRIPT_PATH"

echo "Installing whoswho to $LINK_PATH ..."
do_link ln -sf "$SCRIPT_PATH" "$LINK_PATH"

if command -v whoswho >/dev/null 2>&1; then
    echo "Done. Run it from anywhere with: whoswho"
    echo "(use 'sudo whoswho' for full SYN-scan / OS-detection capability)"
    echo "To uninstall: ./install.sh --remove"
else
    echo "Install finished, but 'whoswho' isn't on your PATH yet."
    echo "Make sure /usr/local/bin is in your PATH, or run directly with: $SCRIPT_PATH"
fi
