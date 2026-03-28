#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OVERLAY_DIR="$ROOT_DIR/applications/ai-runtime/overlays/dev"
LLM_PATCH_FILE="$OVERLAY_DIR/llm-config-patch.yaml"
NAMESPACE="ai-runtime-dev"
DEPLOYMENT="ai-runtime-dev"
SERVICE="ai-runtime-dev"
ACR_SECRET_NAME="acr-pull-secret"
ACR_SERVER_DEFAULT="crpi-ir1o22efjphtqr94-vpc.cn-hangzhou.personal.cr.aliyuncs.com"
VERIFY_PORT_DEFAULT="18090"
ROLLOUT_TIMEOUT_DEFAULT="300s"
VERIFY_MESSAGE_DEFAULT="What is this platform for?"

if [ -z "${KUBECONFIG:-}" ] && [ -f "$HOME/.kube/career-prep-ack.yaml" ]; then
  export KUBECONFIG="$HOME/.kube/career-prep-ack.yaml"
fi

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

require_env() {
  if [ -z "${!1:-}" ]; then
    echo "missing required environment variable: $1" >&2
    exit 1
  fi
}

for cmd in kubectl curl mktemp; do
  require_cmd "$cmd"
done

require_env AI_RUNTIME_ACR_USERNAME
require_env AI_RUNTIME_ACR_PASSWORD

ACR_SERVER="${AI_RUNTIME_ACR_SERVER:-$ACR_SERVER_DEFAULT}"
VERIFY_PORT="${AI_RUNTIME_VERIFY_PORT:-$VERIFY_PORT_DEFAULT}"
ROLLOUT_TIMEOUT="${AI_RUNTIME_ROLLOUT_TIMEOUT:-$ROLLOUT_TIMEOUT_DEFAULT}"
VERIFY_MESSAGE="${AI_RUNTIME_VERIFY_MESSAGE:-$VERIFY_MESSAGE_DEFAULT}"
DESIRED_PROVIDER="$(awk -F': ' '/AI_RUNTIME_LLM_PROVIDER:/ {print $2; exit}' "$LLM_PATCH_FILE")"
DESIRED_MODEL="$(awk -F': ' '/AI_RUNTIME_LLM_MODEL:/ {print $2; exit}' "$LLM_PATCH_FILE")"
LLM_API_KEY_VALUE="${AI_RUNTIME_LLM_API_KEY:-}"
PORT_FORWARD_LOG="$(mktemp /tmp/ai-runtime-dev-port-forward.XXXXXX.log)"
RENDER_FILE="$(mktemp /tmp/ai-runtime-dev-render.XXXXXX.yaml)"
HEALTH_FILE="$(mktemp /tmp/ai-runtime-dev-healthz.XXXXXX.json)"
TURN_FILE="$(mktemp /tmp/ai-runtime-dev-turn.XXXXXX.json)"
PF_PID=""

cleanup() {
  rm -f "$OVERLAY_DIR/.env.runtime.secrets" "$PORT_FORWARD_LOG" "$RENDER_FILE" "$HEALTH_FILE" "$TURN_FILE"
  if [ -n "$PF_PID" ] && kill -0 "$PF_PID" >/dev/null 2>&1; then
    kill "$PF_PID" >/dev/null 2>&1 || true
    wait "$PF_PID" 2>/dev/null || true
  fi
}

trap cleanup EXIT

case "$DESIRED_PROVIDER" in
  stub)
    if [ -z "$LLM_API_KEY_VALUE" ]; then
      LLM_API_KEY_VALUE="dummy-not-used"
    fi
    ;;
  dashscope_openai_compatible)
    if [ -z "$LLM_API_KEY_VALUE" ] || [ "$LLM_API_KEY_VALUE" = "dummy-not-used" ]; then
      echo "AI_RUNTIME_LLM_API_KEY is required when dev provider is dashscope_openai_compatible" >&2
      exit 1
    fi
    ;;
  *)
    echo "unsupported provider in $LLM_PATCH_FILE: $DESIRED_PROVIDER" >&2
    exit 1
    ;;
esac

printf 'AI_RUNTIME_LLM_API_KEY=%s\n' "$LLM_API_KEY_VALUE" > "$OVERLAY_DIR/.env.runtime.secrets"

kubectl version --client >/dev/null
kubectl auth can-i create deployment -n "$NAMESPACE" >/dev/null

kubectl apply -f "$OVERLAY_DIR/namespace.yaml"

kubectl -n "$NAMESPACE" create secret docker-registry "$ACR_SECRET_NAME" \
  --docker-server="$ACR_SERVER" \
  --docker-username="$AI_RUNTIME_ACR_USERNAME" \
  --docker-password="$AI_RUNTIME_ACR_PASSWORD" \
  --dry-run=client \
  -o yaml | kubectl apply -f -

kubectl kustomize "$OVERLAY_DIR" > "$RENDER_FILE"
kubectl apply --dry-run=server -f "$RENDER_FILE"
kubectl apply -f "$RENDER_FILE"
kubectl rollout status "deployment/$DEPLOYMENT" -n "$NAMESPACE" --timeout="$ROLLOUT_TIMEOUT"

kubectl get deploy,svc,pod -n "$NAMESPACE" -o wide

kubectl port-forward -n "$NAMESPACE" "svc/$SERVICE" "$VERIFY_PORT:80" >"$PORT_FORWARD_LOG" 2>&1 &
PF_PID="$!"

for _ in $(seq 1 20); do
  if curl -fsS "http://127.0.0.1:${VERIFY_PORT}/healthz" >"$HEALTH_FILE" 2>/dev/null; then
    break
  fi
  sleep 1
done

if ! curl -fsS "http://127.0.0.1:${VERIFY_PORT}/healthz" >"$HEALTH_FILE"; then
  cat "$PORT_FORWARD_LOG" >&2
  echo "live health check failed" >&2
  exit 1
fi

SESSION_ID="demo-live-$(date +%s)"
curl -fsS -X POST "http://127.0.0.1:${VERIFY_PORT}/v1/runtime/turn" \
  -H 'content-type: application/json' \
  -d "{\"session_id\":\"${SESSION_ID}\",\"user_message\":\"${VERIFY_MESSAGE}\"}" >"$TURN_FILE"

python3 - "$TURN_FILE" "$DESIRED_PROVIDER" "$DESIRED_MODEL" <<'PY'
import json
import pathlib
import sys

turn_file = pathlib.Path(sys.argv[1])
expected_provider = sys.argv[2]
expected_model = sys.argv[3]
payload = json.loads(turn_file.read_text())
actual_provider = payload.get("model_provider")
actual_model = payload.get("model_name")

if actual_provider != expected_provider:
    raise SystemExit(
        f"unexpected model_provider: expected {expected_provider}, got {actual_provider}"
    )

if expected_provider != "stub" and actual_model != expected_model:
    raise SystemExit(
        f"unexpected model_name: expected {expected_model}, got {actual_model}"
    )
PY

echo
echo "healthz:"
cat "$HEALTH_FILE"
echo
echo
echo "provider:"
echo "$DESIRED_PROVIDER"
echo
echo
echo "runtime turn:"
cat "$TURN_FILE"
echo
