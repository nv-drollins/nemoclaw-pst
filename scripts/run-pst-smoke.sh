#!/usr/bin/env bash
set -euo pipefail

PORT="${PST_SERVER_PORT:-9003}"
SANDBOX="${NEMOCLAW_SANDBOX_NAME:-}"
HOST_ONLY=0

usage() {
  cat <<EOF
Usage: $0 [--sandbox NAME] [--host-only]

Runs PST demo smoke checks.

Options:
  --sandbox NAME  Also verify that the OpenClaw sandbox can reach the PST service.
  --host-only     Only run host-side PST service checks.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --sandbox)
      SANDBOX="${2:?missing sandbox name}"
      shift
      ;;
    --host-only) HOST_ONLY=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

echo "Host PST health:"
curl -fsS "http://127.0.0.1:$PORT/health"
echo

echo "Folder counts:"
curl -fsS "http://127.0.0.1:$PORT/folders"
echo

echo "Subject search for 'attachment':"
curl -fsS "http://127.0.0.1:$PORT/emails/search_subject?keyword=attachment&max_results=2"
echo

if [ "$HOST_ONLY" -eq 0 ] && [ -n "$SANDBOX" ]; then
  echo
  echo "Sandbox PST route:"

  if ! command -v docker >/dev/null 2>&1; then
    echo "Skipping sandbox route check: docker command not found." >&2
    exit 0
  fi

  if ! docker inspect openshell-cluster-nemoclaw >/dev/null 2>&1; then
    sandbox_container="$(
      docker ps \
        --filter "label=openshell.ai/sandbox-name=$SANDBOX" \
        --filter "label=openshell.ai/managed-by=openshell" \
        --format '{{.Names}}' |
        head -n 1
    )"

    if [ -z "$sandbox_container" ]; then
      echo "Skipping sandbox route check: OpenShell sandbox container not found." >&2
      exit 0
    fi

    docker exec "$sandbox_container" runuser -u sandbox -- \
      curl -fsS --max-time 15 "http://host.docker.internal:$PORT/folders"
    echo
    exit 0
  fi

  docker exec openshell-cluster-nemoclaw kubectl exec -n openshell "$SANDBOX" -c agent -- \
    curl -fsS --max-time 15 "http://host.openshell.internal:$PORT/folders"
  echo
fi
