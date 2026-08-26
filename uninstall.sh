#!/usr/bin/env bash
#
# uninstall.sh - removes the whoswho symlink from /usr/local/bin
#
set -euo pipefail

LINK_PATH="/usr/local/bin/whoswho"

if [[ -L "$LINK_PATH" || -f "$LINK_PATH" ]]; then
    if [[ -w /usr/local/bin ]]; then
        rm -f "$LINK_PATH"
    else
        sudo rm -f "$LINK_PATH"
    fi
    echo "Removed $LINK_PATH"
else
    echo "Nothing to remove at $LINK_PATH"
fi
