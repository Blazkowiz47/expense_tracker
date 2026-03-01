# Expense Tracker Next Steps (Sequential)

## Status legend
- `[ ]` pending
- `[~]` in progress
- `[x]` done

## Roadmap
1. `[x]` Settle-up flow (first slice)
2. `[x]` Recurring expenses
3. `[ ]` Notifications
4. `[x]` Expense detail completion (delete/download/remove attachment + audit)
5. `[x]` Group balances v2 (simplify transfer suggestions)
6. `[x]` Search and filters
7. `[x]` Export and reporting
8. `[x]` Production hardening

## Current item: 1) Settle-up flow
- `[x]` Add a Friends page `Settle up` action with amount input.
- `[x]` Persist settlement as a backend expense entry (`category=Settlement`).
- `[x]` Reflect settlement in friend-level owed/owe aggregates.
- `[x]` Add settle-up actions from group settings/member cards.
- `[x]` Add unit tests for settlement parsing and net-balance aggregation.
- `[x]` Add integration tests for settle-up state transitions.

## Current item: 2) Recurring expenses
- `[x]` Add backend recurring templates API (`GET/POST /api/v1/recurring/templates`).
- `[x]` Add overview recurring summary card wired to backend API.
- `[x]` Add create recurring template UI (title, amount, frequency, start date).
- `[x]` Generate due personal expenses from templates (manual backend processor endpoint).

## Current item: 4) Expense detail completion
- `[x]` Add group expense delete endpoint and UI flow.
- `[x]` Show group expense audit metadata (`updatedAt`, `updatedBy`) in edit dialog.
- `[x]` Keep attachment remove/preview actions in expense detail form.

## Current item: 5) Group balances v2
- `[x]` Add transfer suggestion calculator to simplify debts.
- `[x]` Render suggested transfers in group settings when simplify is enabled.
- `[x]` Add unit tests for transfer simplification logic.

## Current item: 6) Search and filters
- `[x]` Add activity search input.
- `[x]` Add activity type filters (`All`, `Spent`, `Incoming`).
- `[x]` Add time window filters (`Any time`, `Last 7d`, `Last 30d`).

## Current item: 7) Export and reporting
- `[x]` Add backend CSV export endpoint (`GET /api/v1/expenses-export.csv`).
- `[x]` Add frontend export action in Activity page.
- `[x]` Add backend export endpoint test coverage.

## Current item: 8) Production hardening
- `[x]` Add backend config validation (`AUTH_MODE`, Firebase requirements, production CORS requirement).
- `[x]` Add stricter CORS behavior (allowlist in production).
- `[x]` Add config and CORS tests.
