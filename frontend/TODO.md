# Expense Tracker - Backend-First TDD Roadmap# Expense Tracker - Backend-First TDD Roadmap



**Last Updated**: November 16, 2025



---**Last Updated**: November 16, 2025# Expense Tracker - Project Plan & TDD Roadmap



## 🏗️ ARCHITECTURE OVERVIEW



### Technology Stack---## 🏗️ ARCHITECTURE OVERVIEW



| Layer | Technology | Purpose |

|-------|------------|---------|

| **Backend** | Django 5.x + DRF | API server, business logic |## 🏗️ ARCHITECTURE OVERVIEW**Last Updated**: November 16, 2025

| **Database** | Firebase Firestore (NoSQL) | Data storage (backend-only access) |

| **Auth** | Firebase Authentication | Google Sign-In only |

| **Frontend** | Flutter 3.x | Thin client (UI + API calls) |

| **Offline Cache** | Hive | Local storage in Flutter |### Technology Stack### System Architecture

| **Hosting** | Heroku/Railway | Backend deployment |



### Why Backend-First?

| Layer | Technology | Purpose |This project uses a **backend-first architecture** with clear separation of concerns:

✅ **Security**: No direct Firestore access from Flutter  

✅ **Complex Logic**: Split calculations server-side  |-------|------------|---------|

✅ **Data Integrity**: Backend validates everything  

✅ **Testability**: Isolated backend logic  | **Backend** | Django 5.x + DRF | API server, business logic |**Technology Stack**:

✅ **Scalability**: Easy feature additions  

| **Database** | Firebase Firestore (NoSQL) | Data storage (backend-only access) |- **Backend**: Django 5.x + Django REST Framework + Firebase Admin SDK

### Data Flow

| **Auth** | Firebase Authentication | Google Sign-In only |- **Database**: Firebase Firestore (NoSQL, accessed via backend only)

```

Flutter → Django API → Firebase Admin SDK → Firestore| **Frontend** | Flutter 3.x | Thin client (UI + API calls) |- **Frontend**: Flutter 3.x (thin client, calls REST API, offline caching with Hive)

   ↓

 Hive (offline)| **Offline Cache** | Hive | Local storage in Flutter |- **Auth**: Firebase Authentication (Google Sign-In only)

```

| **Hosting** | Heroku/Railway | Backend deployment |- **Hosting**: Heroku/Railway/Render (free tier)

### Authentication



```

1. Google Sign-In (Flutter) → Firebase Auth → ID token### Why Backend-First?### Why Backend-First?

2. POST /api/auth/google/ with ID token

3. Django verifies with Firebase Admin SDK

4. All API calls: Authorization: Bearer <firebase-id-token>

```✅ **Security**: No direct Firestore access from Flutter  **Rationale**:



---✅ **Complex Logic**: Split calculations server-side  - ✅ **Security**: Centralized access control, users cannot bypass business logic



## 📊 FIRESTORE DATA MODEL✅ **Data Integrity**: Backend validates everything  - ✅ **Complex Calculations**: Split algorithms, balance calculations happen server-side



```javascript✅ **Testability**: Isolated backend logic  - ✅ **Data Integrity**: Backend validates all operations (group membership, expense ownership)

users/{uid}

  email, displayName, avatarUrl, createdAt, updatedAt✅ **Scalability**: Easy feature additions  - ✅ **Testability**: Backend logic isolated and easier to test comprehensively



groups/{groupId}- ✅ **Scalability**: Can add features without Flutter app changes

  name, creatorId, memberIds[], createdAt, updatedAt, isActive

  ### Data Flow

  /members/{userId}

    userId, displayName, avatarUrl, joinedAt**Security Model**:

  

  /expenses/{expenseId}```- 🔒 Flutter NEVER accesses Firestore directly (all access via Django API)

    description, totalAmount, currency, category,

    paidBy, splits{userId: amount}, createdAt, updatedAt, deletedAtFlutter → Django API → Firebase Admin SDK → Firestore- 🔒 Firebase Authentication handles Google Sign-In (OAuth2)



balances/{balanceId}   ↓- 🔒 Firebase ID tokens verified by Django (Firebase Admin SDK)

  groupId, debtorId, creditorId, amount, updatedAt

``` Hive (offline)- 🔒 Backend enforces member-only access to groups and expenses



**Security**: Member-only access, backend validates all operations```- 🔒 Split calculations validated server-side (cannot be manipulated)



---- 🔒 Firestore Security Rules provide defense-in-depth



## 🔌 API ENDPOINTS### Authentication



```### Data Flow

Auth:        POST   /api/auth/google/

             GET    /api/auth/me/```



Groups:      GET    /api/groups/1. Google Sign-In (Flutter) → Firebase Auth → ID token```

             POST   /api/groups/

             GET    /api/groups/{id}/2. POST /api/auth/google/ with ID token┌─────────────────────────────────────────────────────────┐

             DELETE /api/groups/{id}/

             POST   /api/groups/{id}/members/3. Django verifies with Firebase Admin SDK│                    FLUTTER APP                          │



Expenses:    GET    /api/expenses/4. All API calls: Authorization: Bearer <firebase-id-token>│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌─────────┐ │

             POST   /api/expenses/

             PATCH  /api/expenses/{id}/```│  │  Groups  │  │ Activity │  │Analytics │  │ Account │ │

             DELETE /api/expenses/{id}/

│  │  Screen  │  │  Screen  │  │  Screen  │  │ Screen  │ │

Balances:    GET    /api/balances/

             POST   /api/balances/settle/---│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬────┘ │



Analytics:   GET    /api/analytics/summary/│       └─────────────┴──────────────┴─────────────┘      │

             GET    /api/analytics/trends/

             GET    /api/analytics/categories/## 📊 FIRESTORE DATA MODEL│                      │                                   │

```

│               ┌──────▼──────┐                           │

---

```javascript│               │ BLoC Layer  │                           │

## 📋 DEVELOPMENT PLAN

users/{uid}│               └──────┬──────┘                           │

**TDD**: Red → Green → Refactor  

**Coverage**: 90%+ backend, 80%+ frontend  email, displayName, avatarUrl, createdAt, updatedAt│                      │                                   │



---│               ┌──────▼──────┐                           │



## BACKEND (Django + Firestore)groups/{groupId}│               │ Repository  │                           │



### Phase 1: Setup (2-3 days)  name, creatorId, memberIds[], createdAt, updatedAt, isActive│               └──────┬──────┘                           │



- [ ] Create Django project + `api` app  │                      │                                   │

- [ ] Install: django, djangorestframework, firebase-admin, python-decouple, django-cors-headers, pytest

- [ ] Setup Firebase Admin SDK in `config/firebase_client.py`  /members/{userId}│       ┌──────────────┴────────────────┐                │

- [ ] Test Firestore connection ✅

- [ ] Test Firebase Auth available ✅    userId, displayName, avatarUrl, joinedAt│       │                                │                │

- [ ] Configure DRF + CORS in settings

  │  ┌────▼────┐                    ┌─────▼──────┐        │

### Phase 2: Authentication (3-4 days)

  /expenses/{expenseId}│  │ApiClient│                    │Hive Cache  │        │

- [ ] **Token Verification (TDD)**

  - [ ] Test: `verify_firebase_token(id_token)` → user info    description, totalAmount, currency, category,│  │  (Dio)  │                    │ (Offline)  │        │

  - [ ] Implement using `auth.verify_id_token()`

  - [ ] Test: invalid token → exception    paidBy, splits{userId: amount}, createdAt, updatedAt, deletedAt│  └────┬────┘                    └────────────┘        │

  - [ ] Tests pass ✅

└───────┼───────────────────────────────────────────────┘

- [ ] **User Management (TDD)**

  - [ ] Test: `get_or_create_user(uid, email, name)`balances/{balanceId}        │

  - [ ] Implement: create/update in Firestore `users/{uid}`

  - [ ] Tests pass ✅  groupId, debtorId, creditorId, amount, updatedAt        │ HTTPS + Firebase ID Token



- [ ] **Custom Auth Class (TDD)**```        │

  - [ ] Test: `FirebaseAuthentication` extracts & verifies token

  - [ ] Implement `BaseAuthentication`┌───────▼────────────────────────────────────────────────┐

  - [ ] Tests pass ✅

**Security**: Member-only access, backend validates all operations│              DJANGO REST API                            │

- [ ] **Endpoints (TDD)**

  - [ ] Test: `POST /api/auth/google/` with ID token → user data│  ┌──────────────────────────────────────────────────┐  │

  - [ ] Implement

  - [ ] Test: invalid token → 401---│  │        FirebaseAuthentication Middleware          │  │

  - [ ] Test: `GET /api/auth/me/` → current user

  - [ ] Implement│  │     (Verifies Firebase ID token on every req)     │  │

  - [ ] All tests pass ✅

## 🔌 API ENDPOINTS│  └───────────────────┬──────────────────────────────┘  │

### Phase 3: Groups (4-5 days)

│                      │                                  │

- [ ] **Serializers (TDD)**

  - [ ] Test: `GroupSerializer` validates name, memberIds```│  ┌───────────────────▼──────────────────────────────┐  │

  - [ ] Implement

  - [ ] Tests pass ✅Auth:        POST   /api/auth/google/│  │          API Views (DRF ViewSets)                 │  │



