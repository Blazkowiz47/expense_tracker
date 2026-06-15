#!/usr/bin/env bash
set -euo pipefail

SESSION="${SESSION:-expense-dev}"
ROOT="/Users/sushrutpatwardhan/1Projects/expense_tracker"
BACKEND_DIR="$ROOT/backend"
FRONTEND_DIR="$ROOT/frontend"

AUTH_MODE_USED="${AUTH_MODE:-local}"
BACKEND_HOST_USED="${BACKEND_HOST:-127.0.0.1}"
BACKEND_PORT_USED="${BACKEND_PORT:-8080}"
FRONTEND_HOST_USED="${FRONTEND_HOST:-127.0.0.1}"
FRONTEND_PORT_USED="${FRONTEND_PORT:-7357}"
API_BASE_URL_USED="${API_BASE_URL:-http://$BACKEND_HOST_USED:$BACKEND_PORT_USED}"
MONGO_HOST_USED="${MONGO_HOST:-127.0.0.1}"
MONGO_PORT_USED="${MONGO_PORT:-27017}"
MONGO_URI_USED="${MONGO_URI:-mongodb://$MONGO_HOST_USED:$MONGO_PORT_USED}"
MONGO_DB_USED="${MONGO_DB:-expense_tracker_local}"
AI_PROVIDER_USED="${AI_PROVIDER:-custom}"
AI_BASE_URL_USED="${AI_BASE_URL:-}"
AI_MODEL_USED="${AI_MODEL:-unsloth/gemma-4-E4B-it-GGUF}"
FIREBASE_PROJECT_ID_USED="${FIREBASE_PROJECT_ID:-}"
BACKEND_PYTHON="${BACKEND_PYTHON:-$BACKEND_DIR/.venv/bin/python}"
MONGO_CONTAINER_NAME_USED="${MONGO_CONTAINER_NAME:-expense-tracker-mongo}"

if [[ ! -x "$BACKEND_PYTHON" ]]; then
  echo "Backend Python was not found at $BACKEND_PYTHON."
  echo "Create it with: cd backend && python3 -m venv .venv && . .venv/bin/activate && pip install -r requirements-dev.txt"
  exit 1
fi

MONGO_BOOTSTRAP_HOST="$MONGO_HOST_USED"
MONGO_BOOTSTRAP_PORT="$MONGO_PORT_USED"
SHOULD_BOOTSTRAP_MONGO=0
if [[ "$MONGO_URI_USED" =~ ^mongodb://(127\.0\.0\.1|localhost)(:([0-9]+))?(/|$) ]]; then
  SHOULD_BOOTSTRAP_MONGO=1
  MONGO_BOOTSTRAP_HOST="${BASH_REMATCH[1]}"
  MONGO_BOOTSTRAP_PORT="${BASH_REMATCH[3]:-$MONGO_PORT_USED}"
fi

if [[ "${SKIP_MONGO_BOOTSTRAP:-0}" != "1" && "$SHOULD_BOOTSTRAP_MONGO" -eq 1 ]] && \
  ! nc -z "$MONGO_BOOTSTRAP_HOST" "$MONGO_BOOTSTRAP_PORT" >/dev/null 2>&1; then
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    DOCKER_BIND_HOST="$MONGO_BOOTSTRAP_HOST"
    if [[ "$DOCKER_BIND_HOST" == "localhost" ]]; then
      DOCKER_BIND_HOST="127.0.0.1"
    fi
    docker start "$MONGO_CONTAINER_NAME_USED" >/dev/null 2>&1 || \
      docker run -d --name "$MONGO_CONTAINER_NAME_USED" \
        -p "$DOCKER_BIND_HOST:$MONGO_BOOTSTRAP_PORT:27017" mongo:7 >/dev/null
    for _ in {1..20}; do
      nc -z "$MONGO_BOOTSTRAP_HOST" "$MONGO_BOOTSTRAP_PORT" >/dev/null 2>&1 && break
      sleep 0.25
    done
  else
    echo "MongoDB is not listening on $MONGO_BOOTSTRAP_HOST:$MONGO_BOOTSTRAP_PORT and Docker is unavailable."
    echo "Start MongoDB locally, or start Docker and rerun this script."
    exit 1
  fi
fi

if [[ "$SHOULD_BOOTSTRAP_MONGO" -eq 1 ]] && \
  ! nc -z "$MONGO_BOOTSTRAP_HOST" "$MONGO_BOOTSTRAP_PORT" >/dev/null 2>&1; then
  echo "MongoDB is not listening on $MONGO_BOOTSTRAP_HOST:$MONGO_BOOTSTRAP_PORT."
  if [[ "${SKIP_MONGO_BOOTSTRAP:-0}" == "1" ]]; then
    echo "Start MongoDB locally, or set MONGO_URI to a reachable managed server."
  else
    echo "Start MongoDB locally, set MONGO_URI to a reachable server, or rerun with SKIP_MONGO_BOOTSTRAP=1 if Mongo is managed separately."
  fi
  exit 1
fi

BACKEND_CMD="cd \"$BACKEND_DIR\" && AUTH_MODE=\"$AUTH_MODE_USED\" MONGO_URI=\"$MONGO_URI_USED\" MONGO_DB=\"$MONGO_DB_USED\" DATA_DIR=\"$BACKEND_DIR/data\" AI_PROVIDER=\"$AI_PROVIDER_USED\" AI_BASE_URL=\"$AI_BASE_URL_USED\" AI_MODEL=\"$AI_MODEL_USED\" FIREBASE_PROJECT_ID=\"$FIREBASE_PROJECT_ID_USED\" \"$BACKEND_PYTHON\" -m uvicorn app.main:app --host \"$BACKEND_HOST_USED\" --port \"$BACKEND_PORT_USED\" --reload"

FRONTEND_CMD="cd \"$FRONTEND_DIR\" && flutter run -d web-server --web-hostname \"$FRONTEND_HOST_USED\" --web-port \"$FRONTEND_PORT_USED\" --dart-define=API_BASE_URL=\"$API_BASE_URL_USED\" --dart-define=AUTH_MODE=\"$AUTH_MODE_USED\""

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
echo "Backend target: http://$BACKEND_HOST_USED:$BACKEND_PORT_USED"
echo "Frontend target: http://$FRONTEND_HOST_USED:$FRONTEND_PORT_USED"

if [[ "$ATTACH" -eq 1 ]]; then
  tmux attach-session -t "$SESSION"
fi
