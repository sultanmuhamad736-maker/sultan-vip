#!/bin/bash
set -e

REPO="https://raw.githubusercontent.com/sultanmuhamad736-maker/sultan-vip/main"
MAIN="sultan-vip.sh"

if [ "$(id -u)" != "0" ]; then
  echo "Run as root."
  exit 1
fi

apt update -y
apt install -y curl bash

curl -fL -o /tmp/sultan-vip.sh "$REPO/$MAIN"
chmod +x /tmp/sultan-vip.sh
bash /tmp/sultan-vip.sh
