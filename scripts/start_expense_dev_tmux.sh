#!/usr/bin/env bash
set -euo pipefail

SESSION="${SESSION:-expense-dev}"
ROOT="/Users/sushrutpatwardhan/1Projects/expense_tracker"
BACKEND_DIR="$ROOT/backend"
FRONTEND_DIR="$ROOT/frontend"

AUTH_MODE_USED="${AUTH_MODE:-local}"
MONGO_URI_USED="${MONGO_URI:-mongodb://127.0.0.1:27017}"
MONGO_DB_USED="${MONGO_DB:-expense_tracker_local}"

if ! nc -z 127.0.0.1 27017 >/dev/null 2>&1; then
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    docker start expense-tracker-mongo >/dev/null 2>&1 || \
      docker run -d --name expense-tracker-mongo -p 127.0.0.1:27017:27017 mongo:7 >/dev/null
  else
    echo "MongoDB is not listening on 127.0.0.1:27017 and Docker is unavailable."
    echo "Start MongoDB locally, or start Docker and rerun this script."
    exit 1
  fi
fi

BACKEND_CMD="cd \"$BACKEND_DIR\" && AUTH_MODE=$AUTH_MODE_USED MONGO_URI=\"$MONGO_URI_USED\" MONGO_DB=\"$MONGO_DB_USED\" DATA_DIR=\"$BACKEND_DIR/data\" uvicorn app.main:app --host 127.0.0.1 --port 8080 --reload"

FRONTEND_CMD="cd \"$FRONTEND_DIR\" && flutter run -d web-server --web-hostname 127.0.0.1 --web-port 7357 --dart-define=API_BASE_URL=http://127.0.0.1:8080 --dart-define=AUTH_MODE=$AUTH_MODE_USED"

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
  "$FRONTEND_CMD" C-m

tmux list-windows -t "$SESSION"

if [[ "$ATTACH" -eq 1 ]]; then
  tmux attach-session -t "$SESSION"
fi
