# Frontend Plan: Flutter + Hydrated Bloc + Splitwise-Style UX

Last updated: 2026-02-24

## 1. Goal
Build the frontend as a production-ready Flutter app using `flutter_bloc` + `hydrated_bloc`, with UX inspired by Splitwise flows:
- Friends tab (net balance summary + friend balances)
- Groups tab (group balances + settled filters)
- Activity tab (ledger feed)
- Account tab
- Add Expense flow (participant picker, amount, paid-by, split mode)

This plan is tailored to the current repository state in `frontend/`.

## 2. Current Baseline (What Exists Today)
- Data models and repositories exist for `Expense`, `Group`, and `Friend`.
- `ExpensesBloc` and `FriendsBloc` exist, but are not yet wired to UI.
- `main.dart` is still the default Flutter counter app.
- `features/auth/`, `app/`, and `domain/` folders exist but are empty.
- `flutter analyze` currently reports structural errors (notably wrong imports for `groups_datasource.dart`) and missing dependencies (`bloc`, `bloc_test`).

## 3. External Pattern Alignment

### Bloc Tutorials (from bloclibrary.dev)
- Use app-level auth gating pattern (Firebase login tutorial):
  - `AuthenticationRepository`
  - `AppBloc` with auth status stream
  - Route/view switching based on auth state
- Use feature-sliced bloc organization (Todos tutorial):
  - One bloc/cubit per feature boundary
  - Explicit events/states and test-first behavior for state transitions

### Bloc Lint
- Adopt `bloc_lint` recommended rules in `analysis_options.yaml`.
- Add lint/dependency setup before expanding features to avoid style drift.

## 4. Product Scope (V1 Frontend)

### Screens
1. Auth
2. Friends
3. Groups
4. Activity
5. Account
6. Add Expense modal/screen
7. Group/Friend detail (light V1)

### Core Behaviors
- Bottom navigation with 4 tabs and persistent state per tab.
- Floating "Add expense" action from Friends/Groups/Activity.
- Net summary text ("Overall, you are owed / you owe").
- Settled-item collapse/expand behavior.
- Activity items with counterparty, context, timestamp, and signed amount.
- Add expense flow:
  - Select people/group
  - Description
  - Amount + currency
  - Paid by
  - Split mode (equal in V1; exact/percent in V1.1)

## 5. Architecture Plan

### 5.1 Layering
- `features/*` for presentation + bloc/cubit
- `data/*` for DTO/model + datasource + repository
- `app/*` for app bootstrap, DI, navigation shell
- `core/*` for shared utilities/constants/errors

### 5.2 State Management
- `HydratedBloc` for persisted UI/domain state:
  - `SessionCubit` (auth/session metadata)
  - `FriendsBloc` (cached balances list)
  - `GroupsBloc` (cached groups list)
  - `ActivityBloc` (recent feed cache)
  - `DraftExpenseCubit` (in-progress expense form)
- Non-hydrated blocs for short-lived actions:
  - `AddExpenseBloc` submit workflow
  - `AccountBloc` one-shot commands (logout/profile refresh)

### 5.3 Data Sources
- Short term: keep existing local (Hive) + remote (Firebase/HTTP) pattern.
- Medium term: align remote datasource to backend API contract once backend stabilizes.

## 6. Phased Implementation

## Phase 0: Stabilize Project Foundation
- Fix import path mismatches:
  - `groups_datasource.dart` references -> `groups.dart`
- Add missing dependencies:
  - `bloc` (or migrate imports to `flutter_bloc` only)
  - `hydrated_bloc`
  - `bloc_test`
  - `path_provider` (for hydrated storage dir)
- Wire `analysis_options.yaml` to `bloc_lint`.
- Keep app compiling with zero analyzer errors before feature work.

Exit criteria:
- `flutter analyze` passes.
- Existing tests compile.

## Phase 1: App Bootstrap + Auth Shell
- Replace counter app in `main.dart` with app bootstrap:
  - `WidgetsFlutterBinding.ensureInitialized()`
  - `Firebase.initializeApp(...)`
  - `HydratedBloc.storage = ...`
