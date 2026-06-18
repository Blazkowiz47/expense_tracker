#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON="${PYTHON:-$ROOT/backend/.venv/bin/python}"

if [[ -f "$ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/.env"
  set +a
fi

if [[ -z "${TARGET_MONGO_URI:-${REMOTE_MONGO_URI:-${ATLAS_MONGO_URI:-}}}" ]]; then
  cat >&2 <<'EOF'
Set TARGET_MONGO_URI to the Atlas connection string before running.

Example:
  TARGET_MONGO_URI='mongodb+srv://user:password@cluster.mongodb.net/expense_tracker_prod?retryWrites=true&w=majority' \
  scripts/sync_mongo_to_atlas.sh --execute --replace-target
EOF
  exit 2
fi

exec "$PYTHON" "$ROOT/scripts/sync_mongo.py" "$@"
