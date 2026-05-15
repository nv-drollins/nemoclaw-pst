#!/usr/bin/env bash
set -euo pipefail

CERT_FILE="${NEMOCLAW_INFERENCE_CA_CERT:-/tmp/nemoclaw-inference-chain.pem}"

source /tmp/nemoclaw-proxy-env.sh 2>/dev/null || true

restart_gateway() {
  local gateway_pids
  gateway_pids="$(ps -eo pid=,comm= | awk '$2 == "openclaw-gatewa" { print $1 }')"
  if [ -n "$gateway_pids" ]; then
    # shellcheck disable=SC2086
    kill $gateway_pids 2>/dev/null || true
  fi
  sleep 2

  nohup openclaw gateway >>/tmp/gateway.log 2>&1 &
  sleep 5

  if ! ps -eo comm= | grep -q '^openclaw-gatewa$'; then
    echo "OpenClaw gateway did not restart cleanly." >&2
    tail -80 /tmp/gateway.log >&2 || true
    exit 1
  fi
}

proxy="${HTTPS_PROXY:-${https_proxy:-${HTTP_PROXY:-${http_proxy:-}}}}"
if [ -z "$proxy" ]; then
  if [ -n "${NEMOCLAW_INFERENCE_BASE_URL:-}" ]; then
    node - <<'NODE'
const baseUrl = process.env.NEMOCLAW_INFERENCE_BASE_URL.replace(/\/+$/, "");

fetch(`${baseUrl}/models`)
  .then((response) => {
    if (!response.ok) {
      throw new Error(`${baseUrl}/models returned HTTP ${response.status}`);
    }
  })
  .catch((error) => {
    console.error(`Node inference route check failed: ${error.message}`);
    process.exit(1);
  });
NODE

    restart_gateway
    echo "OpenClaw direct local inference route prepared."
    exit 0
  fi

  echo "OpenClaw proxy environment was not found inside the sandbox." >&2
  exit 1
fi

proxy="${proxy#http://}"
proxy="${proxy#https://}"
proxy="${proxy%%/*}"

openssl s_client \
  -proxy "$proxy" \
  -connect inference.local:443 \
  -servername inference.local \
  -showcerts \
  </dev/null 2>/tmp/nemoclaw-inference-sclient.err |
  awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/ { print }' > "$CERT_FILE"

if [ ! -s "$CERT_FILE" ]; then
  echo "Failed to extract the inference.local certificate chain." >&2
  sed -n '1,20p' /tmp/nemoclaw-inference-sclient.err >&2 || true
  exit 1
fi

export NODE_USE_ENV_PROXY=1
export NODE_EXTRA_CA_CERTS="$CERT_FILE"
export NODE_NO_WARNINGS=1

node - <<'NODE'
fetch("https://inference.local/v1/models")
  .then((response) => {
    if (!response.ok) {
      throw new Error(`inference.local returned HTTP ${response.status}`);
    }
  })
  .catch((error) => {
    console.error(`Node inference route check failed: ${error.message}`);
    process.exit(1);
  });
NODE

restart_gateway
echo "OpenClaw Node inference route prepared with sandbox CA trust."