- [ ] **Services (TDD)**             GET    /api/auth/me/│  │  /auth/google/, /groups/, /expenses/,            │  │

  - [ ] Test: `create_group(name, creator_id, member_ids)`

  - [ ] Implement: create in `groups/{id}` + members subcollection│  │  /balances/, /analytics/                         │  │

  - [ ] Test: `get_user_groups(user_id)`

  - [ ] Implement: query where memberIds contains user_idGroups:      GET    /api/groups/│  └───────────────────┬──────────────────────────────┘  │

  - [ ] Test: `add_member()`, `remove_member()`

  - [ ] Implement with validation             POST   /api/groups/│                      │                                  │

  - [ ] Tests pass ✅

             GET    /api/groups/{id}/│  ┌───────────────────▼──────────────────────────────┐  │

- [ ] **Authorization (TDD)**

  - [ ] Test: `@require_group_membership` decorator             DELETE /api/groups/{id}/│  │         Business Logic Services                   │  │

  - [ ] Implement: check user in memberIds, 403 if not

  - [ ] Tests pass ✅             POST   /api/groups/{id}/members/│  │  • Group membership validation                   │  │



- [ ] **Endpoints (TDD)**│  │  • Split calculation algorithms                  │  │

  - [ ] Test: `GET /api/groups/` → only user's groups

  - [ ] ImplementExpenses:    GET    /api/expenses/│  │  • Balance calculation & simplification          │  │

  - [ ] Test: `POST /api/groups/` → creates group

  - [ ] Test: non-member access → 403             POST   /api/expenses/│  │  • Authorization checks                          │  │

  - [ ] Test: only creator can DELETE → 403

  - [ ] Test: `POST /api/groups/{id}/members/`             PATCH  /api/expenses/{id}/│  └───────────────────┬──────────────────────────────┘  │

  - [ ] All tests pass ✅

             DELETE /api/expenses/{id}/│                      │                                  │

### Phase 4: Expenses & Splits (5-6 days)

│  ┌───────────────────▼──────────────────────────────┐  │

- [ ] **Serializers (TDD)**

  - [ ] Test: validations (amount > 0, sum == total, userIds exist, paidBy in splits)Balances:    GET    /api/balances/│  │        Firebase Admin SDK                         │  │

  - [ ] Implement `ExpenseSerializer`

  - [ ] Tests pass ✅             POST   /api/balances/settle/│  │  • auth.verify_id_token()                        │  │



- [ ] **Split Calculations (TDD)**│  │  • firestore.client()                            │  │

  - [ ] Test: `calculate_equal_split(total, num_people)`

  - [ ] Implement (handle rounding)Analytics:   GET    /api/analytics/summary/│  └───────────────────┬──────────────────────────────┘  │

  - [ ] Test: `calculate_percentage_split()`

  - [ ] Implement             GET    /api/analytics/trends/└──────────────────────┼──────────────────────────────────┘

  - [ ] Tests pass ✅

             GET    /api/analytics/categories/                       │

- [ ] **Services (TDD)**

  - [ ] Test: `create_expense(...)` with security checks```                       │

  - [ ] Implement:

    - Verify user in group.memberIds┌──────────────────────▼──────────────────────────────────┐

    - Verify all split userIds are members

    - Verify sum(splits) == totalAmount---│             FIREBASE FIRESTORE (NoSQL)                   │

    - Create in `groups/{id}/expenses/{id}`

    - Trigger balance recalculation│                                                          │

  - [ ] Tests pass ✅

## 📋 DEVELOPMENT PLAN│  Collections:                                            │

- [ ] **Endpoints (TDD)**

  - [ ] Test: `POST /api/expenses/` member → success, non-member → 403│  • users/{uid}                                          │

  - [ ] Test: `GET /api/expenses/` → only user's group expenses

  - [ ] Test: `?groupId={id}` filtering**TDD**: Red → Green → Refactor  │  • groups/{groupId}                                     │

  - [ ] Test: only creator can PATCH/DELETE → 403

  - [ ] Test: DELETE soft deletes (sets deletedAt)**Coverage**: 90%+ backend, 80%+ frontend│      └── members/{userId}       (subcollection)         │

  - [ ] All tests pass ✅

│      └── expenses/{expenseId}   (subcollection)         │

### Phase 5: Balances (4-5 days)

---│  • balances/{balanceId}                                 │

- [ ] **Calculation Algorithm (TDD)**

  - [ ] Test: `calculate_group_balances(group_id)`│                                                          │

  - [ ] Implement:

    ```## BACKEND (Django + Firestore)│  Security Rules: Member-only access enforced            │

    For each expense: payer is owed by each participant

    Aggregate debts between pairs└─────────────────────────────────────────────────────────┘

    Simplify: net_debt = owed - owing

    ```### Phase 1: Setup (2-3 days)```

  - [ ] Test: simplification (A owes B $10, B owes A $3 → A owes B $7)

  - [ ] Tests pass ✅



- [ ] **Services (TDD)**- [ ] Create Django project + `api` app### Authentication Flow

  - [ ] Test: `get_user_balances(user_id)`

  - [ ] Test: `record_settlement(debtor, creditor, amount)`- [ ] Install: django, djangorestframework, firebase-admin, python-decouple, django-cors-headers, pytest

  - [ ] Implement with security checks (user == debtor, amount <= balance)

  - [ ] Tests pass ✅- [ ] Setup Firebase Admin SDK in `config/firebase_client.py````



- [ ] **Endpoints (TDD)**- [ ] Test Firestore connection ✅1. User clicks "Sign in with Google" in Flutter app

  - [ ] Test: `GET /api/balances/` → only user's balances

  - [ ] Test: cannot see others' balances → 403- [ ] Test Firebase Auth available ✅   ↓

  - [ ] Test: `POST /api/balances/settle/` with auth

  - [ ] Test: settle someone else's debt → 403- [ ] Configure DRF + CORS in settings2. Google Sign-In flow → Firebase Auth

  - [ ] Test: amount > balance → 400

  - [ ] All tests pass ✅   ↓



### Phase 6: Analytics (3-4 days)### Phase 2: Authentication (3-4 days)3. Firebase Auth returns Firebase ID token



- [ ] **Services (TDD)**   ↓

  - [ ] Test: `get_expense_summary(user_id, start, end)`

  - [ ] Implement (only user's groups, calc spent/share/balance)- [ ] **Token Verification (TDD)**4. Flutter sends ID token to Django: POST /api/auth/google/

  - [ ] Test: `get_category_breakdown()`

  - [ ] Test: `get_spending_trends()`  - [ ] Test: `verify_firebase_token(id_token)` → user info   ↓

  - [ ] Tests pass ✅

  - [ ] Implement using `auth.verify_id_token()`5. Django verifies token with Firebase Admin SDK

- [ ] **Endpoints (TDD)**

  - [ ] Test: `GET /api/analytics/summary/` for current user  - [ ] Test: invalid token → exception   ↓

  - [ ] Test: cannot request another user's analytics → 403

  - [ ] Test: `GET /api/analytics/categories/`  - [ ] Tests pass ✅6. Django creates/updates user in Firestore users/{uid}

  - [ ] Test: `GET /api/analytics/trends/`

  - [ ] All tests pass ✅   ↓



### Phase 7: Deployment (2-3 days)- [ ] **User Management (TDD)**7. Django returns user profile to Flutter



- [ ] **Security Hardening**  - [ ] Test: `get_or_create_user(uid, email, name)`   ↓

  - [ ] Production Django settings (DEBUG=False, HTTPS, etc)

  - [ ] Rate limiting: `@ratelimit(key='user', rate='10/m')`  - [ ] Implement: create/update in Firestore `users/{uid}`8. Flutter stores auth state (Firebase handles token refresh)

  - [ ] Test: 11th request → 429

  - [ ] CORS for production domain  - [ ] Tests pass ✅   ↓

  - [ ] Tests pass ✅

9. All subsequent API calls include: Authorization: Bearer <firebase-id-token>

- [ ] **Firestore Security Rules**

  - [ ] Deploy security rules (member-only access)- [ ] **Custom Auth Class (TDD)**```

  - [ ] Test with Firebase emulator

  - [ ] Enable Google Sign-In in Firebase Console  - [ ] Test: `FirebaseAuthentication` extracts & verifies token



- [ ] **Heroku Deployment**  - [ ] Implement `BaseAuthentication`---

  - [ ] Create Procfile, runtime.txt, requirements.txt

  - [ ] Configure env vars on Heroku  - [ ] Tests pass ✅

  - [ ] Upload Firebase service account key

  - [ ] Deploy---

  - [ ] Run: `python manage.py check --deploy`

  - [ ] Test production API- [ ] **Endpoints (TDD)**

  - [ ] All security tests pass ✅

  - [ ] Test: `POST /api/auth/google/` with ID token → user data## 📋 DEVELOPMENT ROADMAP

