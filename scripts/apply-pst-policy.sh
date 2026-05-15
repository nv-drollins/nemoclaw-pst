#!/usr/bin/env bash
set -euo pipefail

SANDBOX="${1:-${NEMOCLAW_SANDBOX_NAME:-pst-agent}}"
PORT="${PST_SERVER_PORT:-9003}"
POLICY_FILE="$(mktemp /tmp/pst-policy-XXXX.yaml)"

export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"

openshell policy get "$SANDBOX" --full | sed '1,/^---$/d' > "$POLICY_FILE"

if grep -q "pst_mail_service:" "$POLICY_FILE"; then
  echo "PST policy already present"
else
  cat >> "$POLICY_FILE" <<YAML
  pst_mail_service:
    name: pst_mail_service
    endpoints:
    - host: 127.0.0.1
      port: $PORT
      protocol: rest
      enforcement: enforce
      rules:
      - allow:
          method: GET
          path: /**
    - host: host.openshell.internal
      port: $PORT
      protocol: rest
      enforcement: enforce
      rules:
      - allow:
          method: GET
          path: /**
      allowed_ips:
      - '10.0.0.0/8'
      - '172.16.0.0/12'
      - '192.168.0.0/16'
    binaries:
    - path: /usr/bin/curl
    - path: /usr/local/bin/node
    - path: /usr/bin/node
YAML
fi

openshell policy set "$SANDBOX" --policy "$POLICY_FILE" --wait
rm -f "$POLICY_FILE"
