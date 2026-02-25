#!/usr/bin/env bash
set -euo pipefail

SESSION="${SESSION:-expense-dev}"
ROOT="/Users/sushrutpatwardhan/1Projects/expense_tracker"
BACKEND_DIR="$ROOT/backend"
FRONTEND_DIR="$ROOT/frontend"
FIREBASE_CREDS_DEFAULT="$ROOT/firebase_config/expense-tracker-275c3-firebase-adminsdk-fbsvc-0c1a8a9132.json"

FIREBASE_PROJECT_ID="${FIREBASE_PROJECT_ID:-expense-tracker-275c3}"
FIREBASE_CREDENTIALS_FILE="${FIREBASE_CREDENTIALS_FILE:-$FIREBASE_CREDS_DEFAULT}"

BACKEND_CMD="cd \"$BACKEND_DIR\" && AUTH_MODE=dev DEV_AUTH_TOKEN=dev-token DEV_AUTH_UID=local-user"
if [[ -f "$FIREBASE_CREDENTIALS_FILE" ]]; then
  BACKEND_CMD="$BACKEND_CMD FIREBASE_PROJECT_ID=$FIREBASE_PROJECT_ID FIREBASE_CREDENTIALS_FILE=\"$FIREBASE_CREDENTIALS_FILE\""
fi
BACKEND_CMD="$BACKEND_CMD go run ./cmd/server"

ATTACH=1
if [[ "${1:-}" == "--no-attach" ]]; then
  ATTACH=0
fi

# Clean restart.
tmux kill-session -t "$SESSION" 2>/dev/null || true

# Window 1: backend.
tmux new-session -d -s "$SESSION" -n backend
tmux set-option -t "$SESSION" remain-on-exit on
tmux send-keys -t "$SESSION:1" \
  "$BACKEND_CMD" C-m

# Window 2: frontend.
tmux new-window -t "$SESSION" -n frontend
tmux send-keys -t "$SESSION:2" \
  "cd \"$FRONTEND_DIR\" && flutter run -d web-server --web-hostname 127.0.0.1 --web-port 7357 --dart-define=API_BASE_URL=http://127.0.0.1:8080 --dart-define=DEV_AUTH_TOKEN=dev-token" C-m

tmux list-windows -t "$SESSION"

if [[ "$ATTACH" -eq 1 ]]; then
  tmux attach-session -t "$SESSION"
fi