---

  - [ ] Implement

## FRONTEND (Flutter App)

  - [ ] Test: invalid token → 401This project follows **Test-Driven Development (TDD)** with the "Red-Green-Refactor" cycle:

### Phase 8: Setup & Auth (3-4 days)

  - [ ] Test: `GET /api/auth/me/` → current user1. **Red**: Write a failing test

- [ ] **Project Setup**

  - [ ] Create Flutter project  - [ ] Implement2. **Green**: Write minimal code to pass the test

  - [ ] Add deps: dio, firebase_core, firebase_auth, google_sign_in, flutter_bloc, hive

  - [ ] Initialize Firebase  - [ ] All tests pass ✅3. **Refactor**: Clean up the code



- [ ] **Google Sign-In (TDD)**

  - [ ] Test: `signInWithGoogle()`

  - [ ] Implement Google Sign-In flow### Phase 3: Groups (4-5 days)**Target Coverage**: 90%+ backend, 80%+ frontend

  - [ ] Tests pass ✅



- [ ] **API Client (TDD)**

  - [ ] Test: `ApiClient` sends Firebase ID token in headers- [ ] **Serializers (TDD)**---

  - [ ] Implement with Dio + token interceptor

  - [ ] Test: token auto-refresh  - [ ] Test: `GroupSerializer` validates name, memberIds

  - [ ] Tests pass ✅

  - [ ] Implement## PART 1: BACKEND DEVELOPMENT (Django + Firestore)

- [ ] **Auth Repository & BLoC (TDD)**

  - [ ] Test: `signInWithGoogle()` calls backend `/api/auth/google/`  - [ ] Tests pass ✅

  - [ ] Implement

  - [ ] bloc_test: `GoogleSignInEvent → AuthSuccess`### Phase 1: Project Setup & Firebase Configuration

  - [ ] Test: logout clears Firebase + Hive

  - [ ] Test: 401 → auto-logout- [ ] **Services (TDD)**

  - [ ] All tests pass ✅

  - [ ] Test: `create_group(name, creator_id, member_ids)````

- [ ] **Login Screen (TDD)**

  - [ ] Widget test: shows Google Sign-In button  - [ ] Implement: create in `groups/{id}` + members subcollectionlib/

  - [ ] Implement UI

  - [ ] Test: error handling  - [ ] Test: `get_user_groups(user_id)`│

  - [ ] Tests pass ✅

  - [ ] Implement: query where memberIds contains user_id├── app/                      # App-level configuration, routing, and DI

### Phase 9: Groups (4-5 days)

  - [ ] Test: `add_member()`, `remove_member()`│   ├── routes/               # App navigation logic

- [ ] Update Group model for API

- [ ] **Repository (TDD)**  - [ ] Implement with validation│   └── view/                 # Main app widget (e.g., MaterialApp)

  - [ ] Test: `getGroups()` calls API

  - [ ] Test: Hive caching  - [ ] Tests pass ✅│

  - [ ] Test: cache invalidation

  - [ ] Tests pass ✅├── core/                     # Shared utilities, constants, and base classes

- [ ] **BLoC (TDD)**

  - [ ] bloc_test: `LoadGroups → GroupsLoaded`- [ ] **Authorization (TDD)**│   ├── constants/

  - [ ] Test: `CreateGroup` with optimistic updates

  - [ ] Test: 403 → error state  - [ ] Test: `@require_group_membership` decorator│   ├── error/                # Custom exceptions and failures

  - [ ] Tests pass ✅

- [ ] **Screen (TDD)**  - [ ] Implement: check user in memberIds, 403 if not│   └── utils/

  - [ ] Widget test: displays groups

  - [ ] Test: member list (no user IDs shown)  - [ ] Tests pass ✅│

  - [ ] Tests pass ✅

├── data/                     # Data Layer: Data sources and repository implementations

### Phase 10: Expenses (4-5 days)

- [ ] **Endpoints (TDD)**│   ├── datasources/

- [ ] Update Expense model for API

- [ ] **Repository (TDD)**  - [ ] Test: `GET /api/groups/` → only user's groups│   │   ├── remote/           # Remote API client implementation

  - [ ] Test: `getExpenses()` calls API

  - [ ] Test: client-side split validation  - [ ] Implement│   │   └── local/            # Local persistence implementation

  - [ ] Tests pass ✅

- [ ] **BLoC (TDD)**  - [ ] Test: `POST /api/groups/` → creates group│   ├── models/               # Data Transfer Objects (DTOs) for serialization

  - [ ] bloc_test: `CreateExpense → ExpensesLoaded`

  - [ ] Test: split sum validation  - [ ] Test: non-member access → 403│   └── repositories/         # Concrete repository implementations

  - [ ] Test: 403 → error state

  - [ ] Tests pass ✅  - [ ] Test: only creator can DELETE → 403│

- [ ] **Screen (TDD)**

  - [ ] Widget test: expense list + split form  - [ ] Test: `POST /api/groups/{id}/members/`├── domain/                   # Domain Layer: Core business logic and contracts

  - [ ] Test: split calculator (sum == total)

  - [ ] Tests pass ✅  - [ ] All tests pass ✅│   ├── entities/             # Pure business objects (e.g., Expense)



### Phase 11: Balances & Analytics (3-4 days)│   ├── repositories/         # Abstract repository interfaces



- [ ] **Balances**### Phase 4: Expenses & Splits (5-6 days)│   └── usecases/             # Business logic operations (optional)

  - [ ] Implement BalancesRepository, BLoC, Screen

  - [ ] Tests pass ✅│



- [ ] **Analytics**- [ ] **Serializers (TDD)**└── features/                 # Feature Layer: UI (Screens/Widgets) and Business Logic (BLoCs)

  - [ ] Implement AnalyticsRepository, BLoC, Screen (charts)

  - [ ] Tests pass ✅  - [ ] Test: validations (amount > 0, sum == total, userIds exist, paidBy in splits)    │



### Phase 12: Integration (2-3 days)  - [ ] Implement `ExpenseSerializer`    ├── auth/                 # Authentication Feature



- [ ] **Home Screen**  - [ ] Tests pass ✅    │   ├── bloc/             # Auth BLoC/Cubit, events, and states

  - [ ] BottomNavigationBar (4 tabs: Groups, Activity, Analytics, Account)

  - [ ] FloatingActionButton for expense creation    │   └── view/             # Auth screens and widgets

  - [ ] App routing

- [ ] **Split Calculations (TDD)**    │

- [ ] **Dependency Injection**

  - [ ] Set up BlocProviders  - [ ] Test: `calculate_equal_split(total, num_people)`    └── expenses_overview/    # Expenses Overview Feature

  - [ ] Inject ApiClient + repositories

  - [ ] Implement (handle rounding)        ├── bloc/

- [ ] **E2E Testing**

  - [ ] Test: Google Sign-In → Create Group → Add Expense → View Balance  - [ ] Test: `calculate_percentage_split()`        └── view/

  - [ ] Test: Access another user's group → 403

  - [ ] Test: Edit another user's expense → 403  - [ ] Implement```

  - [ ] Test: Token expiration → auto-refresh

  - [ ] Test: Invalid token → redirect to login  - [ ] Tests pass ✅

  - [ ] Test: Sign out → clears auth + cache

  - [ ] Test: Offline mode works### 1.2. Layering Principles

  - [ ] All E2E tests pass ✅

- [ ] **Services (TDD)**

---

  - [ ] Test: `create_expense(...)` with security checks-   **Data Layer**: Responsible for retrieving raw data from APIs or local storage. Contains DTO models and concrete repository implementations. This project uses:

## ✅ SUCCESS CRITERIA

  - [ ] Implement:    - **Remote Storage**: Firebase Firestore for data persistence and Firebase Storage for file uploads

### Backend

- [ ] 90%+ test coverage    - Verify user in group.memberIds    - **Local Storage**: Hive or local SQLite for offline caching

- [ ] All endpoints functional

- [ ] All auth checks enforced    - Verify all split userIds are members-   **Domain Layer**: The core of the application. Contains pure business objects (entities) and abstract repository contracts. It is independent of any other layer.

- [ ] API responses < 500ms

- [ ] Deployed with HTTPS    - Verify sum(splits) == totalAmount-   **Feature Layer**: Contains all the UI and state management logic for specific features. It depends on the Domain layer to get data.



### Frontend    - Create in `groups/{id}/expenses/{id}`-   **Dependency Rule**: Dependencies flow inwards: `Features` -> `Domain` <- `Data`. The `Domain` layer has no external dependencies.

- [ ] 80%+ test coverage

- [ ] All screens functional    - Trigger balance recalculation

- [ ] Firebase tokens handled correctly

- [ ] App loads < 2s  - [ ] Tests pass ✅## 2. Testing & Development Strategy

- [ ] Google Sign-In seamless



### Integration

