import asyncio
from pathlib import Path

import mongomock
from fastapi.testclient import TestClient

from app.main import create_app, parse_model_json, run_bill_extraction


class FakeExtractor:
    async def extract(self, file_path: Path, original_name: str):
        return {
            "merchant": "Cafe Oslo",
            "date": "2026-05-30T10:00:00Z",
            "amount": 42.5,
            "currency": "INR",
            "category": "Food",
            "notes": "Lunch",
            "lineItems": [],
            "confidence": 0.95,
            "warnings": [],
        }


def make_client(tmp_path):
    mongo = mongomock.MongoClient()
    app = create_app(database=mongo.expense_tracker_test, ai_provider=FakeExtractor())
    app.state.upload_dir = tmp_path / "uploads"
    app.state.upload_dir.mkdir(parents=True, exist_ok=True)
    return TestClient(app), app


def register(client, email="user@example.com"):
    response = client.post(
        "/api/v1/auth/register",
        json={"email": email, "password": "password123", "displayName": "User"},
    )
    assert response.status_code == 201, response.text
    token = response.json()["token"]
    return {"Authorization": f"Bearer {token}"}


def test_register_login_me_and_logout(tmp_path):
    client, _ = make_client(tmp_path)
    headers = register(client)

    me = client.get("/api/v1/auth/me", headers=headers)
    assert me.status_code == 200
    assert me.json()["user"]["email"] == "user@example.com"

    login = client.post(
        "/api/v1/auth/login",
        json={"email": "user@example.com", "password": "password123"},
    )
    assert login.status_code == 200
    assert login.json()["token"]

    logout = client.post("/api/v1/auth/logout", headers=headers)
    assert logout.status_code == 200
    assert client.get("/api/v1/auth/me", headers=headers).status_code == 401


def test_expenses_persist_in_mongo(tmp_path):
    client, app = make_client(tmp_path)
    headers = register(client)

    created = client.post(
        "/api/v1/expenses",
        headers=headers,
        json={
            "amount": 99.5,
            "category": "Food",
            "description": "Dinner",
            "date": "2026-05-30T12:00:00Z",
        },
    )
    assert created.status_code == 201, created.text
    expense_id = created.json()["id"]

    same_db_app = create_app(database=app.state.db, ai_provider=FakeExtractor())
    with TestClient(same_db_app) as restarted:
        listed = restarted.get("/api/v1/expenses", headers=headers)
    assert listed.status_code == 200
    assert listed.json()["expenses"][0]["id"] == expense_id


def test_sync_freshness_tracks_personal_expense_changes_and_deletes(tmp_path):
    client, _ = make_client(tmp_path)
    headers = register(client)

    baseline = client.get(
        "/api/v1/sync/freshness?sections=activity,dashboard",
        headers=headers,
    )
    assert baseline.status_code == 200, baseline.text
    cursor = baseline.json()["serverTime"]

    unchanged = client.get(
        f"/api/v1/sync/freshness?since={cursor}&sections=activity",
        headers=headers,
    )
    assert unchanged.status_code == 200, unchanged.text
    assert unchanged.json()["sections"]["activity"]["changed"] is False

    created = client.post(
        "/api/v1/expenses",
        headers=headers,
        json={
            "amount": 99.5,
            "category": "Food",
            "description": "Dinner",
            "date": "2026-05-30T12:00:00Z",
        },
    )
    assert created.status_code == 201, created.text
    expense_id = created.json()["id"]

    changed = client.get(
        f"/api/v1/sync/freshness?since={cursor}&sections=activity,dashboard",
        headers=headers,
    )
    assert changed.status_code == 200, changed.text
    assert changed.json()["sections"]["activity"]["changed"] is True
    assert changed.json()["sections"]["dashboard"]["changed"] is True
    cursor = changed.json()["serverTime"]

    deleted = client.delete(f"/api/v1/expenses/{expense_id}", headers=headers)
    assert deleted.status_code == 204, deleted.text

    tombstone = client.get(
        f"/api/v1/sync/freshness?since={cursor}&sections=activity",
        headers=headers,
    )
    assert tombstone.status_code == 200, tombstone.text
    activity = tombstone.json()["sections"]["activity"]
    assert activity["changed"] is True
    assert activity["personalDeletedIds"] == [expense_id]


