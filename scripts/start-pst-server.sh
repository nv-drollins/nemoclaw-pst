#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=resolve-demo-root.sh
. "$SCRIPT_DIR/resolve-demo-root.sh"
ROOT="$(resolve_demo_root "$SCRIPT_DIR")"
PORT="${PST_SERVER_PORT:-9003}"
PID_FILE="$ROOT/logs/pst-server.pid"
LOG_FILE="$ROOT/logs/pst-server.log"

mkdir -p "$ROOT/logs"

if [ -f "$PID_FILE" ]; then
  old_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
    echo "PST server already running on pid $old_pid"
    exit 0
  fi
  rm -f "$PID_FILE"
fi

if command -v lsof >/dev/null 2>&1; then
  existing="$(lsof -ti ":$PORT" 2>/dev/null || true)"
  if [ -n "$existing" ]; then
    echo "Stopping existing process on port $PORT: $existing"
    for pid in $existing; do
      kill "$pid" 2>/dev/null || true
    done
    sleep 1
  fi
fi

if ! command -v readpst >/dev/null 2>&1; then
  echo "Missing readpst. Run ./scripts/install-host-prereqs.sh" >&2
  exit 1
fi

nohup python3 "$ROOT/server/pst_rest_server.py" --port "$PORT" \
  > "$LOG_FILE" 2>&1 &
echo $! > "$PID_FILE"

for _ in $(seq 1 20); do
  if curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
    echo "PST server running at http://127.0.0.1:$PORT"
    exit 0
  fi
  sleep 1
done

echo "PST server did not become healthy" >&2
tail -80 "$LOG_FILE" >&2 || true
exit 1