- [ ] All E2E tests pass- [ ] **Endpoints (TDD)**### 2.1. Test-Driven Development (TDD)

- [ ] Offline mode works

- [ ] Unauthorized access blocked  - [ ] Test: `POST /api/expenses/` member → success, non-member → 403

- [ ] No secrets in code

  - [ ] Test: `GET /api/expenses/` → only user's group expensesWe will follow the "Red-Green-Refactor" cycle for all new code:

---

  - [ ] Test: `?groupId={id}` filtering1.  **Red**: Write a failing test.

## 📚 COMMANDS

  - [ ] Test: only creator can PATCH/DELETE → 4032.  **Green**: Write the simplest code to make the test pass.

### Backend

```bash  - [ ] Test: DELETE soft deletes (sets deletedAt)3.  **Refactor**: Clean up the code.

pytest                        # All tests

pytest --cov=api             # With coverage  - [ ] All tests pass ✅

pytest path/to/test.py -v    # Specific test

```### 2.2. Code Generation (`json_serializable`)



### Frontend### Phase 5: Balances (4-5 days)

```bash

flutter test                        # All testsWe will use `json_serializable` to handle JSON parsing for our DTOs in `lib/data/models/`.

flutter test --coverage             # With coverage

flutter test path/to/test.dart      # Specific test- [ ] **Calculation Algorithm (TDD)**-   **Command**: `dart run build_runner build --delete-conflicting-outputs`

```

  - [ ] Test: `calculate_group_balances(group_id)`

---

  - [ ] Implement:### 2.3. Running Tests

**Follow TDD strictly: Red → Green → Refactor. High coverage. Clean code!**

    ```

    For each expense: payer is owed by each participantAll tests can be run from the project root.

    Aggregate debts between pairs-   **All Tests**: `flutter test`

    Simplify: net_debt = owed - owing-   **Code Coverage**: `flutter test --coverage`

    ```

  - [ ] Test: simplification (A owes B $10, B owes A $3 → A owes B $7)### 2.4. Firebase Integration

  - [ ] Tests pass ✅

This project uses Firebase for remote data storage:

- [ ] **Services (TDD)**-   **Firestore**: Primary database for storing expense records

  - [ ] Test: `get_user_balances(user_id)`-   **Firebase Storage**: For storing receipts or attachments (if needed)

  - [ ] Test: `record_settlement(debtor, creditor, amount)`-   **Firebase Authentication**: For user authentication and authorization

  - [ ] Implement with security checks (user == debtor, amount <= balance)

  - [ ] Tests pass ✅**Dependencies to add**:

- `cloud_firestore` — Firestore SDK

- [ ] **Endpoints (TDD)**- `firebase_core` — Firebase core SDK

  - [ ] Test: `GET /api/balances/` → only user's balances- `firebase_storage` — Storage SDK

  - [ ] Test: cannot see others' balances → 403- `firebase_auth` — Auth SDK (for later phases)

  - [ ] Test: `POST /api/balances/settle/` with auth- `mocktail` — For mocking Firebase services in tests

  - [ ] Test: settle someone else's debt → 403

  - [ ] Test: amount > balance → 400## 3. Project Development Plan (TDD Checklist)

  - [ ] All tests pass ✅

---

### Phase 6: Analytics (3-4 days)

### Phase 1: Setup & Core