def test_activity_feed_returns_incremental_entries_and_tombstones(tmp_path):
    client, _ = make_client(tmp_path)
    headers_a = register(client, "alice@example.com")
    headers_b = register(client, "bob@example.com")

    personal = client.post(
        "/api/v1/expenses",
        headers=headers_b,
        json={
            "amount": 35,
            "category": "Coffee",
            "description": "Morning coffee",
            "date": "2026-05-30T08:00:00Z",
        },
    )
    assert personal.status_code == 201, personal.text
    personal_id = personal.json()["id"]

    group = client.post(
        "/api/v1/groups",
        headers=headers_a,
        json={"name": "Household", "groupType": "family", "members": ["bob@example.com"]},
    )
    assert group.status_code == 201, group.text
    group_id = group.json()["id"]

    group_expense = client.post(
        f"/api/v1/groups/{group_id}/expenses",
        headers=headers_a,
        json={
            "description": "Weekly groceries",
            "amount": 120,
            "category": "Groceries",
            "date": "2026-05-30T11:00:00Z",
        },
    )
    assert group_expense.status_code == 201, group_expense.text
    group_expense_id = group_expense.json()["id"]

    feed = client.get(
        "/api/v1/activity?include=personal,group&limit=10",
        headers=headers_b,
    )
    assert feed.status_code == 200, feed.text
    payload = feed.json()
    entries = payload["entries"]
    assert {entry["kind"] for entry in entries} == {"personalExpense", "groupExpense"}
    personal_entry = next(entry for entry in entries if entry["kind"] == "personalExpense")
    group_entry = next(entry for entry in entries if entry["kind"] == "groupExpense")
    assert personal_entry["expense"]["id"] == personal_id
    assert group_entry["group"]["name"] == "Household"
    assert group_entry["expense"]["id"] == group_expense_id
    cursor = payload["serverTime"]

    updated = client.put(
        f"/api/v1/expenses/{personal_id}",
        headers=headers_b,
        json={
            "amount": 42,
            "category": "Coffee",
            "description": "Morning coffee",
            "date": "2026-05-30T08:00:00Z",
        },
    )
    assert updated.status_code == 200, updated.text

    delta = client.get(f"/api/v1/activity?since={cursor}", headers=headers_b)
    assert delta.status_code == 200, delta.text
    delta_payload = delta.json()
    assert [entry["kind"] for entry in delta_payload["entries"]] == ["personalExpense"]
    assert delta_payload["entries"][0]["expense"]["amount"] == 42
    cursor = delta_payload["serverTime"]

    deleted_personal = client.delete(f"/api/v1/expenses/{personal_id}", headers=headers_b)
    assert deleted_personal.status_code == 204, deleted_personal.text
    deleted_group = client.delete(
        f"/api/v1/groups/{group_id}/expenses/{group_expense_id}",
        headers=headers_a,
    )
    assert deleted_group.status_code == 204, deleted_group.text

    tombstones = client.get(f"/api/v1/activity?since={cursor}", headers=headers_b)
    assert tombstones.status_code == 200, tombstones.text
    assert tombstones.json()["tombstones"] == {
        "personalDeletedIds": [personal_id],
        "groupDeleted": [{"groupId": group_id, "expenseId": group_expense_id}],
        "deletedGroupIds": [],
    }


def test_bill_upload_extraction_and_create_expense(tmp_path):
    client, app = make_client(tmp_path)
    headers = register(client)

    upload = client.post(
        "/api/v1/bills",
        headers=headers,
        files={"file": ("bill.jpg", b"fake-image-bytes", "image/jpeg")},
    )
    assert upload.status_code == 201, upload.text
    job_id = upload.json()["id"]

    asyncio.run(run_bill_extraction(app, job_id))

    job = client.get(f"/api/v1/bills/{job_id}", headers=headers)
    assert job.status_code == 200
    assert job.json()["status"] == "completed"
    assert job.json()["result"]["merchant"] == "Cafe Oslo"

    expense = client.post(f"/api/v1/bills/{job_id}/create-expense", headers=headers)
    assert expense.status_code == 201
    assert expense.json()["description"] == "Cafe Oslo"
    assert expense.json()["amount"] == 42.5


