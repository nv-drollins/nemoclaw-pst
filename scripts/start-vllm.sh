#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=resolve-demo-root.sh
. "$SCRIPT_DIR/resolve-demo-root.sh"
ROOT="$(resolve_demo_root "$SCRIPT_DIR")"

CONTAINER="${PST_VLLM_CONTAINER:-nemoclaw-pst-vllm}"
IMAGE="${PST_VLLM_IMAGE:-vllm/vllm-openai:v0.20.0}"
MODEL_ID="${PST_VLLM_MODEL_ID:-nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B-FP8}"
SERVED_MODEL_NAME="${PST_VLLM_SERVED_MODEL_NAME:-model}"
PORT="${PST_VLLM_PORT:-8000}"
MAX_MODEL_LEN="${PST_VLLM_MAX_MODEL_LEN:-65536}"
MAX_NUM_SEQS="${PST_VLLM_MAX_NUM_SEQS:-4}"
GPU_MEMORY_UTILIZATION="${PST_VLLM_GPU_MEMORY_UTILIZATION:-0.85}"
READY_TIMEOUT="${PST_VLLM_READY_TIMEOUT:-1800}"
HF_CACHE="${HF_HOME:-$HOME/.cache/huggingface}"
VLLM_CACHE="$ROOT/.cache/vllm"
PARSER_DIR="$VLLM_CACHE/parsers"
PARSER_FILE="$PARSER_DIR/nano_v3_reasoning_parser.py"
PARSER_URL="${PST_VLLM_REASONING_PARSER_URL:-https://huggingface.co/${MODEL_ID}/resolve/main/nano_v3_reasoning_parser.py}"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Required command not found: $1" >&2
    exit 1
  }
}

endpoint_ready() {
  curl -fsS "http://127.0.0.1:${PORT}/v1/models" >/dev/null 2>&1
}

wait_for_ready() {
  local waited=0
  while [ "$waited" -lt "$READY_TIMEOUT" ]; do
    if endpoint_ready; then
      echo "vLLM is ready at http://127.0.0.1:${PORT}/v1"
      return 0
    fi
    sleep 5
    waited=$((waited + 5))
    if [ $((waited % 60)) -eq 0 ]; then
      echo "Still waiting for vLLM (${waited}s elapsed)..."
    fi
  done

  echo "vLLM did not become ready within ${READY_TIMEOUT}s." >&2
  docker logs --tail 120 "$CONTAINER" >&2 || true
  exit 1
}

download_parser() {
  mkdir -p "$PARSER_DIR"
  if [ -s "$PARSER_FILE" ]; then
    return 0
  fi

  echo "Downloading Nemotron Nano v3 reasoning parser"
  if [ -n "${HF_TOKEN:-}" ]; then
    curl -fsSL -H "Authorization: Bearer ${HF_TOKEN}" "$PARSER_URL" -o "$PARSER_FILE"
  else
    curl -fsSL "$PARSER_URL" -o "$PARSER_FILE"
  fi
}

need_cmd curl
need_cmd docker

mkdir -p "$HF_CACHE" "$VLLM_CACHE"
download_parser

if endpoint_ready; then
  echo "Reusing existing vLLM endpoint at http://127.0.0.1:${PORT}/v1"
  exit 0
fi

if docker ps --format '{{.Names}}' | grep -Fxq "$CONTAINER"; then
  echo "Container $CONTAINER is running; waiting for readiness"
  wait_for_ready
  exit 0
fi

if docker ps -a --format '{{.Names}}' | grep -Fxq "$CONTAINER"; then
  echo "Removing stopped vLLM container $CONTAINER"
  docker rm -f "$CONTAINER" >/dev/null
fi

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "Pulling vLLM image: $IMAGE"
  docker pull "$IMAGE"
fi

env_args=(
  -e VLLM_USE_FLASHINFER_MOE_FP8=1
  -e VLLM_ALLOW_LONG_MAX_MODEL_LEN=1
)

if [ -n "${HF_TOKEN:-}" ]; then
  env_args+=(-e "HF_TOKEN=${HF_TOKEN}" -e "HUGGING_FACE_HUB_TOKEN=${HF_TOKEN}")
elif [ -n "${HUGGING_FACE_HUB_TOKEN:-}" ]; then
  env_args+=(-e "HUGGING_FACE_HUB_TOKEN=${HUGGING_FACE_HUB_TOKEN}")
fi

echo "Starting vLLM for ${MODEL_ID}"
echo "First start may take a while while Hugging Face model files download."
docker run -d \
  --name "$CONTAINER" \
  --restart unless-stopped \
  --gpus all \
  --ipc=host \
  --network host \
  "${env_args[@]}" \
  -v "${HF_CACHE}:/root/.cache/huggingface" \
  -v "${VLLM_CACHE}:/root/.cache/vllm" \
  -v "${PARSER_FILE}:/opt/nemoclaw-pst/nano_v3_reasoning_parser.py:ro" \
  "$IMAGE" \
  "$MODEL_ID" \
    --served-model-name "$SERVED_MODEL_NAME" \
    --host 0.0.0.0 \
    --port "$PORT" \
    --max-num-seqs "$MAX_NUM_SEQS" \
    --tensor-parallel-size 1 \
    --max-model-len "$MAX_MODEL_LEN" \
    --gpu-memory-utilization "$GPU_MEMORY_UTILIZATION" \
    --trust-remote-code \
    --enable-auto-tool-choice \
    --tool-call-parser qwen3_coder \
    --reasoning-parser-plugin /opt/nemoclaw-pst/nano_v3_reasoning_parser.py \
    --reasoning-parser nano_v3 \
    --kv-cache-dtype fp8 \
  >/dev/null

wait_for_ready
