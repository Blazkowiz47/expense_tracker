# Expense Tracker - Execution Plan

## 1. Objective
Build a production-ready expense tracker for iOS, Android, and Web using `frontend/` (Flutter) and `backend/` (Go + Gin + Firestore), with Firebase Authentication.

### Success Criteria
- Authenticated users can create, read, update, and delete only their own expenses.
- Users can view expenses by date and category, plus monthly/category analytics.
- Backend API has structured error responses and pagination.
- Core user flows work on Android, iOS, and Web without platform-specific blockers.

## 2. Scope
### In Scope
- Firebase Auth integration (Google and Email/Password).
- Go API with token verification and expense/analytics endpoints.
- Firestore data model and required indexes.
- Flutter UI for auth, expense CRUD, and charts.

### Out of Scope (V1)
- Shared family wallets/multi-user households.
- Budget goals, alerts, recurring expense automation.
- Receipt OCR/import from bank statements.

## 3. Architecture
### Request Flow
1. Flutter app signs in with Firebase Auth.
2. Flutter sends `Authorization: Bearer <Firebase ID Token>` to Go API.
3. Go middleware verifies token with Firebase Admin SDK and extracts `uid`.
4. API reads/writes Firestore documents scoped by `uid`.

### Components
- Client (`frontend/`): Flutter + BLoC + Dio + fl_chart.
- API (`backend/`): Gin routes, auth middleware, handlers/services/repositories.
- Auth: Firebase Authentication.
- Data store: Firestore (accessed only by backend service account).

## 4. Delivery Plan
### Phase 0 - Foundation and Guardrails
### Tasks
- Define environment variables for backend and frontend.
- Standardize folder structure in `backend/` (`cmd`, `internal`, optional `pkg`).
- Add basic lint/test commands and a short local run guide.

### Exit Criteria
- Backend boots locally with `/health` endpoint.
- Frontend runs on at least one mobile target and web.

### Phase 1 - Backend Core
### Tasks
- Implement config loading and Firebase Admin initialization.
- Implement auth middleware for bearer token verification.
- Add consistent error envelope:
```json
{ "error": { "code": "INVALID_ARGUMENT", "message": "..." } }
```
- Add request logging and request ID propagation.

### Exit Criteria
- Unauthorized requests fail with `401`.
- Verified requests include `uid` in request context.

### Phase 2 - Expense API (CRUD)
### Tasks
- `POST /api/v1/expenses` with validation.
- `GET /api/v1/expenses` with `page`, `limit`, optional `from`, `to`, `category`.
- `PUT /api/v1/expenses/:id` with ownership enforcement.
- `DELETE /api/v1/expenses/:id` with ownership enforcement.

### Exit Criteria
- Users cannot access or modify other users' records.
- Pagination and filters are deterministic and tested.

### Phase 3 - Flutter Integration
### Tasks
- Build auth state handling (`AuthRepository` + `AuthBloc`).
- Add Dio interceptor to attach fresh Firebase ID token.
- Build expense list, create/edit form, and delete interaction.
- Handle loading, empty, error, and retry states.

### Exit Criteria
- End-to-end CRUD works against backend for authenticated users.
- No unauthenticated API calls from protected screens.

### Phase 4 - Analytics
### Tasks
- Implement `GET /api/v1/analytics` (monthly totals + category breakdown).
- Build chart widgets with `fl_chart`.
- Add filters (month/date range) and corresponding API query params.

### Exit Criteria
- Analytics match raw expense data for the same period.
- Chart screens render correctly on mobile and web layouts.

### Phase 5 - Quality and Release Readiness
### Tasks
- Backend tests: middleware, validation, repository behavior.
- Frontend tests: BLoC tests and widget tests for key flows.
- Add seed data script or fixture strategy for local QA.
- Document deploy steps and environment setup.

### Exit Criteria
- Green test suite in CI/local for backend and frontend.
- Deployment checklist completed for staging.

## 5. API Contract (V1)
| Method | Endpoint | Auth | Notes |
| :--- | :--- | :--- | :--- |
| `GET` | `/health` | No | Liveness check |
| `GET` | `/api/v1/expenses` | Yes | Query params: `page`, `limit`, `from`, `to`, `category` |
| `POST` | `/api/v1/expenses` | Yes | Create expense |
| `PUT` | `/api/v1/expenses/:id` | Yes | Update owned expense |
| `DELETE` | `/api/v1/expenses/:id` | Yes | Delete owned expense |
| `GET` | `/api/v1/analytics` | Yes | Monthly + category aggregates |

### Expense Payload
```json
{
  "amount": 150.5,
  "category": "Groceries",
  "description": "Weekly shopping",
  "date": "2026-01-27T10:00:00Z"
}
```

Validation rules:
- `amount` > 0
- `category` is non-empty and normalized to a fixed set or canonical casing
- `date` is RFC3339 UTC

## 6. Firestore Data Model
Collection: `expenses`

```json
{
  "id": "auto_doc_id",
  "uid": "firebase_uid",
  "amount": 150.5,
  "category": "Groceries",
  "description": "Weekly shopping",
  "date": "2026-01-27T10:00:00Z",
  "createdAt": "2026-01-27T10:00:00Z",
  "updatedAt": "2026-01-27T10:00:00Z"
}
```

Indexes to plan early:
- `uid` + `date (desc)` for timeline listing.
- `uid` + `category` + `date (desc)` for filtered listing.

## 7. Risks and Mitigations
- Token verification latency: cache Firebase app/client instances and reuse per process.
- Query/index surprises: define required composite indexes in advance.
- Cross-platform UI drift: validate core screens on Android, iOS, and Web every sprint.
- Scope creep: defer budgets/recurring/shared wallets until V1 acceptance criteria are met.

## 8. Definition of Done (V1)
- All Phase 0-5 exit criteria are met.
- API and app behavior documented in `README`.
- Staging build is deployable and testable end-to-end with real Firebase Auth and Firestore.
