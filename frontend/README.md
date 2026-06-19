# Expense Tracker

Flutter client for the local-first family expense tracker. It talks to the
FastAPI backend for authentication, expenses, groups, recurring money, uploads,
and monthly planning.

## Local Development

From `frontend/`:

```bash
flutter pub get
flutter run
flutter analyze
flutter test
```

The repository-level dev script runs the web frontend on `127.0.0.1:7357` and
the backend on `127.0.0.1:8080`:

```bash
../scripts/start_expense_dev_tmux.sh --no-attach
```

If a local port is already occupied, override the ports and matching frontend
API target:

```bash
BACKEND_PORT=8081 FRONTEND_PORT=7358 ../scripts/start_expense_dev_tmux.sh --no-attach
```

When MongoDB is managed separately, set `MONGO_URI` to that reachable server.
If your `.env` only has a deployment-style `MONGODB_URI`, opt in with
`USE_MONGODB_URI_FOR_DEV=1`. Local dev uses `expense_tracker_local` even if
`.env` has a deployment `MONGO_DB`; override with `DEV_MONGO_DB` for a different
local database, or set `MONGO_URI`/`USE_MONGODB_URI_FOR_DEV=1` to pair with
`MONGO_DB`. Use `SKIP_MONGO_BOOTSTRAP=1` only when that MongoDB server is
already running and you want to prevent the script from trying to start the
local Docker Mongo container.

## Production Web / PWA Build

The Flutter web app can be installed from Safari on iPhone with Add to Home
Screen, but the static web bundle does not include the backend. Before sharing
the PWA, expose the FastAPI backend over HTTPS and build the frontend with that
public API URL:

```bash
API_BASE_URL=https://api.example.com ../scripts/build_expense_web_release.sh
```

The output is written to `frontend/build/web/`.

Useful variants:

```bash
# GitHub Pages project site, for example https://user.github.io/expense_tracker/
BASE_HREF=/expense_tracker/ API_BASE_URL=https://api.example.com ../scripts/build_expense_web_release.sh

# Intentional local release smoke test
ALLOW_LOCAL_API=1 API_BASE_URL=http://127.0.0.1:8080 ../scripts/build_expense_web_release.sh
```

Deployment notes:

- Netlify Drop: build locally, then drag `frontend/build/web/` into Netlify.
- GitHub Pages: publish the contents of `frontend/build/web/`; set `BASE_HREF`
  to the repository path when hosting under `/<repo>/`.
- The web bundle includes `_redirects` for Netlify SPA refreshes and `.nojekyll`
  for GitHub Pages.
- Keep `API_BASE_URL` on HTTPS for installable PWA behavior and browser security.
