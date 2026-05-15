#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SANDBOX="${NEMOCLAW_SANDBOX_NAME:-pst-agent}"
MODEL="${NEMOCLAW_MODEL:-nemotron-3-nano:30b}"
PROVIDER="${NEMOCLAW_PROVIDER:-vllm}"
INSTALL_REF="${NEMOCLAW_INSTALL_REF:-latest}"
OLLAMA_WRAPPER_DIR="$(mktemp -d)"

drop_path_entry() {
  local remove="$1"
  local entry new_path=""

  IFS=: read -r -a entries <<<"$PATH"
  for entry in "${entries[@]}"; do
    if [ "$entry" = "$remove" ]; then
      continue
    fi

    if [ -z "$new_path" ]; then
      new_path="$entry"
    else
      new_path="$new_path:$entry"
    fi
  done

  printf '%s\n' "$new_path"
}

if [ -n "${VIRTUAL_ENV:-}" ]; then
  echo "Ignoring active Python virtualenv during NemoClaw install: $VIRTUAL_ENV"
  PATH="$(drop_path_entry "$VIRTUAL_ENV/bin")"
  export PATH
  unset VIRTUAL_ENV
fi
unset PIP_REQUIRE_VIRTUALENV PYTHONHOME PYTHONPATH

REAL_OLLAMA_BIN="${NEMOCLAW_OLLAMA_BIN:-}"
if [ -z "$REAL_OLLAMA_BIN" ]; then
  REAL_OLLAMA_BIN="$(command -v ollama 2>/dev/null || true)"
fi
REAL_PIP3_BIN="${NEMOCLAW_PIP3_BIN:-}"
if [ -z "$REAL_PIP3_BIN" ]; then
  REAL_PIP3_BIN="$(command -v pip3 2>/dev/null || true)"
fi

cleanup() {
  rm -rf "$OLLAMA_WRAPPER_DIR"
}
trap cleanup EXIT

export NEMOCLAW_PROVIDER=ollama
export NEMOCLAW_MODEL="$MODEL"
export NEMOCLAW_SANDBOX_NAME="$SANDBOX"
export NEMOCLAW_POLICY_TIER="${NEMOCLAW_POLICY_TIER:-balanced}"
export NEMOCLAW_ACCEPT_THIRD_PARTY_SOFTWARE=1
export NEMOCLAW_NON_INTERACTIVE=1
export NEMOCLAW_LOCAL_INFERENCE_TIMEOUT="${NEMOCLAW_LOCAL_INFERENCE_TIMEOUT:-300}"
export NEMOCLAW_SANDBOX_READY_TIMEOUT="${NEMOCLAW_SANDBOX_READY_TIMEOUT:-600}"
if [ -n "$REAL_OLLAMA_BIN" ]; then
  export NEMOCLAW_OLLAMA_BIN="$REAL_OLLAMA_BIN"
fi
if [ -n "$REAL_PIP3_BIN" ]; then
  export NEMOCLAW_PIP3_BIN="$REAL_PIP3_BIN"
fi

ensure_nvidia_cdi_specs() {
  if ! command -v nvidia-ctk >/dev/null 2>&1; then
    return 0
  fi

  if nvidia-ctk cdi list 2>/dev/null | grep -q 'nvidia.com/gpu=all'; then
    return 0
  fi

  echo "Generating NVIDIA CDI specs for OpenShell GPU passthrough"
  sudo mkdir -p /etc/cdi
  sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml

  if ! nvidia-ctk cdi list 2>/dev/null | grep -q 'nvidia.com/gpu=all'; then
    echo "NVIDIA CDI specs were not generated correctly; run 'nvidia-ctk cdi list' for details." >&2
    exit 1
  fi
}

if [ "$PROVIDER" = "vllm" ]; then
  bash "$SCRIPT_DIR/ensure-sudo.sh"
  ensure_nvidia_cdi_specs
  "$SCRIPT_DIR/start-vllm.sh"

  export NEMOCLAW_EXPERIMENTAL=1
  export NEMOCLAW_PROVIDER=vllm
  export NEMOCLAW_MODEL="${PST_VLLM_SERVED_MODEL_NAME:-model}"
  export NEMOCLAW_SANDBOX_NAME="$SANDBOX"
  export NEMOCLAW_POLICY_TIER="${NEMOCLAW_POLICY_TIER:-balanced}"
  export NEMOCLAW_ACCEPT_THIRD_PARTY_SOFTWARE=1
  export NEMOCLAW_NON_INTERACTIVE=1
  export NEMOCLAW_PREFERRED_API="${NEMOCLAW_PREFERRED_API:-chat-completions}"
  export NEMOCLAW_LOCAL_INFERENCE_TIMEOUT="${NEMOCLAW_LOCAL_INFERENCE_TIMEOUT:-600}"
  export NEMOCLAW_SANDBOX_READY_TIMEOUT="${NEMOCLAW_SANDBOX_READY_TIMEOUT:-600}"

  echo "Onboarding sandbox '$SANDBOX' with local vLLM model '${NEMOCLAW_MODEL}'"
  echo "NemoClaw installer ref: ${INSTALL_REF}"
  curl -fsSL https://www.nvidia.com/nemoclaw.sh -o /tmp/nemoclaw.sh
  bash /tmp/nemoclaw.sh --non-interactive --yes-i-accept-third-party-software --fresh
  exit 0
