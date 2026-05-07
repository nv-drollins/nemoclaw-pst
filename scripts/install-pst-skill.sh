#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=resolve-demo-root.sh
. "$SCRIPT_DIR/resolve-demo-root.sh"
ROOT="$(resolve_demo_root "$SCRIPT_DIR")"
SANDBOX="${1:-${NEMOCLAW_SANDBOX_NAME:-pst-agent}}"

export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"

if ! command -v nemoclaw >/dev/null 2>&1; then
  echo "Missing nemoclaw. Run ./scripts/onboard-nemoclaw.sh first." >&2
  exit 1
fi

if ! openshell sandbox get "$SANDBOX" >/dev/null 2>&1; then
  echo "Sandbox '$SANDBOX' was not found. Run ./scripts/onboard-nemoclaw.sh first." >&2
  exit 1
fi

"$SCRIPT_DIR/apply-pst-policy.sh" "$SANDBOX"
nemoclaw "$SANDBOX" skill install "$ROOT/skills/pst-mail"

echo "PST skill installed in sandbox $SANDBOX"
