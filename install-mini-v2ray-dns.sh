#!/usr/bin/env bash
# SULTAN VIP MINI LAUNCHER
# ضع هذا الملف في GitHub باسم: install-mini.sh
# هذا الملف يحمل السيرفر الكامل: sultan.sh

set -e

USER_NAME="sultanmuhamad736-maker"
REPO_NAME="Sultanmaker"
BRANCH_NAME="main"
FULL_FILE="sultan.sh"

RAW_URL="https://raw.githubusercontent.com/${USER_NAME}/${REPO_NAME}/${BRANCH_NAME}/${FULL_FILE}"
LOCAL_FILE="/root/${FULL_FILE}"

echo "=================================================="
echo "        SULTAN VIP MINI LAUNCHER"
echo "        Downloading full server file..."
echo "=================================================="
echo "URL: ${RAW_URL}"
echo ""

if ! command -v curl >/dev/null 2>&1; then
  apt update -y
  apt install -y curl
fi

curl -fL --retry 3 --connect-timeout 15 "${RAW_URL}" -o "${LOCAL_FILE}"

chmod +x "${LOCAL_FILE}"

echo ""
echo "Full server downloaded to: ${LOCAL_FILE}"
echo "Starting SULTAN VIP SERVER..."
echo "=================================================="
echo ""

bash "${LOCAL_FILE}" "$@"
