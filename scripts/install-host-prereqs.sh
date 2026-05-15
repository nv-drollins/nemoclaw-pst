#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if command -v readpst >/dev/null 2>&1; then
  echo "readpst already installed"
  exit 0
fi

echo "Installing pst-utils for ARM-native PST parsing"
bash "$SCRIPT_DIR/ensure-sudo.sh"

sudo apt-get update
sudo apt-get install -y pst-utils