def test_parse_model_json_handles_wrapped_json():
    parsed = parse_model_json(
        """
        ```json
        {"merchant": "Store", "amount": 12.3}
        ```
        """
    )
    assert parsed["merchant"] == "Store"
    assert parsed["amount"] == 12.3

    parsed = parse_model_json('Result: {"merchant": "Bakery", "amount": "8.5"}')
    assert parsed["merchant"] == "Bakery"


def test_monthly_plan_returns_budget_actuals_and_remaining(tmp_path):
    client, _ = make_client(tmp_path)
    headers = register(client)

    created = client.post(
        "/api/v1/expenses",
        headers=headers,
        json={
            "amount": 200,
            "category": "Food",
            "description": "Groceries",
            "date": "2026-05-10T12:00:00Z",
        },
    )
    assert created.status_code == 201, created.text

    saved = client.put(
        "/api/v1/planning/monthly",
        headers=headers,
        json={"month": "2026-05", "currency": "INR", "budgets": {"Food": 500, "Travel": 300}},
    )
    assert saved.status_code == 200, saved.text
    payload = saved.json()
    assert payload["totalBudget"] == 800
    assert payload["totalActual"] == 200

    food = next(item for item in payload["categories"] if item["category"] == "Food")
    assert food["budget"] == 500
    assert food["actual"] == 200
    assert food["remaining"] == 300


def test_family_roles_and_expenses_feed_monthly_plan(tmp_path):
    client, _ = make_client(tmp_path)
    headers_a = register(client, "alice@example.com")
    headers_b = register(client, "bob@example.com")

    created = client.post(
        "/api/v1/groups",
        headers=headers_a,
        json={
            "name": "Our household",
            "groupType": "family",
            "members": ["bob@example.com"],
            "ownerRole": "Wife",
        },
    )
    assert created.status_code == 201, created.text
    group_id = created.json()["id"]

    members = client.get(f"/api/v1/groups/{group_id}/members", headers=headers_a)
    assert members.status_code == 200, members.text
    alice = next(item for item in members.json()["members"] if item["email"] == "alice@example.com")
    bob = next(item for item in members.json()["members"] if item["email"] == "bob@example.com")
    assert alice["role"] == "Wife"

    role = client.put(
        f"/api/v1/groups/{group_id}/members/{bob['uid']}/role",
        headers=headers_a,
        json={"role": "Husband"},
    )
    assert role.status_code == 200, role.text
    assert role.json()["role"] == "Husband"

    expense = client.post(
        f"/api/v1/groups/{group_id}/expenses",
        headers=headers_a,
        json={
            "description": "Monthly grocery run",
            "amount": 220,
            "category": "Groceries",
            "date": "2026-05-12T12:00:00Z",
        },
    )
    assert expense.status_code == 201, expense.text
    assert expense.json()["category"] == "Groceries"

    saved = client.put(
        "/api/v1/planning/monthly",
        headers=headers_a,
        json={"month": "2026-05", "currency": "INR", "budgets": {"Groceries": 500}},
    )
    assert saved.status_code == 200, saved.text
    groceries = next(
        item for item in saved.json()["categories"] if item["category"] == "Groceries"
    )
    assert groceries["budget"] == 500
    assert groceries["actual"] == 220
    assert groceries["remaining"] == 280

    bob_plan = client.get(
        "/api/v1/planning/monthly?month=2026-05",
        headers=headers_b,
    )
    assert bob_plan.status_code == 200, bob_plan.text
    bob_groceries = next(
        item for item in bob_plan.json()["categories"] if item["category"] == "Groceries"
    )
    assert bob_groceries["actual"] == 220


def test_group_create_rejects_unknown_initial_members(tmp_path):
    client, _ = make_client(tmp_path)
    headers = register(client, "alice@example.com")

    created = client.post(
        "/api/v1/groups",
        headers=headers,
        json={
            "name": "Our household",
            "groupType": "family",
            "members": ["missing-spouse@example.com"],
        },
    )
    assert created.status_code == 404, created.text
    assert created.json()["error"]["code"] == "MEMBER_NOT_FOUND"
    assert "missing-spouse@example.com" in created.json()["error"]["message"]

    groups = client.get("/api/v1/groups", headers=headers)
    assert groups.status_code == 200
    assert groups.json()["groups"] == []