- [ ] **Services (TDD)**- [x] Initialize the Flutter project.

  - [ ] Test: `get_expense_summary(user_id, start, end)`- [x] Create the directory structure inside `lib/` as shown in the diagram.

  - [ ] Implement (only user's groups, calc spent/share/balance)- [x] **Core**:

  - [ ] Test: `get_category_breakdown()`    - [x] Write a failing test for a shared utility in `test/core/utils/`.

  - [ ] Test: `get_spending_trends()`    - [x] Implement the utility in `lib/core/utils/` to pass the test.

  - [ ] Tests pass ✅

### Phase 2: Data & Domain Layers (TDD)

- [ ] **Endpoints (TDD)**- [x] **Domain Layer First**:

  - [ ] Test: `GET /api/analytics/summary/` for current user    - [x] Define the pure `Expense` entity in `lib/domain/entities/`.

  - [ ] Test: cannot request another user's analytics → 403    - [x] Define the abstract `ExpensesRepository` in `lib/domain/repositories/`.

  - [ ] Test: `GET /api/analytics/categories/`- [x] **Data Layer (Models & Serialization)**:

  - [ ] Test: `GET /api/analytics/trends/`    - [x] Define the `ExpenseCore` immutable core data in `lib/data/models/expense_core.dart`.

  - [ ] All tests pass ✅    - [x] Define the `Expense` wrapper DTO in `lib/data/models/expense.dart` with metadata (description, isSynced, deleted).

    - [x] Write failing tests for model serialization/deserialization in `test/unit/data/models/expense_test.dart`.

### Phase 7: Deployment (2-3 days)    - [x] Run the build runner to generate `.g.dart` files: `flutter pub run build_runner build --delete-conflicting-outputs`.

    - [x] All model tests passing (4 test cases).

- [ ] **Security Hardening**- [x] **Data Layer (Abstract Datasources)**:

  - [ ] Production Django settings (DEBUG=False, HTTPS, etc)    - [x] Define abstract `ExpensesDatasource` interface in `lib/data/datasources/expenses.dart`.

  - [ ] Rate limiting: `@ratelimit(key='user', rate='10/m')`    - [x] Methods return `bool` for write operations to indicate success/failure.

  - [ ] Test: 11th request → 429    - [x] Read operations return `Future<Expense?>` or `Future<List<Expense>>`.

  - [ ] CORS for production domain- [x] **Data Layer (Repository Implementation)**:

  - [ ] Tests pass ✅    - [x] Implement `ExpensesRepository` in `lib/data/repositories/expenses_repository.dart`:

        - [x] In-memory caching with `Map<String, Expense> _expensesCache`.

- [ ] **Firestore Security Rules**        - [x] `initialize()` method to load expenses from local datasource.

  - [ ] Deploy security rules (member-only access)        - [x] `createExpense()` - local-first save, then fire-and-forget remote sync.

  - [ ] Test with Firebase emulator        - [x] `updateExpense()` - local-first update, then async remote sync.

  - [ ] Enable Google Sign-In in Firebase Console        - [x] `deleteExpense()` - soft delete with `deleted: true` flag.

        - [x] `getExpenseById()` - O(1) cache lookup.

- [ ] **Heroku Deployment**        - [x] `getExpenses()` - return all from cache.

  - [ ] Create Procfile, runtime.txt, requirements.txt        - [x] `getUnsyncedExpenses()` - filter unsynced/deleted from cache.

  - [ ] Configure env vars on Heroku        - [x] `getExpensesByDateRange()` - filter cache by date range.

  - [ ] Upload Firebase service account key        - [x] `syncExpenses()` - retry unsynced expenses with fire-and-forget async.

  - [ ] Deploy        - [x] `refresh()` - pull all expenses from remote and update cache.

  - [ ] Run: `python manage.py check --deploy`        - [x] Internal `_syncExpenseToRemote()` - fire-and-forget async sync logic.

  - [ ] Test production API    - [x] Write comprehensive unit tests in `test/unit/data/repositories/expenses_repository_test.dart`.

  - [ ] All security tests pass ✅    - [x] Mock both local and remote datasources using `mocktail`.

    - [x] All 19 repository tests passing.

---- [x] **Dependencies**:

    - [x] Added `json_annotation` for JSON serialization support.

## FRONTEND (Flutter App)    - [x] Added `mocktail` for mocking in tests.

    - [x] Ran `flutter pub get` to install dependencies.

### Phase 8: Setup & Auth (3-4 days)

### Phase 3: Feature Layer & BLoC Architecture (TDD) - ⚠️ REPLACED BY PHASE 5.10-5.14

- [ ] **Project Setup**

  - [ ] Create Flutter project**Note**: This phase describes the original Flutter-only BLoC architecture where BLoCs talked directly to Firestore. With the backend-first approach (Phase 5), BLoCs will instead call REST API repositories. The sections below are kept for reference only.

  - [ ] Add deps: dio, firebase_core, firebase_auth, google_sign_in, flutter_bloc, hive

  - [ ] Initialize Firebase#### 3.1 Core Expenses BLoC (Original - Reference Only)

- [ ] ~~**Expenses BLoC** (REPLACED: See Phase 5.12 for API-based implementation)~~

- [ ] **Google Sign-In (TDD)**    - ~~Define events: `LoadExpenses`, `RefreshExpenses`, `CreateExpense`, `UpdateExpense`, `DeleteExpense`~~

  - [ ] Test: `signInWithGoogle()`    - ~~Define states: `ExpensesInitial`, `ExpensesLoading`, `ExpensesLoaded`, `ExpensesError`~~

  - [ ] Implement Google Sign-In flow    - ~~Interact with `ExpensesRepository` (which now calls Django API, not Firestore directly)~~

  - [ ] Tests pass ✅

#### 3.2 Dependent BLoCs (Original - Reference Only)

- [ ] **API Client (TDD)**- [ ] ~~**Friends BLoC** (REMOVED: Friends data comes from backend `/api/groups/{id}/members/`)~~

  - [ ] Test: `ApiClient` sends Firebase ID token in headers- [ ] ~~**Groups BLoC** (REPLACED: See Phase 5.11 for API-based implementation)~~

  - [ ] Implement with Dio + token interceptor- [ ] ~~**Activity BLoC** (REPLACED: Filtering/sorting done via API query params)~~

  - [ ] Test: token auto-refresh- [ ] ~~**Analytics BLoC** (REPLACED: See Phase 5.13 - backend calculates analytics)~~

  - [ ] Tests pass ✅

#### 3.3 Independent BLoCs (Original - Reference Only)

- [ ] **Auth Repository & BLoC (TDD)**- [ ] ~~**Account/Auth BLoC** (REPLACED: See Phase 5.10 for JWT-based auth)~~

  - [ ] Test: `signInWithGoogle()` calls backend `/api/auth/google/`- [ ] ~~**Add Expense Modal BLoC** (UPDATED: Will submit to API endpoint, not Firestore)~~

  - [ ] Implement

  - [ ] bloc_test: `GoogleSignInEvent → AuthSuccess`#### 3.4 UI Implementation (Original - Reference Only)

  - [ ] Test: logout clears Firebase + Hive- [ ] ~~**Expenses Overview/Detail Screens** (See Phase 5.12 for API-based implementation)~~

  - [ ] Test: 401 → auto-logout- [ ] ~~**Friends Screen** (REMOVED: Friends are now group members from API)~~

  - [ ] All tests pass ✅- [ ] ~~**Groups Screen** (See Phase 5.11 for API-based implementation)~~

- [ ] ~~**Activity/Transactions Screen** (Use API filtering instead)~~

- [ ] **Login Screen (TDD)**- [ ] ~~**Analytics Screen** (See Phase 5.13 - backend provides computed analytics)~~

  - [ ] Widget test: shows Google Sign-In button- [ ] ~~**Account Screen** (See Phase 5.10 for JWT auth-based implementation)~~

  - [ ] Implement UI- [ ] ~~**Add Expense Modal** (See Phase 5.12 - submits to API endpoint)~~

  - [ ] Test: error handling

  - [ ] Tests pass ✅### Phase 4: App Assembly & Navigation (TDD) - ⚠️ REPLACED BY PHASE 5.14



### Phase 9: Groups (4-5 days)**Note**: This phase is replaced by Phase 5.14 (App Integration) which uses API-based repositories instead of direct Firestore access.



- [ ] Update Group model for API- [ ] ~~**HomeScreen with Bottom Navigation** (See Phase 5.14)~~

- [ ] **Repository (TDD)**- [ ] ~~**Dependency Injection & Provider Setup** (See Phase 5.14 - inject ApiClient instead of Firestore)~~

  - [ ] Test: `getGroups()` calls API- [ ] ~~**App Root Widget** (See Phase 5.14)~~

  - [ ] Test: Hive caching- [ ] ~~**End-to-End (E2E) Testing** (See Phase 5.14)~~

  - [ ] Test: cache invalidation- [ ] ~~**CI/CD** (Updated for both Django and Flutter in Phase 5.7 and 5.14)~~

  - [ ] Tests pass ✅

- [ ] **BLoC (TDD)**---

  - [ ] bloc_test: `LoadGroups → GroupsLoaded`

  - [ ] Test: `CreateGroup` with optimistic updates## Phase 5: Backend-First Architecture (NEW)

  - [ ] Test: 403 → error state

  - [ ] Tests pass ✅### 📊 Firestore Data Structure (NoSQL Collections)

- [ ] **Screen (TDD)**

  - [ ] Widget test: displays groups**Security Model**: Member-only access pattern (users can only access groups they're in)

  - [ ] Test: member list (no user IDs shown)

  - [ ] Tests pass ✅```javascript

// users/{userId}

### Phase 10: Expenses (4-5 days){

  email: "user@example.com",

- [ ] Update Expense model for API  displayName: "John Doe",

- [ ] **Repository (TDD)**  avatarUrl: "https://...",

  - [ ] Test: `getExpenses()` calls API  createdAt: Timestamp,

  - [ ] Test: client-side split validation  updatedAt: Timestamp

  - [ ] Tests pass ✅}

- [ ] **BLoC (TDD)**// Security: User can only read/update their own document

  - [ ] bloc_test: `CreateExpense → ExpensesLoaded`

  - [ ] Test: split sum validation// groups/{groupId}

  - [ ] Test: 403 → error state{

  - [ ] Tests pass ✅  name: "Weekend Trip",

- [ ] **Screen (TDD)**  creatorId: "userId123",

  - [ ] Widget test: expense list + split form  memberIds: ["userId123", "userId456"],  // CRITICAL: Used for access control

  - [ ] Test: split calculator (sum == total)  createdAt: Timestamp,

  - [ ] Tests pass ✅  updatedAt: Timestamp,

  isActive: true

### Phase 11: Balances & Analytics (3-4 days)}

// Security: Only members (in memberIds array) can read this document

- [ ] **Balances**// Only creator can delete group

  - [ ] Implement BalancesRepository, BLoC, Screen// Any member can update group name

  - [ ] Tests pass ✅

// groups/{groupId}/members/{userId}  (Subcollection)

- [ ] **Analytics**{

  - [ ] Implement AnalyticsRepository, BLoC, Screen (charts)  userId: "userId123",

  - [ ] Tests pass ✅  displayName: "John Doe",

  avatarUrl: "https://...",

### Phase 12: Integration (2-3 days)  joinedAt: Timestamp

}

- [ ] **Home Screen**// Security: Only group members can read members subcollection

  - [ ] BottomNavigationBar (4 tabs: Groups, Activity, Analytics, Account)// Only creator can add/remove members

  - [ ] FloatingActionButton for expense creation

  - [ ] App routing// groups/{groupId}/expenses/{expenseId}  (Subcollection)

{

- [ ] **Dependency Injection**  description: "Dinner at restaurant",

  - [ ] Set up BlocProviders  totalAmount: 100.00,

  - [ ] Inject ApiClient + repositories  currency: "USD",

  category: "Food",

- [ ] **E2E Testing**  paidBy: "userId123",  // Who paid the bill

  - [ ] Test: Google Sign-In → Create Group → Add Expense → View Balance  splits: {             // Map of userId to share amount

  - [ ] Test: Access another user's group → 403    "userId123": 50.00,

  - [ ] Test: Edit another user's expense → 403    "userId456": 50.00

  - [ ] Test: Token expiration → auto-refresh  },

  - [ ] Test: Invalid token → redirect to login  createdAt: Timestamp,

  - [ ] Test: Sign out → clears auth + cache  updatedAt: Timestamp,

  - [ ] Test: Offline mode works  deletedAt: null  // Soft delete

  - [ ] All E2E tests pass ✅}

// Security: Only group members can read/create expenses

---// Only expense creator (paidBy) can edit/delete their expense

// Backend validates: sum(splits) == totalAmount

## ✅ SUCCESS CRITERIA// Backend validates: all userIds in splits are group members



### Backend// balances/{balanceId}

- [ ] 90%+ test coverage{

- [ ] All endpoints functional  groupId: "groupId789",

- [ ] All auth checks enforced  debtorId: "userId456",    // Person who owes money

- [ ] API responses < 500ms  creditorId: "userId123",  // Person who is owed money

- [ ] Deployed with HTTPS  amount: 50.00,            // Amount owed

  updatedAt: Timestamp

### Frontend}

- [ ] 80%+ test coverage// Security: Only debtor and creditor can read this balance

- [ ] All screens functional// Only backend can write balances (auto-calculated from expenses)

- [ ] Firebase tokens handled correctly// Backend recalculates on every expense create/update/delete

- [ ] App loads < 2s```

- [ ] Google Sign-In seamless

**Firestore Security Rules** (defense-in-depth even with Admin SDK):

### Integration```javascript

- [ ] All E2E tests passrules_version = '2';

- [ ] Offline mode worksservice cloud.firestore {

- [ ] Unauthorized access blocked  match /databases/{database}/documents {

- [ ] No secrets in code    

    // Helper function: Check if user is in group

---    function isGroupMember(groupId) {

      return request.auth.uid in get(/databases/$(database)/documents/groups/$(groupId)).data.memberIds;

## 📚 COMMANDS    }

    

### Backend    // Users can only read/write their own document

```bash    match /users/{userId} {

pytest                        # All tests      allow read, write: if request.auth.uid == userId;

pytest --cov=api             # With coverage    }

pytest path/to/test.py -v    # Specific test    

```    // Groups: Members-only access

    match /groups/{groupId} {

### Frontend      allow read: if request.auth.uid in resource.data.memberIds;

```bash      allow create: if request.auth.uid != null;

flutter test                        # All tests      allow update: if request.auth.uid in resource.data.memberIds;

flutter test --coverage             # With coverage      allow delete: if request.auth.uid == resource.data.creatorId;

flutter test path/to/test.dart      # Specific test      

```      // Members subcollection

      match /members/{userId} {

---        allow read: if isGroupMember(groupId);

        allow write: if isGroupMember(groupId);

**Follow TDD strictly: Red → Green → Refactor. High coverage. Clean code!**      }

      
      // Expenses subcollection
      match /expenses/{expenseId} {
        allow read: if isGroupMember(groupId);
        allow create: if isGroupMember(groupId);
        allow update: if isGroupMember(groupId) && request.auth.uid == resource.data.paidBy;
        allow delete: if isGroupMember(groupId) && request.auth.uid == resource.data.paidBy;
      }
    }
    
    // Balances: Only involved parties can read
    match /balances/{balanceId} {
      allow read: if request.auth.uid == resource.data.debtorId 
                  || request.auth.uid == resource.data.creditorId;
      allow write: false;  // Only backend can write balances
    }
  }
}
```

### 🔌 API Endpoints

**Authentication** (Firebase Auth + Google Sign-In)
```
POST   /api/auth/google/        - Verify Firebase ID token, create/update user
POST   /api/auth/refresh/       - Refresh Firebase ID token
GET    /api/auth/me/            - Get current user profile (requires Firebase ID token)
PATCH  /api/auth/me/            - Update user profile
DELETE /api/auth/logout/        - Revoke tokens (optional)
```
Note: No username/password endpoints - Google Sign-In only

**Groups**
```
GET    /api/groups/
POST   /api/groups/
GET    /api/groups/{id}/
PATCH  /api/groups/{id}/
DELETE /api/groups/{id}/
POST   /api/groups/{id}/members/
DELETE /api/groups/{id}/members/{userId}/
```

**Expenses**
```
GET    /api/expenses/
POST   /api/expenses/
GET    /api/expenses/{id}/
PATCH  /api/expenses/{id}/
DELETE /api/expenses/{id}/
```

**Balances**
```
GET    /api/balances/
GET    /api/balances/?groupId={id}
POST   /api/balances/settle/
```

**Analytics**
```
GET    /api/analytics/summary/
GET    /api/analytics/trends/
GET    /api/analytics/categories/
```

### 🚀 Backend Development (Django + Firestore)

#### Phase 5.1: Django Project Setup
- [ ] Create Django project: `django-admin startproject expense_tracker_backend`
- [ ] Create app: `python manage.py startapp api`
- [ ] Install dependencies:
  ```
  django>=5.0
  djangorestframework
  firebase-admin          # For Firebase Auth token verification + Firestore
  python-decouple
  django-cors-headers
  pytest
  pytest-django
  pytest-cov
  ```
  Note: No djangorestframework-simplejwt (using Firebase Auth instead)
- [ ] Configure `settings.py` (DRF, CORS)
- [ ] Setup Firebase Admin SDK in `config/firebase_client.py`:
  ```python
  import firebase_admin
  from firebase_admin import credentials, firestore, auth
  
  cred = credentials.Certificate(config('FIREBASE_CREDENTIALS_PATH'))
  firebase_admin.initialize_app(cred)
  db = firestore.client()
  # auth module used for verifying ID tokens
  ```
- [ ] Write test to verify Firestore connection
- [ ] Write test to verify Firebase Auth connection
- [ ] All tests pass

#### Phase 5.2: User Authentication (TDD) - Firebase Auth + Google Sign-In
- [ ] **Firebase ID Token Verification**:
  - [ ] Write failing test for `verify_firebase_token(id_token)`
  - [ ] Implement token verification using Firebase Admin SDK:
    ```python
    from firebase_admin import auth
    
    def verify_firebase_token(id_token):
        try:
            decoded_token = auth.verify_id_token(id_token)
            uid = decoded_token['uid']
            email = decoded_token.get('email')
            name = decoded_token.get('name')
            return {'uid': uid, 'email': email, 'name': name}
        except Exception as e:
            raise AuthenticationFailed('Invalid token')
    ```
  - [ ] Write failing test for expired/invalid token → raises exception
  - [ ] Test passes
- [ ] **User Creation/Update in Firestore**:
  - [ ] Write failing test for `get_or_create_user(uid, email, name)`
  - [ ] Implement user creation/update in `users/{uid}`:
    ```python
    def get_or_create_user(uid, email, name):
        user_ref = db.collection('users').document(uid)
        user_doc = user_ref.get()
        
        if not user_doc.exists:
            # First time user - create document
            user_ref.set({
                'email': email,
                'displayName': name,
                'createdAt': firestore.SERVER_TIMESTAMP,
                'updatedAt': firestore.SERVER_TIMESTAMP
            })
        else:
            # Update name/email if changed
            user_ref.update({
                'displayName': name,
                'email': email,
                'updatedAt': firestore.SERVER_TIMESTAMP
            })
        return user_ref.get().to_dict()
    ```
  - [ ] Test passes
- [ ] **Authentication Middleware**:
  - [ ] Write failing test for custom DRF authentication class
  - [ ] Implement `FirebaseAuthentication`:
    ```python
    from rest_framework.authentication import BaseAuthentication
    
    class FirebaseAuthentication(BaseAuthentication):
        def authenticate(self, request):
            auth_header = request.META.get('HTTP_AUTHORIZATION')
            if not auth_header or not auth_header.startswith('Bearer '):
                return None
            
            id_token = auth_header.split('Bearer ')[1]
            user_info = verify_firebase_token(id_token)
            # Return (user_object, None) or raise AuthenticationFailed
    ```
  - [ ] Test passes
- [ ] **API Endpoints**:
  - [ ] Write failing API test for `POST /api/auth/google/` (send Firebase ID token)
  - [ ] Implement Google Sign-In endpoint:
    ```python
    # Request: {"idToken": "firebase-id-token-from-flutter"}
    # Response: {"uid": "...", "email": "...", "displayName": "..."}
    ```
  - [ ] Write failing test for missing/invalid token → 401 Unauthorized
  - [ ] Implement error handling
  - [ ] Write failing API test for `GET /api/auth/me/` (requires Firebase ID token in header)
  - [ ] Implement protected profile endpoint
  - [ ] Write failing test for request without token → 401
  - [ ] Test passes
- [ ] All auth tests passing

Note: No password hashing, no JWT generation - Firebase handles all auth!

#### Phase 5.3: Groups Management (TDD)
- [ ] Write failing test for `GroupSerializer`
- [ ] Implement group serializer (validate name, memberIds)
- [ ] Write failing test for `create_group()` in Firestore
- [ ] Implement group creation service:
  ```python
  def create_group(name, creator_id, member_ids):
      # Validate: creator_id must be in member_ids
      # Create doc in groups/{groupId} with creatorId, memberIds
      # Create subcollection docs in groups/{groupId}/members/{userId} for each member
  ```
- [ ] Write failing test for authorization: only group members can view group
- [ ] Implement membership check decorator:
  ```python
  @require_group_membership
  def get_group(request, group_id):
      # Check if request.user.id in group.memberIds
      # Return 403 Forbidden if not a member
  ```
- [ ] Write failing test for `get_user_groups(user_id)`
- [ ] Implement query: `groups.where('memberIds', 'array_contains', user_id)`
- [ ] Write failing API test for `GET /api/groups/` (returns only user's groups)
- [ ] Implement list groups endpoint (filtered by current user)
- [ ] Write failing API test for `POST /api/groups/`
- [ ] Implement create group endpoint (auto-adds creator to memberIds)
- [ ] Write failing test for authorization: non-member cannot view group details
- [ ] Implement `GET /api/groups/{id}/` with membership check
- [ ] Write failing test for authorization: only creator can delete group
- [ ] Implement `DELETE /api/groups/{id}/` with creator-only check
- [ ] Write failing test for `add_member()` validates user exists
- [ ] Implement member addition with user validation
- [ ] Write failing API test for `POST /api/groups/{id}/members/`
- [ ] Implement add member endpoint (check requester is member)
- [ ] Write failing test for `remove_member()` prevents removing last member
- [ ] Implement member removal with validation
- [ ] All groups tests passing

#### Phase 5.4: Expenses & Splits (TDD)
- [ ] Write failing test for `ExpenseSerializer`
- [ ] Implement expense serializer with validations:
  ```python
  # Validate: amount > 0
  # Validate: sum(splits.values()) == totalAmount
  # Validate: all userIds in splits exist
  # Validate: paidBy is in splits
  ```
- [ ] Write failing test for authorization: user must be group member to create expense
- [ ] Implement membership check for expense creation
- [ ] Write failing test for `create_expense()` in Firestore
- [ ] Implement expense creation:
  ```python
  def create_expense(group_id, description, total_amount, paid_by, splits, user_id):
      # SECURITY: Verify user_id is in group.memberIds
      # SECURITY: Verify all split userIds are in group.memberIds
      # SECURITY: Verify sum(splits) == total_amount
      # Create doc in groups/{groupId}/expenses/{expenseId}
      # Trigger balance recalculation
  ```
- [ ] Write failing test for split validation: cannot split to non-members
- [ ] Implement split validation against group membership
- [ ] Write failing test for split validation: sum must equal total
- [ ] Implement sum validation
- [ ] Write failing test for `calculate_equal_split()`
- [ ] Implement equal split calculation (handles rounding)
- [ ] Write failing test for `calculate_percentage_split()`
- [ ] Implement percentage-based split
- [ ] Write failing API test for `POST /api/expenses/` (user is group member)
- [ ] Implement create expense endpoint with membership check
- [ ] Write failing test for authorization: non-member cannot create expense
- [ ] Implement 403 Forbidden for non-members
- [ ] Write failing API test for `GET /api/expenses/` (returns only user's group expenses)
- [ ] Implement list expenses endpoint (filtered by user's groups)
- [ ] Write failing test for query parameter: `?groupId={id}` filters by group
- [ ] Implement group filtering
- [ ] Write failing test for authorization: only expense creator can update
- [ ] Implement `PATCH /api/expenses/{id}/` with creator-only check
- [ ] Write failing test for authorization: only expense creator can delete
- [ ] Implement `DELETE /api/expenses/{id}/` with creator-only check (soft delete)
- [ ] Write failing test for soft delete: sets `deletedAt` timestamp
- [ ] Implement soft delete logic
- [ ] All expense tests passing

#### Phase 5.5: Balance Calculations (TDD)
- [ ] Write failing test for `calculate_group_balances(group_id)`
- [ ] Implement balance calculation algorithm:
  ```python
  def calculate_group_balances(group_id):
      # Fetch all non-deleted expenses for group
      # For each expense:
      #   - Payer is owed by each split participant (except self)
      #   - debt = split_amount (if participant != payer)
      # Aggregate debts between user pairs
      # Simplify: net_debt = total_owed - total_owing between each pair
      # Store in balances collection
      # SECURITY: Only store balances where amount > 0
  ```
- [ ] Write failing test for balance simplification (A owes B $10, B owes A $3 → A owes B $7)
- [ ] Implement debt simplification logic
- [ ] Write failing test for `get_user_balances(user_id)`
- [ ] Implement query to get all balances for a user (as debtor or creditor)
- [ ] Write failing API test for `GET /api/balances/` (returns only current user's balances)
- [ ] Implement balances endpoint (filtered by current user)
- [ ] Write failing test for authorization: user cannot see balances they're not part of
- [ ] Implement authorization check (user must be debtor or creditor)
- [ ] Write failing test for `GET /api/balances/?groupId={id}` (user must be group member)
- [ ] Implement group filtering with membership check
- [ ] Write failing test for `record_settlement(debtor_id, creditor_id, amount)`
- [ ] Implement settlement recording:
  ```python
  def record_settlement(debtor_id, creditor_id, amount, user_id):
      # SECURITY: Verify user_id == debtor_id (users can only settle their own debts)
      # SECURITY: Verify amount <= current_balance
      # Update balance (subtract amount)
      # If balance reaches 0, delete balance document
      # Create settlement record for audit trail
  ```
- [ ] Write failing test for authorization: user can only settle their own debts
- [ ] Implement authorization check
- [ ] Write failing test for validation: cannot settle more than owed
- [ ] Implement validation logic
- [ ] Write failing API test for `POST /api/balances/settle/`
- [ ] Implement settlement endpoint with authorization
- [ ] All balance tests passing

#### Phase 5.6: Analytics (TDD)
- [ ] Write failing test for `get_expense_summary(user_id, start_date, end_date)`
- [ ] Implement summary calculation:
  ```python
  def get_expense_summary(user_id, start_date, end_date):
      # SECURITY: Only include expenses from user's groups
      # Calculate: total_spent (sum where paidBy == user_id)
      # Calculate: total_share (sum of user's splits across all expenses)
      # Calculate: net_balance (total_spent - total_share)
      # Return aggregated data
  ```
- [ ] Write failing test for authorization: only returns data from user's groups
- [ ] Implement group membership filtering
- [ ] Write failing test for `get_category_breakdown(user_id, start_date, end_date)`
- [ ] Implement category aggregation (only user's groups)
- [ ] Write failing test for `get_spending_trends(user_id, period='month')`
- [ ] Implement time-series aggregation (only user's groups)
- [ ] Write failing API test for `GET /api/analytics/summary/` (current user only)
- [ ] Implement summary endpoint with user filtering
- [ ] Write failing test for authorization: cannot request another user's analytics
- [ ] Implement authorization check
- [ ] Write failing API test for `GET /api/analytics/categories/`
- [ ] Implement category breakdown endpoint
- [ ] Write failing API test for `GET /api/analytics/trends/`
- [ ] Implement trends endpoint
- [ ] All analytics tests passing

#### Phase 5.7: Deployment & Security Hardening
- [ ] **Django Security Settings**:
  ```python
  # settings.py
  DEBUG = False
  ALLOWED_HOSTS = ['your-app.herokuapp.com']
  SECURE_SSL_REDIRECT = True
  SESSION_COOKIE_SECURE = True
  CSRF_COOKIE_SECURE = True
  SECURE_BROWSER_XSS_FILTER = True
  SECURE_CONTENT_TYPE_NOSNIFF = True
  X_FRAME_OPTIONS = 'DENY'
  
  # Firebase Authentication
  REST_FRAMEWORK = {
      'DEFAULT_AUTHENTICATION_CLASSES': [
          'api.auth.FirebaseAuthentication',  # Custom Firebase auth
      ],
      'DEFAULT_PERMISSION_CLASSES': [
          'rest_framework.permissions.IsAuthenticated',
      ],
  }
  ```
- [ ] **Environment Variables** (never commit):
  ```
  SECRET_KEY=<django-secret-key>
  FIREBASE_CREDENTIALS_PATH=<path-to-serviceAccountKey.json>
  ALLOWED_HOSTS=your-app.herokuapp.com
  DEBUG=False
  ```
- [ ] **Rate Limiting** (prevent abuse):
  ```python
  # Install django-ratelimit
  @ratelimit(key='user', rate='10/m')  # 10 requests per minute per user
  def create_expense(request):
      ...
  ```
- [ ] Write test for rate limiting (11th request returns 429 Too Many Requests)
- [ ] Implement rate limiting on all write endpoints
- [ ] **CORS Configuration** (Flutter app domain only):
  ```python
  CORS_ALLOWED_ORIGINS = [
      "https://your-flutter-app.com",  # Production
      "http://localhost:8080",         # Development
  ]
  ```
- [ ] **Deploy Firestore Security Rules** (from Phase 5 Firestore section)
- [ ] **Firebase Auth Configuration**:
  - [ ] Enable Google Sign-In in Firebase Console
  - [ ] Configure OAuth consent screen
  - [ ] Add authorized domains (Heroku domain)
  - [ ] Test Google Sign-In in production
- [ ] Test security rules with Firebase emulator
- [ ] Create `Procfile`: `web: gunicorn expense_tracker_backend.wsgi`
- [ ] Create `runtime.txt`: `python-3.11.x`
- [ ] Create `requirements.txt` with all dependencies
- [ ] Configure environment variables on Heroku
- [ ] Upload Firebase service account key securely (Heroku config vars)
- [ ] Deploy to Heroku
- [ ] Run security audit: `python manage.py check --deploy`
- [ ] Test production API with Firebase ID token authentication
- [ ] Verify Firebase token expiration works (tokens auto-expire, handled by Firebase)
- [ ] Verify unauthorized requests return 401/403
- [ ] All security tests passing

### 🎨 Frontend Development (Flutter as API Consumer)

**Key Changes from Original Architecture**:
- ✅ Repositories now call Django REST API endpoints (not Firestore directly)
- ✅ BLoCs remain the same pattern but work with API-based repositories
- ✅ No more "Friends BLoC" - friends are group members from `/api/groups/{id}/members/`
- ✅ Analytics computed by backend, not client-side
- ✅ Hive used ONLY for offline caching of API responses
- ✅ **Firebase Authentication for Google Sign-In** (no custom auth system)

#### Phase 5.8: Flutter API Client & Firebase Auth Setup
- [ ] Add dependencies:
  ```yaml
  dependencies:
    dio: ^5.3.0
    firebase_core: ^2.24.0
    firebase_auth: ^4.15.0
    google_sign_in: ^6.1.5
  ```
- [ ] Initialize Firebase in Flutter:
  ```dart
  await Firebase.initializeApp();
  ```
- [ ] Write failing test for Google Sign-In flow
- [ ] Implement Google Sign-In:
  ```dart
  Future<User?> signInWithGoogle() async {
    final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
    final GoogleSignInAuthentication googleAuth = await googleUser!.authentication;
    
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    
    final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
    return userCredential.user;  // Firebase User with ID token
  }
  ```
- [ ] Write failing test for `ApiClient` initialization
- [ ] Implement `ApiClient` with Dio:
  ```dart
  class ApiClient {
    final Dio _dio;
    final FirebaseAuth _auth;
    
    Future<Response> get(String endpoint) async {
      final idToken = await _auth.currentUser?.getIdToken();
      return _dio.get(endpoint, options: Options(
        headers: {'Authorization': 'Bearer $idToken'}
      ));
    }
  }
  ```
- [ ] Write failing test for Firebase ID token injection in API headers
- [ ] Implement token interceptor (auto-refresh if expired)
- [ ] Write failing test for token auto-refresh
- [ ] Implement token refresh logic (Firebase handles this automatically)
- [ ] All API client tests passing

#### Phase 5.9: Update Data Models
- [ ] Write failing test for `User.fromJson()` from API response
- [ ] Update User model
- [ ] Write failing test for `Group.fromJson()` from API response
- [ ] Update Group model
- [ ] Write failing test for `Expense.fromJson()` from API response
- [ ] Update Expense model
- [ ] Run `dart run build_runner build`
- [ ] All model tests passing

#### Phase 5.10: Auth Feature (Flutter) - Google Sign-In Only
- [ ] Write failing test for `AuthRepository.signInWithGoogle()` calls Firebase Auth
- [ ] Implement AuthRepository:
  ```dart
  class AuthRepository {
    final FirebaseAuth _firebaseAuth;
    final ApiClient _apiClient;
    
    Future<User?> signInWithGoogle() async {
      // 1. Google Sign-In flow
      // 2. Get Firebase credential
      // 3. Sign in to Firebase
      // 4. Get ID token
      // 5. Call backend POST /api/auth/google/ to sync user
      // 6. Return user
    }
  }
  ```
- [ ] Write failing test for backend user sync after Google Sign-In
- [ ] Implement backend sync (POST /api/auth/google/ with ID token)
- [ ] Write failing test for Firebase auth state listening
- [ ] Implement auth state stream:
  ```dart
  Stream<User?> get authStateChanges => _firebaseAuth.authStateChanges();
  ```
- [ ] Write failing bloc_test for `GoogleSignInEvent → AuthSuccess`
- [ ] Implement AuthBloc
- [ ] Write failing test for `LogoutEvent` calls Firebase signOut
- [ ] Implement logout:
  ```dart
  Future<void> signOut() async {
    await _firebaseAuth.signOut();
    await GoogleSignIn().signOut();
    // Clear Hive cache
  }
  ```
- [ ] Write failing test for 401 response → auto-logout (token expired/invalid)
- [ ] Implement 401 interceptor
- [ ] Write widget test for LoginScreen (shows Google Sign-In button)
- [ ] Implement LoginScreen UI:
  ```dart
  ElevatedButton.icon(
    icon: Icon(Icons.login),
    label: Text('Sign in with Google'),
    onPressed: () => context.read<AuthBloc>().add(GoogleSignInEvent()),
  )
  ```
- [ ] Write failing test for Google Sign-In error → error message
- [ ] Implement error handling UI
- [ ] All auth tests passing

Note: No username/password fields - Google Sign-In button only!

#### Phase 5.11: Groups Feature (Flutter)
- [ ] Write failing test for `GroupsRepository.getGroups()` calls API
- [ ] Implement GroupsRepository
- [ ] Write failing test for Hive caching
- [ ] Implement offline caching:
  ```dart
  // Cache API responses in Hive
  // Return cached data if offline
  // Never cache sensitive data (only IDs and names)
  ```
- [ ] Write failing test for cache invalidation on create/update
- [ ] Implement cache refresh after mutations
- [ ] Write failing bloc_test for `LoadGroups → GroupsLoaded`
- [ ] Implement GroupsBloc
- [ ] Write failing test for `CreateGroup` event
- [ ] Implement group creation with optimistic updates
- [ ] Write failing test for unauthorized access → error state
- [ ] Implement error handling for 403 Forbidden
- [ ] Write widget test for GroupsScreen
- [ ] Implement GroupsScreen UI (shows only user's groups)
- [ ] Write widget test for group member list (shows only members, no user IDs exposed)
- [ ] Implement member list UI
- [ ] All groups tests passing

#### Phase 5.12: Expenses Feature (Flutter)
- [ ] Write failing test for `ExpensesRepository.getExpenses()` calls API
- [ ] Implement ExpensesRepository
- [ ] Write failing test for split validation before API call
- [ ] Implement client-side validation (fails fast before network call)
- [ ] Write failing bloc_test for `CreateExpense → ExpensesLoaded`
- [ ] Implement ExpensesBloc
- [ ] Write failing test for expense creation: sum(splits) must equal total
- [ ] Implement split validation in BLoC
- [ ] Write failing test for unauthorized expense edit → error
- [ ] Implement authorization error handling (only creator can edit)
- [ ] Write widget test for ExpensesScreen
- [ ] Implement ExpensesScreen UI with split form
- [ ] Write widget test for split calculator (validates sum == total)
- [ ] Implement split calculator widget
- [ ] Write failing test for displaying only user's group expenses
- [ ] Implement expense filtering
- [ ] All expenses tests passing

#### Phase 5.13: Balances & Analytics (Flutter)
- [ ] Implement BalancesRepository
- [ ] Implement BalancesBloc
- [ ] Implement BalancesScreen
- [ ] Implement AnalyticsRepository
- [ ] Implement AnalyticsBloc
- [ ] Implement AnalyticsScreen with charts
- [ ] All tests passing

#### Phase 5.14: App Integration & Security Testing
- [ ] Create HomeScreen with BottomNavigationBar (4 tabs, not 5):
    1. **Groups** (GroupsBloc - calls `/api/groups/`)
    2. **Activity** (ExpensesBloc - calls `/api/expenses/` with filters)
    3. **Analytics** (AnalyticsBloc - calls `/api/analytics/*`)
    4. **Account** (AuthBloc - calls `/api/auth/me/`)
- [ ] Note: No separate "Friends" tab - friends are group members
- [ ] Set up BlocProviders for all BLoCs
- [ ] Inject `ApiClient` instead of Firestore datasources
- [ ] Inject repositories that use `ApiClient`
- [ ] Implement app routing
- [ ] Add FloatingActionButton for expense creation (opens modal that calls `POST /api/expenses/`)
- [ ] **Security Testing**:
  - [ ] Write E2E test: Google Sign-In → Create Group → Add Expense → View Balance
  - [ ] Write E2E test: Attempt to access another user's group → 403 error
  - [ ] Write E2E test: Attempt to edit another user's expense → 403 error
  - [ ] Write E2E test: Firebase token expiration → auto-logout (or auto-refresh)
  - [ ] Write E2E test: Invalid Firebase token → redirect to login
  - [ ] Write E2E test: Sign out → clears Firebase auth + Hive cache
  - [ ] Write E2E test: Offline mode (cached data from Hive, no sensitive data)
  - [ ] Write E2E test: Clear cache on logout
- [ ] **UI Security**:
  - [ ] Verify: Only Google Sign-In button on login screen (no email/password)
  - [ ] Verify: Never display other users' email addresses (only display names)
  - [ ] Verify: No user IDs visible in UI
  - [ ] Verify: Error messages don't leak sensitive info
  - [ ] Verify: Firebase ID tokens not logged or exposed
- [ ] All integration tests passing
- [ ] All security tests passing

---

## ✅ Success Criteria

### Backend
- [ ] **Test Coverage**: 90%+ test coverage
- [ ] **Functionality**: All endpoints functional and documented
- [ ] **Security**: 
  - [ ] All endpoints require authentication (except register/login)
  - [ ] Group membership validated on every request
  - [ ] Users cannot access other users' data
  - [ ] Split calculations validated server-side
  - [ ] Rate limiting active on all write endpoints
  - [ ] No sensitive data in error messages
  - [ ] JWT tokens expire appropriately
  - [ ] Firestore Security Rules deployed and tested
- [ ] **Performance**: API responses < 500ms

### Frontend
- [ ] **Test Coverage**: 80%+ test coverage
- [ ] **Functionality**: All screens implemented and working
- [ ] **Security**:
  - [ ] Firebase Authentication properly configured (Google Sign-In only)
  - [ ] Firebase ID tokens sent in Authorization header
  - [ ] Tokens auto-refresh when expired (handled by Firebase)
  - [ ] Auto-logout on 401 Unauthorized
  - [ ] Firebase signOut() called on logout
  - [ ] No sensitive data in Hive cache
  - [ ] No user IDs or emails visible in UI (only display names)
  - [ ] Error messages don't leak sensitive info
  - [ ] Firebase tokens not logged or exposed
- [ ] **UX**: App loads < 2s, smooth navigation, Google Sign-In flow works seamlessly

### Integration
- [ ] **E2E Tests**: All user flows pass
- [ ] **Offline Mode**: Works with cached data
- [ ] **Security Tests**: Unauthorized access properly blocked
- [ ] **Deployment**: 
  - [ ] Backend on Heroku (HTTPS enforced)
  - [ ] Flutter app builds successfully (Android/iOS)
  - [ ] No secrets in source code
  - [ ] Environment variables properly configured



