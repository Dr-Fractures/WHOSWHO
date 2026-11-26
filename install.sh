#!/usr/bin/env bash
#
# install.sh - installs whoswho.sh as a system-wide 'whoswho' command
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="/usr/local/bin/whoswho"

if [[ $EUID -ne 0 ]]; then
    echo "[!] Run this installer with sudo." >&2
    exit 1
fi

chmod +x "$SCRIPT_DIR/whoswho.sh"
ln -sf "$SCRIPT_DIR/whoswho.sh" "$TARGET"

echo "[*] Installed. Symlinked $SCRIPT_DIR/whoswho.sh -> $TARGET"
echo "[*] Run with: sudo whoswho"
