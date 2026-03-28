#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OVERLAY_DIR="$ROOT_DIR/applications/ai-runtime/overlays/dev"
LLM_PATCH_FILE="$OVERLAY_DIR/llm-config-patch.yaml"
NAMESPACE="ai-runtime-dev"
SERVICE="ai-runtime-dev"
VERIFY_PORT="${AI_RUNTIME_VERIFY_PORT:-18092}"
VERIFY_MESSAGE="${AI_RUNTIME_VERIFY_MESSAGE:-What is this platform for?}"
HEALTH_FILE="$(mktemp /tmp/ai-runtime-dev-verify-health.XXXXXX.json)"
TURN_FILE="$(mktemp /tmp/ai-runtime-dev-verify-turn.XXXXXX.json)"
PORT_FORWARD_LOG="$(mktemp /tmp/ai-runtime-dev-verify-port-forward.XXXXXX.log)"
PF_PID=""

if [ -z "${KUBECONFIG:-}" ] && [ -f "$HOME/.kube/career-prep-ack.yaml" ]; then
  export KUBECONFIG="$HOME/.kube/career-prep-ack.yaml"
fi

cleanup() {
  rm -f "$HEALTH_FILE" "$TURN_FILE" "$PORT_FORWARD_LOG"
  if [ -n "$PF_PID" ] && kill -0 "$PF_PID" >/dev/null 2>&1; then
    kill "$PF_PID" >/dev/null 2>&1 || true
    wait "$PF_PID" 2>/dev/null || true
  fi
}

trap cleanup EXIT

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

for cmd in kubectl curl python3; do
  require_cmd "$cmd"
done

EXPECTED_PROVIDER="${AI_RUNTIME_EXPECT_PROVIDER:-$(awk -F': ' '/AI_RUNTIME_LLM_PROVIDER:/ {print $2; exit}' "$LLM_PATCH_FILE")}"
EXPECTED_MODEL="${AI_RUNTIME_EXPECT_MODEL:-$(awk -F': ' '/AI_RUNTIME_LLM_MODEL:/ {print $2; exit}' "$LLM_PATCH_FILE")}"

kubectl get deployment ai-runtime-dev -n "$NAMESPACE" >/dev/null
kubectl get service "$SERVICE" -n "$NAMESPACE" >/dev/null

kubectl port-forward -n "$NAMESPACE" "service/$SERVICE" "$VERIFY_PORT:80" >"$PORT_FORWARD_LOG" 2>&1 &
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

SESSION_ID="demo-verify-$(date +%s)"
curl -fsS -X POST "http://127.0.0.1:${VERIFY_PORT}/v1/runtime/turn" \
  -H 'content-type: application/json' \
  -d "{\"session_id\":\"${SESSION_ID}\",\"user_message\":\"${VERIFY_MESSAGE}\"}" >"$TURN_FILE"

python3 - "$TURN_FILE" "$EXPECTED_PROVIDER" "$EXPECTED_MODEL" <<'PY'
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

echo "healthz:"
cat "$HEALTH_FILE"
echo
echo
echo "expected_provider:"
echo "$EXPECTED_PROVIDER"
echo
echo "runtime turn:"
cat "$TURN_FILE"
echo