def test_recurring_income_can_be_confirmed_with_actual_amount(tmp_path):
    client, _ = make_client(tmp_path)
    headers = register(client)

    created = client.post(
        "/api/v1/recurring/templates",
        headers=headers,
        json={
            "title": "Salary",
            "kind": "income",
            "amount": 31000,
            "currency": "INR",
            "category": "Salary",
            "frequency": "monthly",
            "dayOfMonth": 15,
            "startDate": "2026-05-01T00:00:00Z",
        },
    )
    assert created.status_code == 201, created.text
    assert created.json()["kind"] == "income"

    listed = client.get("/api/v1/recurring/occurrences?month=2026-05", headers=headers)
    assert listed.status_code == 200, listed.text
    occurrence = listed.json()["occurrences"][0]
    assert occurrence["expectedAmount"] == 31000
    assert occurrence["actualAmount"] is None

    confirmed = client.post(
        f"/api/v1/recurring/occurrences/{occurrence['id']}/confirm",
        headers=headers,
        json={"actualAmount": 30500, "actualDate": "2026-05-16T10:00:00Z"},
    )
    assert confirmed.status_code == 200, confirmed.text
    assert confirmed.json()["status"] == "confirmed"
    assert confirmed.json()["actualAmount"] == 30500

    expenses = client.get("/api/v1/expenses", headers=headers)
    assert expenses.status_code == 200
    assert expenses.json()["expenses"] == []


def test_recurring_payment_confirmation_creates_or_updates_expense(tmp_path):
    client, _ = make_client(tmp_path)
    headers = register(client)

    created = client.post(
        "/api/v1/recurring/templates",
        headers=headers,
        json={
            "title": "Rent",
            "kind": "expense",
            "amount": 12000,
            "category": "Rent",
            "frequency": "monthly",
            "dayOfMonth": 5,
            "startDate": "2026-05-01T00:00:00Z",
        },
    )
    assert created.status_code == 201, created.text
    occurrence = client.get(
        "/api/v1/recurring/occurrences?month=2026-05",
        headers=headers,
    ).json()["occurrences"][0]

    confirmed = client.post(
        f"/api/v1/recurring/occurrences/{occurrence['id']}/confirm",
        headers=headers,
        json={"actualAmount": 12500, "actualDate": "2026-05-05T10:00:00Z"},
    )
    assert confirmed.status_code == 200, confirmed.text
    expense_id = confirmed.json()["expenseId"]

    edited = client.post(
        f"/api/v1/recurring/occurrences/{occurrence['id']}/confirm",
        headers=headers,
        json={"actualAmount": 12400, "actualDate": "2026-05-06T10:00:00Z"},
    )
    assert edited.status_code == 200, edited.text
    assert edited.json()["expenseId"] == expense_id

    expenses = client.get("/api/v1/expenses", headers=headers).json()["expenses"]
    assert len(expenses) == 1
    assert expenses[0]["amount"] == 12400


def test_friend_settlement_is_visible_to_both_users(tmp_path):
    client, _ = make_client(tmp_path)
    headers_a = register(client, "alice@example.com")
    headers_b = register(client, "bob@example.com")

    added = client.post(
        "/api/v1/friends/add",
        headers=headers_a,
        json={"emailOrPhone": "bob@example.com"},
    )
    assert added.status_code == 200, added.text

    settlement = client.post(
        "/api/v1/friends/settlements",
        headers=headers_a,
        json={"friendUid": added.json()["uid"], "direction": "paid", "amount": 120},
    )
    assert settlement.status_code == 201, settlement.text

    balances_a = client.get("/api/v1/friends/balances", headers=headers_a)
    balances_b = client.get("/api/v1/friends/balances", headers=headers_b)
    assert balances_a.status_code == 200
    assert balances_b.status_code == 200
    bob_uid = added.json()["uid"]
    alice_uid = client.get("/api/v1/auth/me", headers=headers_a).json()["user"]["uid"]
    assert balances_a.json()["balances"][bob_uid] == 120
    assert balances_b.json()["balances"][alice_uid] == -120

    dashboard = client.get("/api/v1/dashboard/snapshot", headers=headers_a)
    assert dashboard.status_code == 200
    assert dashboard.json()["friendItems"][0]["title"] == "User"
    assert dashboard.json()["friendItems"][0]["subtitle"] == "owes you"