fi

if [ "$PROVIDER" != "ollama" ]; then
  echo "Unsupported NEMOCLAW_PROVIDER='$PROVIDER'. Use 'vllm' or 'ollama'." >&2
  exit 2
fi

cat >"$OLLAMA_WRAPPER_DIR/ollama" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

find_real_ollama() {
  local self candidate resolved
  self="$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")"

  if [ -n "${NEMOCLAW_OLLAMA_BIN:-}" ] && [ -x "$NEMOCLAW_OLLAMA_BIN" ]; then
    resolved="$(readlink -f "$NEMOCLAW_OLLAMA_BIN" 2>/dev/null || printf '%s' "$NEMOCLAW_OLLAMA_BIN")"
    if [ "$resolved" != "$self" ]; then
      printf '%s\n' "$NEMOCLAW_OLLAMA_BIN"
      return 0
    fi
  fi

  for candidate in /usr/local/bin/ollama /usr/bin/ollama /bin/ollama; do
    if [ -x "$candidate" ]; then
      resolved="$(readlink -f "$candidate" 2>/dev/null || printf '%s' "$candidate")"
      if [ "$resolved" != "$self" ]; then
        printf '%s\n' "$candidate"
        return 0
      fi
    fi
  done

  while IFS= read -r candidate; do
    [ -n "$candidate" ] || continue
    resolved="$(readlink -f "$candidate" 2>/dev/null || printf '%s' "$candidate")"
    if [ "$resolved" != "$self" ] && [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done < <(type -P -a ollama 2>/dev/null | awk '!seen[$0]++')
}

desired_model="${NEMOCLAW_MODEL:-}"
if [ "$#" -ge 2 ] && [ "$1" = "pull" ] && [ -n "$desired_model" ]; then
  requested_model="$2"
  case "$requested_model" in
    nemotron-3-nano:30b|nemotron-3-super:120b)
      if [ "$requested_model" != "$desired_model" ]; then
        echo "Redirecting NemoClaw installer model pull from $requested_model to $desired_model" >&2
        shift 2
        set -- pull "$desired_model" "$@"
      fi
      ;;
  esac
fi

real_ollama="$(find_real_ollama || true)"
if [ -z "$real_ollama" ]; then
  echo "real ollama binary not found yet" >&2
  exit 127
fi

exec "$real_ollama" "$@"
EOF
chmod +x "$OLLAMA_WRAPPER_DIR/ollama"
if [ -n "$REAL_PIP3_BIN" ]; then
  cat >"$OLLAMA_WRAPPER_DIR/pip3" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

should_skip_model_router_install() {
  local arg saw_user=0 saw_router=0

  [ "${NEMOCLAW_PROVIDER:-}" != "routed" ] || return 1
  [ "${1:-}" = "install" ] || return 1

  for arg in "$@"; do
    [ "$arg" = "--user" ] && saw_user=1
    case "$arg" in
      *llm-router*|*\[prefill,proxy\]*) saw_router=1 ;;
    esac
  done

  [ "$saw_user" -eq 1 ] && [ "$saw_router" -eq 1 ]
}

if should_skip_model_router_install "$@"; then
  echo "Skipping optional NemoClaw model router install for provider '${NEMOCLAW_PROVIDER:-ollama}'" >&2
  exit 0
fi

if [ -z "${NEMOCLAW_PIP3_BIN:-}" ] || [ ! -x "$NEMOCLAW_PIP3_BIN" ]; then
  echo "real pip3 binary not found" >&2
  exit 127
fi

exec "$NEMOCLAW_PIP3_BIN" "$@"
EOF
  chmod +x "$OLLAMA_WRAPPER_DIR/pip3"
fi
export PATH="$OLLAMA_WRAPPER_DIR:$PATH"

bash "$SCRIPT_DIR/ensure-sudo.sh"
ensure_nvidia_cdi_specs

echo "Onboarding sandbox '$SANDBOX' with Ollama model '$MODEL'"
echo "NemoClaw installer ref: ${INSTALL_REF}"
curl -fsSL https://www.nvidia.com/nemoclaw.sh -o /tmp/nemoclaw.sh
bash /tmp/nemoclaw.sh --non-interactive --yes-i-accept-third-party-software --fresh
