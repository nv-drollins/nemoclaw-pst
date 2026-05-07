#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SANDBOX="${NEMOCLAW_SANDBOX_NAME:-pst-agent}"
RUN_SMOKE=1
SHOW_TOKEN=1

usage() {
  cat <<EOF
Usage: $0 [--sandbox NAME] [--no-smoke] [--no-token]

Starts the self-contained NemoClaw PST demo:
  - installs host pst-utils if needed
  - starts the bundled sample PST service
  - applies sandbox egress policy
  - installs the OpenClaw PST skill
  - prepares OpenClaw's Node runtime for local inference
  - prints dashboard URL and token

Options:
  --sandbox NAME   NemoClaw sandbox name. Default: $SANDBOX
      --no-smoke       Skip PST service smoke checks.
  --no-token       Print dashboard URL without printing token.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --sandbox)
      SANDBOX="${2:?missing sandbox name}"
      shift
      ;;
    --no-smoke) RUN_SMOKE=0 ;;
    --no-token) SHOW_TOKEN=0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

export NEMOCLAW_SANDBOX_NAME="$SANDBOX"
export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"

echo "[1/5] Checking host prerequisites"
"$SCRIPT_DIR/install-host-prereqs.sh"

echo "[2/5] Starting PST service"
"$SCRIPT_DIR/start-pst-server.sh"

echo "[3/5] Installing PST skill and policy"
"$SCRIPT_DIR/install-pst-skill.sh" "$SANDBOX"

echo "[4/5] Preparing OpenClaw Node inference route"
"$SCRIPT_DIR/prepare-openclaw-node-inference.sh" "$SANDBOX"

if [ "$RUN_SMOKE" -eq 1 ]; then
  echo
  echo "[smoke] PST service checks"
  "$SCRIPT_DIR/run-pst-smoke.sh" --sandbox "$SANDBOX"
fi

echo
echo "[5/5] OpenClaw dashboard"
if [ "$SHOW_TOKEN" -eq 1 ]; then
  "$SCRIPT_DIR/show-openclaw-dashboard.sh" --sandbox "$SANDBOX" --show-token
else
  "$SCRIPT_DIR/show-openclaw-dashboard.sh" --sandbox "$SANDBOX"
fi

cat <<EOF

Try this prompt in OpenClaw:
  What folders are in my PST mailbox, and how many emails are in each folder?
EOF