def test_group_expense_normalizes_member_aliases_and_custom_split(tmp_path):
    client, _ = make_client(tmp_path)
    headers_a = register(client, "alice@example.com")
    headers_b = register(client, "bob@example.com")
    alice_uid = client.get("/api/v1/auth/me", headers=headers_a).json()["user"]["uid"]
    bob_uid = client.get("/api/v1/auth/me", headers=headers_b).json()["user"]["uid"]

    group = client.post(
        "/api/v1/groups",
        headers=headers_a,
        json={"name": "Family", "groupType": "family", "members": ["bob@example.com"]},
    )
    assert group.status_code == 201, group.text
    group_id = group.json()["id"]

    created = client.post(
        f"/api/v1/groups/{group_id}/expenses",
        headers=headers_a,
        json={
            "description": "Pharmacy",
            "paidBy": "bob@example.com",
            "splitMode": "custom",
            "splitWith": ["alice@example.com"],
            "amount": 90,
            "date": "2026-05-20T10:00:00Z",
        },
    )
    assert created.status_code == 201, created.text
    assert created.json()["paidBy"] == bob_uid
    assert created.json()["splitWith"] == [alice_uid]

    groups = client.get("/api/v1/groups", headers=headers_a)
    balances = groups.json()["groups"][0]["displayData"]["memberBalances"]
    assert balances[alice_uid]["net"] == -90
    assert balances[bob_uid]["net"] == 90


def test_sync_freshness_tracks_group_expense_tombstones(tmp_path):
    client, _ = make_client(tmp_path)
    headers_a = register(client, "alice@example.com")
    headers_b = register(client, "bob@example.com")

    group = client.post(
        "/api/v1/groups",
        headers=headers_a,
        json={"name": "Family", "groupType": "family", "members": ["bob@example.com"]},
    )
    assert group.status_code == 201, group.text
    group_id = group.json()["id"]

    expense = client.post(
        f"/api/v1/groups/{group_id}/expenses",
        headers=headers_a,
        json={
            "description": "Pharmacy",
            "amount": 90,
            "date": "2026-05-20T10:00:00Z",
        },
    )
    assert expense.status_code == 201, expense.text
    expense_id = expense.json()["id"]

    baseline = client.get(
        "/api/v1/sync/freshness?sections=activity,groups",
        headers=headers_b,
    )
    assert baseline.status_code == 200, baseline.text
    cursor = baseline.json()["serverTime"]

    deleted = client.delete(
        f"/api/v1/groups/{group_id}/expenses/{expense_id}",
        headers=headers_a,
    )
    assert deleted.status_code == 204, deleted.text

    freshness = client.get(
        f"/api/v1/sync/freshness?since={cursor}&sections=activity,groups",
        headers=headers_b,
    )
    assert freshness.status_code == 200, freshness.text
    sections = freshness.json()["sections"]
    assert sections["activity"]["changed"] is True
    assert sections["activity"]["groupDeleted"] == [
        {"groupId": group_id, "expenseId": expense_id}
    ]
    assert sections["groups"]["changed"] is True


def test_activity_feed_reports_deleted_group_tombstones(tmp_path):
    client, _ = make_client(tmp_path)
    headers_a = register(client, "alice@example.com")
    headers_b = register(client, "bob@example.com")

    group = client.post(
        "/api/v1/groups",
        headers=headers_a,
        json={"name": "Family", "groupType": "family", "members": ["bob@example.com"]},
    )
    assert group.status_code == 201, group.text
    group_id = group.json()["id"]

    baseline = client.get("/api/v1/activity?limit=1", headers=headers_b)
    assert baseline.status_code == 200, baseline.text
    cursor = baseline.json()["serverTime"]

    left = client.post(f"/api/v1/groups/{group_id}/leave", headers=headers_b)
    assert left.status_code == 200, left.text

    feed = client.get(f"/api/v1/activity?since={cursor}", headers=headers_b)
    assert feed.status_code == 200, feed.text
    assert feed.json()["tombstones"]["deletedGroupIds"] == [group_id]


