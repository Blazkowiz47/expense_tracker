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
