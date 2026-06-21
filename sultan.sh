#!/bin/bash
set -e

REPO="https://raw.githubusercontent.com/sultanmuhamad736-maker/Sultanmaker/main"
MAIN="sultan.sh"

if [ "$(id -u)" != "0" ]; then
  echo "Run as root."
  exit 1
fi

apt update -y
apt install -y curl bash

curl -fL -o /tmp/sultan.sh "$REPO/$MAIN"
chmod +x /tmp/sultan.sh
bash /tmp/sultan.sh
