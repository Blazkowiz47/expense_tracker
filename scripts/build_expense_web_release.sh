#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRONTEND_DIR="$ROOT_DIR/frontend"

API_BASE_URL="${API_BASE_URL:-}"
AUTH_MODE="${AUTH_MODE:-local}"
BASE_HREF="${BASE_HREF:-}"

if [[ -z "$API_BASE_URL" ]]; then
  echo "API_BASE_URL is required for production web builds." >&2
  echo "Example: API_BASE_URL=https://api.example.com $0" >&2
  exit 1
fi

if [[ "$API_BASE_URL" =~ ^https?://(localhost|127\.0\.0\.1|0\.0\.0\.0)(:|/|$) ]] && [[ "${ALLOW_LOCAL_API:-}" != "1" ]]; then
  echo "Refusing to build a production PWA against a local API URL: $API_BASE_URL" >&2
  echo "Use a reachable HTTPS backend URL, or set ALLOW_LOCAL_API=1 for an intentional local test build." >&2
  exit 1
fi

build_args=(
  build
  web
  --release
  --dart-define=API_BASE_URL="$API_BASE_URL"
  --dart-define=AUTH_MODE="$AUTH_MODE"
)

if [[ -n "$BASE_HREF" ]]; then
  build_args+=(--base-href "$BASE_HREF")
fi

cd "$FRONTEND_DIR"
flutter "${build_args[@]}"
