# Expense Tracker Next Steps (Sequential)

## Status legend
- `[ ]` pending
- `[~]` in progress
- `[x]` done

## Roadmap
1. `[~]` Settle-up flow (first slice)
2. `[ ]` Recurring expenses
3. `[ ]` Notifications
4. `[ ]` Expense detail completion (delete/download/remove attachment + audit)
5. `[ ]` Group balances v2 (simplify transfer suggestions)
6. `[ ]` Search and filters
7. `[ ]` Export and reporting
8. `[ ]` Production hardening

## Current item: 1) Settle-up flow
- `[x]` Add a Friends page `Settle up` action with amount input.
- `[x]` Persist settlement as a backend expense entry (`category=Settlement`).
- `[x]` Reflect settlement in friend-level owed/owe aggregates.
- `[x]` Add settle-up actions from group settings/member cards.
- `[x]` Add unit tests for settlement parsing and net-balance aggregation.
- `[x]` Add integration tests for settle-up state transitions.
