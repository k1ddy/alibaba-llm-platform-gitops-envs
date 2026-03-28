#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OVERLAY_DIR="$ROOT_DIR/applications/ai-runtime/overlays/dev"
KUSTOMIZATION_FILE="$OVERLAY_DIR/kustomization.yaml"
SECRET_EXAMPLE="$OVERLAY_DIR/.env.runtime.secrets.example"
SECRET_FILE="$OVERLAY_DIR/.env.runtime.secrets"

if [ "${1:-}" = "" ]; then
  echo "usage: $(basename "$0") <main|sha-xxxxxxxx>" >&2
  exit 1
fi

TARGET_TAG="$1"

if ! [[ "$TARGET_TAG" =~ ^main$|^sha-[0-9a-f]{7,40}$ ]]; then
  echo "unsupported tag format: $TARGET_TAG" >&2
  echo "expected: main or sha-<7..40 lowercase hex chars>" >&2
  exit 1
fi

CURRENT_TAG="$(awk '/newTag:/ {print $2; exit}' "$KUSTOMIZATION_FILE")"

if [ -z "$CURRENT_TAG" ]; then
  echo "failed to read current newTag from $KUSTOMIZATION_FILE" >&2
  exit 1
fi

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

sed -i -E "s#(newTag: ).*#\\1$TARGET_TAG#" "$KUSTOMIZATION_FILE"

if ! kubectl kustomize "$OVERLAY_DIR" >/dev/null; then
  sed -i -E "s#(newTag: ).*#\\1$CURRENT_TAG#" "$KUSTOMIZATION_FILE"
  echo "kustomize render failed after tag update, reverted to $CURRENT_TAG" >&2
  exit 1
fi

echo "updated ai-runtime dev tag: $CURRENT_TAG -> $TARGET_TAG"
