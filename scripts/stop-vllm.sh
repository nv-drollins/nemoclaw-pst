#!/usr/bin/env bash
set -euo pipefail

CONTAINER="${PST_VLLM_CONTAINER:-nemoclaw-pst-vllm}"

if docker ps -a --format '{{.Names}}' | grep -Fxq "$CONTAINER"; then
  echo "Stopping vLLM container $CONTAINER"
  docker rm -f "$CONTAINER" >/dev/null
else
  echo "vLLM container $CONTAINER is not present"
fi
