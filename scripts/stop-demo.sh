#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=resolve-demo-root.sh
. "$SCRIPT_DIR/resolve-demo-root.sh"
ROOT="$(resolve_demo_root "$SCRIPT_DIR")"
PID_FILE="$ROOT/logs/pst-server.pid"

"$SCRIPT_DIR/stop-dashboard-forward.sh" "${NEMOCLAW_SANDBOX_NAME:-pst-agent}" >/dev/null 2>&1 || true

if [ -f "$PID_FILE" ]; then
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    echo "Stopping PST server pid $pid"
    kill "$pid" 2>/dev/null || true
  fi
  rm -f "$PID_FILE"
fi

echo "PST demo stopped."