def test_group_expense_saves_currency_snapshots_for_group_currencies(tmp_path):
    client, app = make_client(tmp_path)
    headers_a = register(client, "alice@example.com")
    register(client, "bob@example.com")
    alice_uid = client.get("/api/v1/auth/me", headers=headers_a).json()["user"]["uid"]

    async def fake_rates(base_currency, quote_currencies):
        assert base_currency == "USD"
        assert quote_currencies == ["INR", "NOK"]
        return {
            "provider": "fake-fx",
            "rateAsOf": "2026-06-07",
            "rates": {"INR": 83.5, "NOK": 10.25},
        }

    app.state.fx_rate_fetcher = fake_rates
    group = client.post(
        "/api/v1/groups",
        headers=headers_a,
        json={"name": "Family", "groupType": "family", "members": ["bob@example.com"]},
    )
    assert group.status_code == 201, group.text
    group_id = group.json()["id"]

    created = client.post(
        f"/api/v1/groups/{group_id}/expenses",
        headers=headers_a,
        json={
            "description": "Imported groceries",
            "amount": 10,
            "currency": "USD",
            "targetCurrencies": ["NOK"],
            "category": "Groceries",
            "date": "2026-05-20T10:00:00Z",
        },
    )
    assert created.status_code == 201, created.text
    payload = created.json()
    assert payload["currency"] == "USD"
    assert payload["convertedAmounts"] == {"INR": 835.0, "NOK": 102.5, "USD": 10.0}
    assert payload["convertedAmountDetails"]["INR"]["provider"] == "fake-fx"
    assert payload["convertedAmountDetails"]["NOK"]["provider"] == "fake-fx"
    assert payload["exchangeRates"]["INR"] == 83.5

    groups = client.get("/api/v1/groups", headers=headers_a)
    display = groups.json()["groups"][0]["displayData"]
    assert groups.json()["groups"][0]["currencyCodes"] == ["INR", "USD", "NOK"]
    assert display["totalSpendByCurrency"]["INR"] == 835
    assert display["totalSpendByCurrency"]["NOK"] == 102.5
    assert display["totalSpendByCurrency"]["USD"] == 10
    assert display["memberBalancesByCurrency"]["INR"][alice_uid]["net"] == 417.5

    saved = client.put(
        "/api/v1/planning/monthly",
        headers=headers_a,
        json={"month": "2026-05", "currency": "INR", "budgets": {"Groceries": 1000}},
    )
    assert saved.status_code == 200, saved.text
    groceries = next(item for item in saved.json()["categories"] if item["category"] == "Groceries")
    assert groceries["actual"] == 835
    assert groceries["remaining"] == 165


def test_group_attachment_upload_accepts_multipart_file(tmp_path):
    client, _ = make_client(tmp_path)
    headers = register(client)

    group = client.post("/api/v1/groups", headers=headers, json={"name": "Trip"})
    assert group.status_code == 201, group.text
    group_id = group.json()["id"]

    expense = client.post(
        f"/api/v1/groups/{group_id}/expenses",
        headers=headers,
        json={
            "description": "Taxi",
            "amount": 35,
            "date": "2026-05-20T10:00:00Z",
        },
    )
    assert expense.status_code == 201, expense.text

    upload = client.post(
        f"/api/v1/groups/{group_id}/attachments",
        headers=headers,
        data={"expenseId": expense.json()["id"]},
        files={"file": ("receipt.jpg", b"receipt-bytes", "image/jpeg")},
    )
    assert upload.status_code == 201, upload.text
    assert upload.json()["url"].endswith("receipt.jpg")


def test_dashboard_includes_split_group_balance_items(tmp_path):
    client, _ = make_client(tmp_path)
    headers_a = register(client, "alice@example.com")
    register(client, "bob@example.com")

    group = client.post(
        "/api/v1/groups",
        headers=headers_a,
        json={"name": "Weekend Trip", "groupType": "split", "members": ["bob@example.com"]},
    )
    assert group.status_code == 201, group.text
    group_id = group.json()["id"]

    created = client.post(
        f"/api/v1/groups/{group_id}/expenses",
        headers=headers_a,
        json={
            "description": "Dinner",
            "amount": 100,
            "date": "2026-05-20T10:00:00Z",
        },
    )
    assert created.status_code == 201, created.text

    dashboard = client.get("/api/v1/dashboard/snapshot", headers=headers_a)
    assert dashboard.status_code == 200, dashboard.text
    assert dashboard.json()["groupItems"][0]["title"] == "Weekend Trip"
    assert dashboard.json()["groupItems"][0]["subtitle"] == "you are owed"