- Create:
  - `app/app.dart`
  - `app/view/app.dart`
  - `app/routes/*` (or `go_router` if preferred)
- Implement auth gate per Firebase login tutorial pattern:
  - `AuthenticationRepository`
  - `AppBloc` / `AppState`
  - Authenticated -> tab shell
  - Unauthenticated -> login screen

Exit criteria:
- Cold start routes correctly based on auth state.
- Session survives app restart.

## Phase 2: Splitwise-Style Tab Shell
- Implement bottom navigation with tabs:
  - Friends, Groups, Activity, Account
- Add FAB behavior:
  - visible on Friends/Groups/Activity
  - opens Add Expense flow
- Introduce placeholder but wired screens for all tabs with bloc-provided state.

Exit criteria:
- Navigation + state retention works across tab switches and restart.

## Phase 3: Friends and Groups (Read Flows)
- Friends:
  - Overall balance header
  - Friend rows with "owes you / you owe"
  - Settled section toggle
- Groups:
  - Overall balance header
  - Group rows + settlement status
  - Settled groups toggle
- Build `GroupsBloc` and normalize view models for money formatting and labels.

Exit criteria:
- Friends/Groups lists render from repository data with loading/empty/error states.

## Phase 4: Activity Feed
- Implement `ActivityBloc` and activity list UI:
  - Actor, action, group/friend context
  - Colored amount text and timestamps
- Add pagination or capped list (e.g., last 50 items cached).

Exit criteria:
- Activity tab reflects repository updates and persists recent feed.

## Phase 5: Add Expense End-to-End
- Add expense flow in two steps:
  1. Participant/group selection
  2. Expense details form
- Use `DraftExpenseCubit` (`HydratedCubit`) for draft persistence.
- Submit via `AddExpenseBloc`, then refresh affected tabs.
- V1 split support:
  - equal split only
  - paid by current user (extendable to member picker)

Exit criteria:
- User can create expense and see updates in Friends/Groups/Activity.

## Phase 6: Account + Settings
- Account page:
  - profile summary
  - settings list tiles
  - logout action
- Hook logout to clear hydrated state where needed.

Exit criteria:
- Logout resets session and returns to auth screen.

## Phase 7: Quality Gates
- Unit tests:
  - blocs/cubits (state transitions)
  - repository behavior
- Widget tests:
  - tab shell navigation
  - add expense flow happy path
- Golden/snapshot tests for key screens (optional but recommended).

Exit criteria:
- `flutter test` green for critical paths.
- Regressions blocked by CI checks.

## 7. Concrete Backlog (First 10 Tasks)
1. Fix datasource import path issues and make analyzer green.
2. Add `hydrated_bloc`, `bloc_test`, and `bloc_lint` setup.
3. Replace default `main.dart` with app bootstrap + hydration storage.
4. Create auth repository + `AppBloc` state gate.
5. Build tab shell scaffold with bottom navigation and FAB.
6. Add `GroupsBloc` (read-only list first).
7. Refactor `FriendsBloc` outputs to explicit balance view models.
8. Implement activity model + `ActivityBloc` + list UI.
9. Build Add Expense flow with hydrated draft state.
10. Add tests for app bootstrap, auth gate, and add expense submit flow.

## 8. Risks and Mitigations
- Risk: Existing repo has partial architecture and stale imports.
  - Mitigation: enforce Phase 0 hard gate before new feature code.
- Risk: Hydrated schema changes may break persisted state.
  - Mitigation: include bloc state `version` and migration fallbacks.
- Risk: UI parity with Splitwise can inflate scope.
  - Mitigation: focus V1 on functional parity, not exact visual cloning.

## 9. Definition of Done (Frontend V1)
- App boots into auth-aware shell.
- Friends/Groups/Activity/Account tabs functional.
- Add expense flow works and updates downstream states.
- Offline-safe state restoration via `hydrated_bloc`.
- Analyzer clean + tests passing for critical flows.

