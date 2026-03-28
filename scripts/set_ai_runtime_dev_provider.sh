#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OVERLAY_DIR="$ROOT_DIR/applications/ai-runtime/overlays/dev"
PATCH_FILE="$OVERLAY_DIR/llm-config-patch.yaml"
SECRET_EXAMPLE="$OVERLAY_DIR/.env.runtime.secrets.example"
SECRET_FILE="$OVERLAY_DIR/.env.runtime.secrets"

if [ "${1:-}" = "" ]; then
  echo "usage: $(basename "$0") <stub|dashscope_openai_compatible> [model] [base_url]" >&2
  exit 1
fi

TARGET_PROVIDER="$1"
TARGET_MODEL="${2:-qwen-plus}"

case "$TARGET_PROVIDER" in
  stub|dashscope_openai_compatible) ;;
  *)
    echo "unsupported provider: $TARGET_PROVIDER" >&2
    exit 1
    ;;
esac

CURRENT_PROVIDER="$(awk -F': ' '/AI_RUNTIME_LLM_PROVIDER:/ {print $2; exit}' "$PATCH_FILE")"
CURRENT_MODEL="$(awk -F': ' '/AI_RUNTIME_LLM_MODEL:/ {print $2; exit}' "$PATCH_FILE")"
CURRENT_BASE_URL="$(awk -F': ' '/AI_RUNTIME_LLM_BASE_URL:/ {print $2; exit}' "$PATCH_FILE")"
TARGET_BASE_URL="${3:-$CURRENT_BASE_URL}"

TEMP_SECRET_CREATED="false"

cleanup() {
  if [ "$TEMP_SECRET_CREATED" = "true" ]; then
    rm -f "$SECRET_FILE"
  fi
}

trap cleanup EXIT

if [ ! -f "$SECRET_FILE" ]; then
  cp "$SECRET_EXAMPLE" "$SECRET_FILE"
  TEMP_SECRET_CREATED="true"
fi

sed -i -E "s#(AI_RUNTIME_LLM_PROVIDER: ).*#\\1$TARGET_PROVIDER#" "$PATCH_FILE"
sed -i -E "s#(AI_RUNTIME_LLM_MODEL: ).*#\\1$TARGET_MODEL#" "$PATCH_FILE"
sed -i -E "s#(AI_RUNTIME_LLM_BASE_URL: ).*#\\1$TARGET_BASE_URL#" "$PATCH_FILE"

if ! kubectl kustomize "$OVERLAY_DIR" >/dev/null; then
  sed -i -E "s#(AI_RUNTIME_LLM_PROVIDER: ).*#\\1$CURRENT_PROVIDER#" "$PATCH_FILE"
  sed -i -E "s#(AI_RUNTIME_LLM_MODEL: ).*#\\1$CURRENT_MODEL#" "$PATCH_FILE"
  sed -i -E "s#(AI_RUNTIME_LLM_BASE_URL: ).*#\\1$CURRENT_BASE_URL#" "$PATCH_FILE"
  echo "kustomize render failed after provider update, reverted" >&2
  exit 1
fi

echo "updated ai-runtime dev provider: $CURRENT_PROVIDER -> $TARGET_PROVIDER"
echo "updated ai-runtime dev model: $CURRENT_MODEL -> $TARGET_MODEL"
echo "updated ai-runtime dev base_url: $CURRENT_BASE_URL -> $TARGET_BASE_URL"
