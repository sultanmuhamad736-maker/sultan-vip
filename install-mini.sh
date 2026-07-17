#!/bin/bash
set -e

SCRIPT_URL="https://raw.githubusercontent.com/sultanmuhamad736-maker/sultan-vip/main/sultan-auto-install.sh"
SCRIPT_PATH="/tmp/sultan-vip.sh"

curl -fsSL "$SCRIPT_URL" -o "$SCRIPT_PATH"
chmod +x "$SCRIPT_PATH"

exec "$SCRIPT_PATH" "$@"
