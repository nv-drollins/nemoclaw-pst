#!/usr/bin/env bash
set -euo pipefail

if command -v readpst >/dev/null 2>&1; then
  echo "readpst already installed"
  exit 0
fi

echo "Installing pst-utils for ARM-native PST parsing"
sudo apt-get update
sudo apt-get install -y pst-utils
