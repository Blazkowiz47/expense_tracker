# Repository Guidelines

## Project Structure & Module Organization
This repository is split into two apps:
- `frontend/`: Flutter client for iOS, Android, and Web. Main app code lives in `frontend/lib/`; tests live in `frontend/test/`; platform folders include `android/`, `ios/`, and `web/`.
- `backend/`: Go API service. Entrypoint is `backend/cmd/server/main.go`; internal packages live in `backend/internal/` (`auth`, `config`, `expense`, `httpapi`, `middleware`, `server`).
- `plan.md`: execution plan and milestones for the project.

## Build, Test, and Development Commands
Run commands from each module directory.

Backend (`backend/`):
- `go run ./cmd/server` - start local API server (default port `8080`).
- `go test ./...` - run all unit tests.
- `go test -v ./internal/...` - verbose test output for internal packages.
- `gofmt -w $(rg --files -g '*.go')` - format all Go files.

Frontend (`frontend/`):
- `flutter pub get` - install Dart/Flutter dependencies.
- `flutter run` - run app on connected device/simulator.
- `flutter test` - run unit/widget tests.
- `flutter analyze` - static analysis.

## Coding Style & Naming Conventions
- Go: use `gofmt` formatting (tabs), lowercase package names, and `CamelCase` exported symbols.
- Dart/Flutter: 2-space indentation, `dart format .`, `lowerCamelCase` members, `UpperCamelCase` classes.
- Keep HTTP error responses consistent with the JSON error envelope in `backend/internal/httpapi/response.go`.

## Testing Guidelines
- Backend tests use Go's `testing` package. Place tests as `*_test.go` next to source files.
- Prefer table-driven tests for service and handler edge cases.
- Frontend tests live under `frontend/test/` and should cover blocs, repositories, and key widgets.
- Run module-local test suites before opening a PR.

## Commit & Pull Request Guidelines
- Git history currently shows a single initial commit (`first commit`), so no strong convention is established yet.
- Use clear, imperative commit messages going forward, e.g., `backend: add auth middleware tests`.
- PRs should include: scope summary, test evidence (commands + results), config/env changes, and screenshots for UI changes.

## Security & Configuration Tips
- Do not commit secrets (`serviceAccountKey.json`, API keys, tokens).
- Use environment variables for backend runtime configuration (`PORT`, `APP_ENV`, `DEV_AUTH_TOKEN`, `DEV_AUTH_UID`).
- Firebase production setup will be added later; current backend auth verifier is local-development oriented.
