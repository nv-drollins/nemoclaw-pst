#!/usr/bin/env bash
set -euo pipefail

SANDBOX="${NEMOCLAW_SANDBOX_NAME:-pst-agent}"
SHOW_TOKEN=0

usage() {
  cat <<EOF
Usage: $0 [--sandbox NAME] [--show-token]

Prints the OpenClaw dashboard URL by running 'openclaw dashboard --no-open'
inside the NemoClaw sandbox.

Options:
  --sandbox NAME   NemoClaw sandbox name. Default: $SANDBOX
  --show-token     Also print the gateway token in this terminal.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --sandbox)
      SANDBOX="${2:?missing sandbox name}"
      shift
      ;;
    --show-token) SHOW_TOKEN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

need nemoclaw
need openshell
need ssh

SSH_CONFIG="/tmp/${SANDBOX}.ssh_config"
openshell sandbox ssh-config "$SANDBOX" > "$SSH_CONFIG"

echo "OpenClaw dashboard:"
ssh -F "$SSH_CONFIG" "openshell-$SANDBOX" env NODE_NO_WARNINGS=1 openclaw dashboard --no-open

echo
if [ "$SHOW_TOKEN" -eq 1 ]; then
  echo "Gateway token:"
  nemoclaw "$SANDBOX" gateway-token --quiet
else
  cat <<EOF
Gateway token:
  nemoclaw $SANDBOX gateway-token --quiet

To print the token now:
  ./scripts/show-openclaw-dashboard.sh --sandbox $SANDBOX --show-token
EOF
fi
