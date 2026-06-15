#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-/Users/sushrutpatwardhan/1Projects/expense_tracker}"
BACKEND_DIR="$ROOT/backend"
BACKEND_PYTHON="${BACKEND_PYTHON:-$BACKEND_DIR/.venv/bin/python}"
HF_AI_HOST="${HF_AI_HOST:-127.0.0.1}"
HF_AI_PORT="${HF_AI_PORT:-8001}"
HF_RECEIPT_MODEL="${HF_RECEIPT_MODEL:-google/gemma-4-E4B-it}"

if [[ ! -x "$BACKEND_PYTHON" ]]; then
  echo "Backend Python was not found at $BACKEND_PYTHON."
  echo "Create it with: cd backend && python3 -m venv .venv && . .venv/bin/activate && pip install -r requirements-ai.txt"
  exit 1
fi

cd "$BACKEND_DIR"
exec "$BACKEND_PYTHON" -m uvicorn app.hf_receipt_server:app \
  --host "$HF_AI_HOST" \
  --port "$HF_AI_PORT"
