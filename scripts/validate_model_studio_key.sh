#!/usr/bin/env bash
set -euo pipefail

BASE_URL_DEFAULT="https://dashscope.aliyuncs.com/compatible-mode/v1"
MODEL_DEFAULT="qwen-plus"
PROMPT_DEFAULT="Reply with OK."

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

require_cmd curl
require_cmd python3
require_env AI_RUNTIME_LLM_API_KEY

BASE_URL="${AI_RUNTIME_LLM_BASE_URL:-$BASE_URL_DEFAULT}"
MODEL="${AI_RUNTIME_LLM_MODEL:-$MODEL_DEFAULT}"
PROMPT="${AI_RUNTIME_LLM_VALIDATE_PROMPT:-$PROMPT_DEFAULT}"
RESPONSE_FILE="$(mktemp /tmp/model-studio-validate.XXXXXX.json)"
HTTP_STATUS_FILE="$(mktemp /tmp/model-studio-validate-status.XXXXXX.txt)"

cleanup() {
  rm -f "$RESPONSE_FILE" "$HTTP_STATUS_FILE"
}

trap cleanup EXIT

HTTP_STATUS="$(
  curl -sS \
    -o "$RESPONSE_FILE" \
    -w '%{http_code}' \
    -X POST "$BASE_URL/chat/completions" \
    -H "Authorization: Bearer $AI_RUNTIME_LLM_API_KEY" \
    -H 'Content-Type: application/json' \
    -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"$PROMPT\"}],\"max_tokens\":8}"
)"

printf '%s' "$HTTP_STATUS" > "$HTTP_STATUS_FILE"

python3 - "$RESPONSE_FILE" "$HTTP_STATUS_FILE" "$MODEL" "$BASE_URL" <<'PY'
import json
import pathlib
import sys

response_file = pathlib.Path(sys.argv[1])
status_file = pathlib.Path(sys.argv[2])
expected_model = sys.argv[3]
base_url = sys.argv[4]
status = status_file.read_text().strip()
raw = response_file.read_text().strip()

if status != "200":
    raise SystemExit(
        f"Model Studio validation failed: http_status={status}, body={raw}"
    )

payload = json.loads(raw)
choices = payload.get("choices") or []
if not choices:
    raise SystemExit(f"Model Studio validation returned no choices: {raw}")

actual_model = payload.get("model") or expected_model
content = choices[0].get("message", {}).get("content", "")
if not str(content).strip():
    raise SystemExit(f"Model Studio validation returned empty content: {raw}")

print(
    json.dumps(
        {
            "validated": True,
            "base_url": base_url,
            "requested_model": expected_model,
            "response_model": actual_model,
            "reply_preview": str(content).strip()[:120],
        },
        ensure_ascii=True,
    )
)
PY
