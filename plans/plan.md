# Expense Tracker - Execution Plan

## Objective

Build a local-first expense tracker for iOS, Android, and Web using
`frontend/` (Flutter) and `backend/` (Python + FastAPI + MongoDB). The backend
owns authentication, expense/group data, uploads, and AI processing.

## Architecture

1. Flutter registers or signs in through the FastAPI backend.
2. The backend returns an opaque bearer session token.
3. Flutter sends `Authorization: Bearer <session token>` on protected API calls.
4. FastAPI reads/writes MongoDB documents scoped by the authenticated `uid`.
5. Uploaded bills are stored locally and processed by backend-only AI jobs.

## Core Components

- Client: Flutter + BLoC + REST repositories.
- API: FastAPI routes in `backend/app/main.py`.
- Auth: local email/password with Argon2 password hashes and opaque sessions.
- Data store: local MongoDB.
- Upload store: local filesystem under `backend/data/uploads`.
- AI: backend-only provider seam targeting a local Gemma-compatible service.

## API Contract

| Method | Endpoint | Auth | Notes |
| :--- | :--- | :--- | :--- |
| `GET` | `/health` | No | Liveness check |
| `POST` | `/api/v1/auth/register` | No | Create local account |
| `POST` | `/api/v1/auth/login` | No | Create session |
| `POST` | `/api/v1/auth/logout` | Yes | Delete current session |
| `GET` | `/api/v1/auth/me` | Yes | Current user |
| `GET/PUT` | `/api/v1/profile` | Yes | Profile read/update |
| `POST` | `/api/v1/profile/photo` | Yes | Local profile photo upload |
| `GET/POST` | `/api/v1/expenses` | Yes | List/create expenses |
| `PUT/DELETE` | `/api/v1/expenses/:id` | Yes | Update/delete owned expense |
| `GET` | `/api/v1/analytics` | Yes | Monthly/category aggregates |
| `GET` | `/api/v1/dashboard/snapshot` | Yes | Home/account summary |
| `GET/POST` | `/api/v1/groups` | Yes | List/create groups |
| `POST` | `/api/v1/bills` | Yes | Upload bill and create AI job |
| `GET` | `/api/v1/bills/:id` | Yes | Poll AI extraction |
| `POST` | `/api/v1/bills/:id/create-expense` | Yes | Save extracted bill |
| `POST` | `/api/v1/ai/summaries/:period` | Yes | Daily/monthly summaries |

## Data Model

MongoDB collections:

- `users`
- `sessions`
- `expenses`
- `friends`
- `friendships`
- `groups`
- `group_expenses`
- `recurring_templates`
- `ai_jobs`
- `ai_suggestions`

## Quality Bar

- Backend tests run with `pytest`.
- Frontend tests run with `flutter test`.
- Static analysis runs with `flutter analyze`.
- Local dev starts through `scripts/start_expense_dev_tmux.sh --no-attach`.
- ngrok exposes the local FastAPI server when remote device testing is needed.
