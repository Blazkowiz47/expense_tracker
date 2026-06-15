import asyncio
import calendar
from datetime import datetime, timedelta
from pathlib import Path

import mongomock
from fastapi.testclient import TestClient

from app.main import create_app, current_month, ensure_indexes, iso, now, parse_model_json, run_bill_extraction


class FakeExtractor:
    async def extract(self, file_path: Path, original_name: str):
        return {
            "merchant": "Cafe Oslo",
            "date": "2026-05-30T10:00:00Z",
            "amount": 42.5,
            "currency": "INR",
            "category": "Food",
            "notes": "Lunch",
            "lineItems": [
                {
                    "originalText": "TINE Lettmelk 1L",
                    "detectedLanguage": "nb",
                    "itemName": "TINE Lettmelk 1L",
                    "normalizedName": "melk",
                    "brand": "TINE",
                    "quantity": 1,
                    "unit": "l",
                    "lineTotal": 22.5,
                    "confidence": 0.9,
                },
                {
                    "originalText": "Brod Grovt 750g",
                    "detectedLanguage": "nb",
                    "itemName": "Brod Grovt 750g",
                    "normalizedName": "bread",
                    "quantity": 750,
                    "unit": "g",
                    "lineTotal": 20,
                    "confidence": 0.8,
                },
            ],
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


def firebase_claims(email="google@example.com", firebase_uid="firebase-user-1"):
    return {
        "user_id": firebase_uid,
        "sub": firebase_uid,
        "email": email,
        "email_verified": True,
        "name": "Google User",
        "picture": "https://example.com/avatar.png",
    }


def add_months(month: str, delta: int) -> str:
    year, month_number = [int(part) for part in month.split("-")]
    zero_based = (year * 12 + (month_number - 1)) + delta
    new_year, new_month_zero = divmod(zero_based, 12)
    return f"{new_year:04d}-{new_month_zero + 1:02d}"


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


def test_firebase_auth_creates_local_session(tmp_path):
    client, app = make_client(tmp_path)
    app.state.firebase_token_verifier = lambda token: firebase_claims()

    response = client.post("/api/v1/auth/firebase", json={"idToken": "firebase-token"})

    assert response.status_code == 200, response.text
    payload = response.json()
    assert payload["token"]
    assert payload["user"]["email"] == "google@example.com"
    assert payload["user"]["displayName"] == "Google User"
    assert payload["user"]["photoUrl"] == "https://example.com/avatar.png"
    stored = app.state.db.users.find_one({"emailNormalized": "google@example.com"})
    assert stored["firebaseUid"] == "firebase-user-1"
    assert stored["authProviders"] == ["google"]

    me = client.get(
        "/api/v1/auth/me",
        headers={"Authorization": f"Bearer {payload['token']}"},
    )
    assert me.status_code == 200
    assert me.json()["user"]["email"] == "google@example.com"


def test_firebase_auth_links_existing_email_user(tmp_path):
    client, app = make_client(tmp_path)
    headers = register(client, "user@example.com")
    original_user = client.get("/api/v1/auth/me", headers=headers).json()["user"]
    app.state.firebase_token_verifier = lambda token: firebase_claims(
        email="user@example.com",
        firebase_uid="firebase-existing-user",
    )

    response = client.post("/api/v1/auth/firebase", json={"idToken": "firebase-token"})

    assert response.status_code == 200, response.text
    assert response.json()["user"]["uid"] == original_user["uid"]
    assert app.state.db.users.count_documents({"emailNormalized": "user@example.com"}) == 1
    stored = app.state.db.users.find_one({"uid": original_user["uid"]})
    assert stored["firebaseUid"] == "firebase-existing-user"
    assert "google" in stored["authProviders"]


def test_firebase_auth_requires_project_config_without_test_verifier(tmp_path, monkeypatch):
    monkeypatch.delenv("FIREBASE_PROJECT_ID", raising=False)
    client, _ = make_client(tmp_path)

    response = client.post("/api/v1/auth/firebase", json={"idToken": "firebase-token"})

    assert response.status_code == 503
    assert response.json()["error"]["code"] == "AUTH_NOT_CONFIGURED"


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


def test_personal_summaries_keep_expense_currencies_separate(tmp_path):
    client, _ = make_client(tmp_path)
    headers = register(client)

    for amount, currency, description in [
        (20, "USD", "Airport snacks"),
        (30, "NOK", "Train ticket"),
    ]:
        created = client.post(
            "/api/v1/expenses",
            headers=headers,
            json={
                "amount": amount,
                "currency": currency,
                "category": "Travel",
                "description": description,
                "date": "2026-05-30T12:00:00Z",
            },
        )
        assert created.status_code == 201, created.text

    analytics = client.get("/api/v1/analytics", headers=headers)
    assert analytics.status_code == 200, analytics.text
    payload = analytics.json()
    assert payload["totalAmountByCurrency"] == {"NOK": 30.0, "USD": 20.0}
    assert payload["byCategoryByCurrency"]["Travel"] == {"NOK": 30.0, "USD": 20.0}
    assert payload["byMonthByCurrency"]["2026-05"] == {"NOK": 30.0, "USD": 20.0}

    dashboard = client.get("/api/v1/dashboard/snapshot", headers=headers)
    assert dashboard.status_code == 200, dashboard.text
    amount_labels = {item["amountText"] for item in dashboard.json()["activityItems"]}
    assert "You spent USD 20.00" in amount_labels
    assert "You spent NOK 30.00" in amount_labels

    exported = client.get("/api/v1/expenses-export.csv", headers=headers)
    assert exported.status_code == 200, exported.text
    assert "amount,currency" in exported.text
    assert "20.00,USD" in exported.text
    assert "30.00,NOK" in exported.text


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


def test_sync_freshness_tracks_monthly_plan_changes(tmp_path):
    client, _ = make_client(tmp_path)
    headers_a = register(client, "alice@example.com")
    headers_b = register(client, "bob@example.com")

    group = client.post(
        "/api/v1/groups",
        headers=headers_a,
        json={
            "name": "Home",
            "groupType": "family",
            "members": ["bob@example.com"],
        },
    )
    assert group.status_code == 201, group.text
    group_id = group.json()["id"]

    baseline = client.get(
        "/api/v1/sync/freshness?sections=dashboard,plans,activity",
        headers=headers_b,
    )
    assert baseline.status_code == 200, baseline.text
    cursor = baseline.json()["serverTime"]

    unchanged = client.get(
        f"/api/v1/sync/freshness?since={cursor}&sections=plans",
        headers=headers_b,
    )
    assert unchanged.status_code == 200, unchanged.text
    assert unchanged.json()["sections"]["plans"]["changed"] is False

    saved = client.put(
        "/api/v1/planning/monthly",
        headers=headers_a,
        json={
            "month": "2026-05",
            "groupId": group_id,
            "currency": "INR",
            "budgets": {"Groceries": 500},
        },
    )
    assert saved.status_code == 200, saved.text

    changed = client.get(
        f"/api/v1/sync/freshness?since={cursor}&sections=dashboard,plans,activity",
        headers=headers_b,
    )
    assert changed.status_code == 200, changed.text
    sections = changed.json()["sections"]
    assert sections["plans"]["changed"] is True
    assert sections["dashboard"]["changed"] is True
    assert sections["activity"]["changed"] is False


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


def test_activity_feed_includes_settlements_and_recurring_confirmations(tmp_path):
    client, _ = make_client(tmp_path)
    headers_a = register(client, "alice@example.com")
    headers_b = register(client, "bob@example.com")
    alice_uid = client.get("/api/v1/auth/me", headers=headers_a).json()["user"]["uid"]
    bob_uid = client.get("/api/v1/auth/me", headers=headers_b).json()["user"]["uid"]

    friend = client.post(
        "/api/v1/friends/add",
        headers=headers_a,
        json={"emailOrPhone": "bob@example.com"},
    )
    assert friend.status_code == 200, friend.text
    friend_settlement = client.post(
        "/api/v1/friends/settlements",
        headers=headers_a,
        json={
            "friendUid": bob_uid,
            "direction": "paid",
            "amount": 25,
            "currency": "USD",
        },
    )
    assert friend_settlement.status_code == 201, friend_settlement.text

    group = client.post(
        "/api/v1/groups",
        headers=headers_a,
        json={"name": "Household", "groupType": "family", "members": ["bob@example.com"]},
    )
    assert group.status_code == 201, group.text
    group_id = group.json()["id"]
    group_settlement = client.post(
        f"/api/v1/groups/{group_id}/settlements",
        headers=headers_b,
        json={
            "memberUid": alice_uid,
            "direction": "paid",
            "amount": 50,
            "currency": "INR",
        },
    )
    assert group_settlement.status_code == 201, group_settlement.text

    template = client.post(
        "/api/v1/recurring/templates",
        headers=headers_a,
        json={
            "title": "Salary",
            "kind": "income",
            "amount": 30000,
            "currency": "INR",
            "category": "Salary",
            "frequency": "monthly",
            "dayOfMonth": 15,
            "startDate": "2026-05-01T00:00:00Z",
        },
    )
    assert template.status_code == 201, template.text
    occurrence = client.get(
        "/api/v1/recurring/occurrences?month=2026-05",
        headers=headers_a,
    ).json()["occurrences"][0]
    confirmed = client.post(
        f"/api/v1/recurring/occurrences/{occurrence['id']}/confirm",
        headers=headers_a,
        json={"actualAmount": 30500, "actualDate": "2026-05-16T10:00:00Z"},
    )
    assert confirmed.status_code == 200, confirmed.text

    feed = client.get(
        "/api/v1/activity?include=friend_settlements,group_settlements,recurring&limit=10",
        headers=headers_a,
    )
    assert feed.status_code == 200, feed.text
    entries = feed.json()["entries"]
    assert {entry["kind"] for entry in entries} == {
        "friendSettlement",
        "groupSettlement",
        "recurringConfirmation",
    }

    friend_entry = next(entry for entry in entries if entry["kind"] == "friendSettlement")
    assert friend_entry["viewerUid"] == alice_uid
    assert friend_entry["payer"]["uid"] == alice_uid
    assert friend_entry["receiver"]["uid"] == bob_uid
    assert friend_entry["settlement"]["currency"] == "USD"

    group_entry = next(entry for entry in entries if entry["kind"] == "groupSettlement")
    assert group_entry["group"]["name"] == "Household"
    assert group_entry["payer"]["uid"] == bob_uid
    assert group_entry["receiver"]["uid"] == alice_uid
    assert group_entry["settlement"]["amount"] == 50

    recurring_entry = next(entry for entry in entries if entry["kind"] == "recurringConfirmation")
    assert recurring_entry["occurrence"]["id"] == occurrence["id"]
    assert recurring_entry["occurrence"]["status"] == "confirmed"
    assert recurring_entry["occurrence"]["actualAmount"] == 30500


def test_activity_feed_paginates_older_events(tmp_path):
    client, app = make_client(tmp_path)
    headers_a = register(client, "alice@example.com")
    headers_b = register(client, "bob@example.com")
    bob_uid = client.get("/api/v1/auth/me", headers=headers_b).json()["user"]["uid"]

    friend = client.post(
        "/api/v1/friends/add",
        headers=headers_a,
        json={"emailOrPhone": "bob@example.com"},
    )
    assert friend.status_code == 200, friend.text

    created_ids = []
    for amount in [10, 20, 30]:
        settlement = client.post(
            "/api/v1/friends/settlements",
            headers=headers_a,
            json={
                "friendUid": bob_uid,
                "direction": "paid",
                "amount": amount,
                "currency": "USD",
            },
        )
        assert settlement.status_code == 201, settlement.text
        created_ids.append(settlement.json()["id"])

    for settlement_id, created_at in zip(
        created_ids,
        [
            datetime(2026, 6, 7, 10, 0),
            datetime(2026, 6, 7, 11, 0),
            datetime(2026, 6, 7, 12, 0),
        ],
        strict=True,
    ):
        app.state.db.friend_settlements.update_one(
            {"id": settlement_id},
            {"$set": {"createdAt": created_at}},
        )

    first_page = client.get(
        "/api/v1/activity?include=friend_settlements&limit=2",
        headers=headers_a,
    )
    assert first_page.status_code == 200, first_page.text
    first_payload = first_page.json()
    assert first_payload["hasMore"] is True
    assert first_payload["nextCursor"] is not None
    assert [entry["settlement"]["amount"] for entry in first_payload["entries"]] == [30, 20]

    second_page = client.get(
        f"/api/v1/activity?include=friend_settlements&limit=2&before={first_payload['nextCursor']}",
        headers=headers_a,
    )
    assert second_page.status_code == 200, second_page.text
    second_payload = second_page.json()
    assert second_payload["hasMore"] is False
    assert second_payload["nextCursor"] is None
    assert [entry["settlement"]["amount"] for entry in second_payload["entries"]] == [10]


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
    items = client.get("/api/v1/receipt-items?q=milk", headers=headers)
    assert items.status_code == 200, items.text
    assert items.json()["items"][0]["normalizedName"] == "milk"
    assert items.json()["items"][0]["unitPriceNormalized"] == 22.5

    comparison = client.get("/api/v1/receipt-items/compare?q=milk", headers=headers)
    assert comparison.status_code == 200, comparison.text
    summary = comparison.json()["summaryByCurrency"][0]
    assert summary["currency"] == "INR"
    assert summary["unit"] == "l"
    assert summary["bestMerchant"] == "Cafe Oslo"


def test_receipt_items_can_be_saved_with_personal_expense(tmp_path):
    client, _ = make_client(tmp_path)
    headers = register(client)

    created = client.post(
        "/api/v1/expenses",
        headers=headers,
        json={
            "amount": 39,
            "currency": "NOK",
            "category": "Groceries",
            "description": "Kiwi",
            "date": "2026-06-15T12:00:00Z",
            "receiptItems": [
                {
                    "originalText": "Banan 1kg",
                    "itemName": "Banan",
                    "normalizedName": "banan",
                    "quantity": 1,
                    "unit": "kg",
                    "lineTotal": 19,
                },
                {
                    "originalText": "Melk 1L",
                    "itemName": "Melk",
                    "normalizedName": "melk",
                    "quantity": 1,
                    "unit": "l",
                    "lineTotal": 20,
                },
            ],
        },
    )
    assert created.status_code == 201, created.text

    comparison = client.get("/api/v1/receipt-items/compare?q=banana&currency=NOK", headers=headers)
    assert comparison.status_code == 200, comparison.text
    payload = comparison.json()
    assert payload["normalizedName"] == "banana"
    assert payload["items"][0]["merchant"] == "Kiwi"
    assert payload["items"][0]["sourceType"] == "personal"
    assert payload["summaryByCurrency"][0]["bestUnitPrice"] == 19


def test_group_receipt_items_are_visible_to_group_members(tmp_path):
    client, _ = make_client(tmp_path)
    headers_a = register(client, "alice@example.com")
    headers_b = register(client, "bob@example.com")

    group = client.post(
        "/api/v1/groups",
        headers=headers_a,
        json={"name": "Household", "groupType": "family", "members": ["bob@example.com"]},
    )
    assert group.status_code == 201, group.text
    group_id = group.json()["id"]

    expense = client.post(
        f"/api/v1/groups/{group_id}/expenses",
        headers=headers_a,
        json={
            "description": "Rema 1000",
            "amount": 30,
            "currency": "NOK",
            "category": "Groceries",
            "date": "2026-06-15T12:00:00Z",
            "receiptItems": [
                {
                    "originalText": "Kylling 500g",
                    "itemName": "Kylling",
                    "normalizedName": "kylling",
                    "quantity": 500,
                    "unit": "g",
                    "lineTotal": 30,
                }
            ],
        },
    )
    assert expense.status_code == 201, expense.text

    visible = client.get("/api/v1/receipt-items/compare?q=chicken", headers=headers_b)
    assert visible.status_code == 200, visible.text
    assert visible.json()["items"][0]["groupName"] == "Household"
    assert visible.json()["items"][0]["normalizedName"] == "chicken"


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

    foreign = client.post(
        "/api/v1/expenses",
        headers=headers,
        json={
            "amount": 30,
            "currency": "USD",
            "category": "Food",
            "description": "Imported snacks",
            "date": "2026-05-11T12:00:00Z",
        },
    )
    assert foreign.status_code == 201, foreign.text

    saved = client.put(
        "/api/v1/planning/monthly",
        headers=headers,
        json={"month": "2026-05", "currency": "INR", "budgets": {"Food": 500, "Travel": 300}},
    )
    assert saved.status_code == 200, saved.text
    payload = saved.json()
    assert payload["totalBudget"] == 800
    assert payload["totalActual"] == 200
    assert payload["excludedExpenseCount"] == 1
    assert payload["skippedActualExpenseCount"] == 1
    assert payload["excludedActualsByCurrency"] == {"USD": 30}
    assert payload["actualsMetadata"]["uncountedExpenseCount"] == 1
    assert payload["actualsMetadata"]["uncountedSpendByCurrency"] == {"USD": 30}
    assert payload["actualsMetadata"]["uncountedSpendByCategoryByCurrency"] == {
        "Food": {"USD": 30}
    }

    food = next(item for item in payload["categories"] if item["category"] == "Food")
    assert food["budget"] == 500
    assert food["actual"] == 200
    assert food["remaining"] == 300
    assert food["excludedExpenseCount"] == 1
    assert food["skippedActualExpenseCount"] == 1
    assert food["excludedActualsByCurrency"] == {"USD": 30}


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


def test_household_scoped_monthly_plan_isolates_group_actuals(tmp_path):
    client, _ = make_client(tmp_path)
    headers_a = register(client, "alice@example.com")
    headers_b = register(client, "bob@example.com")
    headers_c = register(client, "cara@example.com")

    primary = client.post(
        "/api/v1/groups",
        headers=headers_a,
        json={
            "name": "Home",
            "groupType": "family",
            "members": ["bob@example.com"],
        },
    )
    assert primary.status_code == 201, primary.text
    primary_id = primary.json()["id"]

    secondary = client.post(
        "/api/v1/groups",
        headers=headers_a,
        json={"name": "Parents", "groupType": "family"},
    )
    assert secondary.status_code == 201, secondary.text
    secondary_id = secondary.json()["id"]

    for group_id, amount in [(primary_id, 220), (secondary_id, 90)]:
        created = client.post(
            f"/api/v1/groups/{group_id}/expenses",
            headers=headers_a,
            json={
                "description": "Groceries",
                "amount": amount,
                "category": "Groceries",
                "date": "2026-05-12T12:00:00Z",
            },
        )
        assert created.status_code == 201, created.text

    saved = client.put(
        "/api/v1/planning/monthly",
        headers=headers_a,
        json={
            "month": "2026-05",
            "groupId": primary_id,
            "currency": "INR",
            "budgets": {"Groceries": 500},
        },
    )
    assert saved.status_code == 200, saved.text
    scoped_payload = saved.json()
    assert scoped_payload["groupId"] == primary_id
    scoped_groceries = next(
        item for item in scoped_payload["categories"] if item["category"] == "Groceries"
    )
    assert scoped_groceries["actual"] == 220
    assert scoped_groceries["remaining"] == 280

    bob_plan = client.get(
        f"/api/v1/planning/monthly?month=2026-05&groupId={primary_id}",
        headers=headers_b,
    )
    assert bob_plan.status_code == 200, bob_plan.text
    bob_groceries = next(
        item for item in bob_plan.json()["categories"] if item["category"] == "Groceries"
    )
    assert bob_groceries["budget"] == 500
    assert bob_groceries["actual"] == 220

    outsider_plan = client.get(
        f"/api/v1/planning/monthly?month=2026-05&groupId={primary_id}",
        headers=headers_c,
    )
    assert outsider_plan.status_code == 403, outsider_plan.text

    global_plan = client.get("/api/v1/planning/monthly?month=2026-05", headers=headers_a)
    assert global_plan.status_code == 200, global_plan.text
    global_groceries = next(
        item for item in global_plan.json()["categories"] if item["category"] == "Groceries"
    )
    assert global_groceries["actual"] == 310


def test_group_create_rejects_uninvitable_initial_members(tmp_path):
    client, _ = make_client(tmp_path)
    headers = register(client, "alice@example.com")

    created = client.post(
        "/api/v1/groups",
        headers=headers,
        json={
            "name": "Our household",
            "groupType": "family",
            "members": ["missing-phone-number"],
        },
    )
    assert created.status_code == 404, created.text
    assert created.json()["error"]["code"] == "MEMBER_NOT_FOUND"
    assert "missing-phone-number" in created.json()["error"]["message"]

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


def test_loan_emi_logging_creates_or_updates_expense(tmp_path):
    client, _ = make_client(tmp_path)
    headers = register(client)

    baseline = client.get("/api/v1/sync/freshness?sections=loans", headers=headers)
    assert baseline.status_code == 200, baseline.text
    cursor = baseline.json()["serverTime"]

    created = client.post(
        "/api/v1/loans",
        headers=headers,
        json={
            "name": "Home loan",
            "lender": "HDFC",
            "loanType": "Home",
            "principalAmount": 100000,
            "emiAmount": 5000,
            "currency": "INR",
            "totalEmis": 20,
            "dueDay": 5,
            "startDate": "2026-01-05T00:00:00Z",
        },
    )
    assert created.status_code == 201, created.text
    loan = created.json()
    loan_id = loan["id"]
    assert loan["paidEmiCount"] == 0
    assert loan["remainingEmis"] == 20
    assert loan["nextDueDate"] == "2026-01-05T00:00:00Z"

    changed = client.get(
        f"/api/v1/sync/freshness?since={cursor}&sections=loans",
        headers=headers,
    )
    assert changed.status_code == 200, changed.text
    assert changed.json()["sections"]["loans"]["changed"] is True

    logged = client.post(
        f"/api/v1/loans/{loan_id}/payments",
        headers=headers,
        json={"amount": 5000, "date": "2026-06-05T10:00:00Z"},
    )
    assert logged.status_code == 201, logged.text
    payload = logged.json()
    assert payload["payment"]["paymentType"] == "emi"
    assert payload["payment"]["period"] == "2026-06"
    assert payload["loan"]["paidEmiCount"] == 1
    assert payload["loan"]["remainingEmis"] == 19
    assert payload["loan"]["totalPaidAmount"] == 5000
    assert payload["expense"]["category"] == "Loans / EMI"
    assert payload["expense"]["description"] == "Loan EMI: Home loan"
    assert payload["expense"]["sourceType"] == "loan_payment"
    assert payload["expense"]["sourceLoanId"] == loan_id
    assert payload["expense"]["sourceLoanPaymentId"] == payload["payment"]["id"]
    expense_id = payload["expense"]["id"]

    updated = client.post(
        f"/api/v1/loans/{loan_id}/payments",
        headers=headers,
        json={"amount": 5500, "date": "2026-06-20T10:00:00Z"},
    )
    assert updated.status_code == 201, updated.text
    updated_payload = updated.json()
    assert updated_payload["payment"]["id"] == payload["payment"]["id"]
    assert updated_payload["expense"]["id"] == expense_id
    assert updated_payload["expense"]["amount"] == 5500
    assert updated_payload["loan"]["paidEmiCount"] == 1
    assert updated_payload["loan"]["totalPaidAmount"] == 5500

    expenses = client.get("/api/v1/expenses?category=Loans%20/%20EMI", headers=headers)
    assert expenses.status_code == 200, expenses.text
    loan_expenses = expenses.json()["expenses"]
    assert len(loan_expenses) == 1
    assert loan_expenses[0]["id"] == expense_id
    assert loan_expenses[0]["amount"] == 5500

    direct_edit = client.put(
        f"/api/v1/expenses/{expense_id}",
        headers=headers,
        json={
            "amount": 1,
            "currency": "INR",
            "category": "Other",
            "description": "manual edit",
            "date": "2026-06-20T10:00:00Z",
        },
    )
    assert direct_edit.status_code == 409, direct_edit.text
    assert direct_edit.json()["error"]["code"] == "LINKED_RECORD"

    direct_delete = client.delete(f"/api/v1/expenses/{expense_id}", headers=headers)
    assert direct_delete.status_code == 409, direct_delete.text
    assert direct_delete.json()["error"]["code"] == "LINKED_RECORD"

    edited_loan = client.put(
        f"/api/v1/loans/{loan_id}",
        headers=headers,
        json={"name": "Home loan revised"},
    )
    assert edited_loan.status_code == 200, edited_loan.text
    assert edited_loan.json()["lastPaymentAt"] == updated_payload["payment"]["date"]


def test_existing_loan_snapshot_starts_from_current_balance(tmp_path):
    client, _ = make_client(tmp_path)
    headers = register(client)

    created = client.post(
        "/api/v1/loans",
        headers=headers,
        json={
            "name": "Car loan",
            "lender": "Santander",
            "loanType": "Car",
            "currentPrincipalAmount": 146087.67,
            "originalPrincipalAmount": 150534,
            "emiAmount": 3733,
            "currency": "NOK",
            "interestRate": 7.9,
            "rateType": "floating",
            "remainingEmis": 46,
            "dueDay": 18,
            "trackingStartedAt": "2026-06-18T00:00:00Z",
        },
    )

    assert created.status_code == 201, created.text
    payload = created.json()
    assert payload["principalAmount"] == 146087.67
    assert payload["openingPrincipalAmount"] == 146087.67
    assert payload["originalPrincipalAmount"] == 150534
    assert payload["emiAmount"] == 3733
    assert payload["currency"] == "NOK"
    assert payload["interestRate"] == 7.9
    assert payload["rateType"] == "floating"
    assert payload["totalEmis"] == 46
    assert payload["remainingEmis"] == 46
    assert payload["paidEmiCount"] == 0
    assert payload["estimatedOutstanding"] == 146087.67
    assert payload["nextDueDate"] == "2026-06-18T00:00:00Z"


def test_loan_inputs_return_api_errors(tmp_path):
    client, _ = make_client(tmp_path)
    headers = register(client)

    invalid_loan = client.post(
        "/api/v1/loans",
        headers=headers,
        json={
            "name": "Bad loan",
            "principalAmount": "not-a-number",
            "emiAmount": 5000,
        },
    )
    assert invalid_loan.status_code == 400, invalid_loan.text
    assert invalid_loan.json()["error"]["code"] == "INVALID_ARGUMENT"

    created = client.post(
        "/api/v1/loans",
        headers=headers,
        json={
            "name": "Car loan",
            "principalAmount": 100000,
            "emiAmount": 5000,
            "currency": "INR",
            "totalEmis": 20,
            "dueDay": 5,
            "startDate": "2026-06-05T00:00:00Z",
        },
    )
    assert created.status_code == 201, created.text
    loan_id = created.json()["id"]

    zero_payment = client.post(
        f"/api/v1/loans/{loan_id}/payments",
        headers=headers,
        json={"amount": 0, "date": "2026-06-05T10:00:00Z"},
    )
    assert zero_payment.status_code == 400, zero_payment.text
    assert zero_payment.json()["error"]["code"] == "INVALID_ARGUMENT"


def test_savings_goal_contribution_uses_fx_snapshot(tmp_path):
    client, app = make_client(tmp_path)
    headers = register(client)

    def fake_rates(base, quotes):
        assert base == "NOK"
        assert quotes == ["INR"]
        return {
            "provider": "fake-fx",
            "rateAsOf": "2026-06-15T00:00:00Z",
            "rates": {"INR": 8.5},
        }

    app.state.fx_rate_fetcher = fake_rates
    baseline = client.get("/api/v1/sync/freshness?sections=savings", headers=headers)
    assert baseline.status_code == 200, baseline.text
    cursor = baseline.json()["serverTime"]

    created = client.post(
        "/api/v1/savings/goals",
        headers=headers,
        json={
            "name": "India savings",
            "targetAmount": 300000,
            "targetCurrency": "INR",
            "sourceCurrency": "NOK",
            "monthlyTargetAmount": 25000,
            "startMonth": "2026-06",
        },
    )
    assert created.status_code == 201, created.text
    goal = created.json()
    assert goal["targetCurrency"] == "INR"
    assert goal["sourceCurrency"] == "NOK"
    assert goal["totalSavedAmount"] == 0
    goal_id = goal["id"]

    changed = client.get(
        f"/api/v1/sync/freshness?since={cursor}&sections=savings",
        headers=headers,
    )
    assert changed.status_code == 200, changed.text
    assert changed.json()["sections"]["savings"]["changed"] is True

    logged = client.post(
        f"/api/v1/savings/goals/{goal_id}/contributions",
        headers=headers,
        json={
            "sourceAmount": 1000,
            "sourceCurrency": "NOK",
            "targetCurrency": "USD",
            "date": "2026-06-15T10:00:00Z",
            "feeAmount": 25,
        },
    )
    assert logged.status_code == 201, logged.text
    payload = logged.json()
    contribution = payload["contribution"]
    assert contribution["sourceAmount"] == 1000
    assert contribution["sourceCurrency"] == "NOK"
    assert contribution["targetAmount"] == 8500
    assert contribution["targetCurrency"] == "INR"
    assert contribution["exchangeRate"] == 8.5
    assert contribution["marketRate"] == 8.5
    assert contribution["exchangeRateProvider"] == "fake-fx"
    assert payload["goal"]["totalSavedAmount"] == 8500
    assert payload["goal"]["currentMonthSavedAmount"] == 8500
    assert payload["goal"]["remainingAmount"] == 291500

    expenses = client.get("/api/v1/expenses", headers=headers)
    assert expenses.status_code == 200, expenses.text
    assert expenses.json()["expenses"] == []

    contributions = client.get(
        f"/api/v1/savings/goals/{goal_id}/contributions",
        headers=headers,
    )
    assert contributions.status_code == 200, contributions.text
    assert len(contributions.json()["contributions"]) == 1


def test_savings_inputs_return_api_errors(tmp_path):
    client, _ = make_client(tmp_path)
    headers = register(client)

    invalid_goal = client.post(
        "/api/v1/savings/goals",
        headers=headers,
        json={
            "name": "Bad goal",
            "targetAmount": "nope",
            "targetCurrency": "INR",
            "sourceCurrency": "NOK",
        },
    )
    assert invalid_goal.status_code == 400, invalid_goal.text
    assert invalid_goal.json()["error"]["code"] == "INVALID_ARGUMENT"

    goal = client.post(
        "/api/v1/savings/goals",
        headers=headers,
        json={
            "name": "India savings",
            "targetAmount": 300000,
            "targetCurrency": "INR",
            "sourceCurrency": "NOK",
            "monthlyTargetAmount": 25000,
            "startMonth": "2026-06",
        },
    )
    assert goal.status_code == 201, goal.text

    invalid_contribution = client.post(
        f"/api/v1/savings/goals/{goal.json()['id']}/contributions",
        headers=headers,
        json={"sourceAmount": 0, "date": "2026-06-15T10:00:00Z"},
    )
    assert invalid_contribution.status_code == 400, invalid_contribution.text
    assert invalid_contribution.json()["error"]["code"] == "INVALID_ARGUMENT"


def test_recurring_template_lifecycle_updates_generated_occurrences(tmp_path):
    client, _ = make_client(tmp_path)
    headers = register(client)
    current = now()
    period = current_month()
    next_period = (
        f"{current.year + 1:04d}-01"
        if current.month == 12
        else f"{current.year:04d}-{current.month + 1:02d}"
    )

    created = client.post(
        "/api/v1/recurring/templates",
        headers=headers,
        json={
            "title": "Rent",
            "kind": "expense",
            "amount": 12000,
            "currency": "INR",
            "category": "Rent",
            "frequency": "monthly",
            "dayOfMonth": 5,
            "startDate": f"{period}-01T00:00:00Z",
        },
    )
    assert created.status_code == 201, created.text
    template_id = created.json()["id"]

    occurrence = client.get(
        f"/api/v1/recurring/occurrences?month={period}",
        headers=headers,
    ).json()["occurrences"][0]
    assert occurrence["expectedAmount"] == 12000
    assert occurrence["currency"] == "INR"

    updated = client.put(
        f"/api/v1/recurring/templates/{template_id}",
        headers=headers,
        json={
            "title": "Apartment rent",
            "amount": 13000,
            "currency": "USD",
            "category": "Housing",
            "dayOfMonth": 7,
        },
    )
    assert updated.status_code == 200, updated.text
    assert updated.json()["title"] == "Apartment rent"
    assert updated.json()["currency"] == "USD"

    updated_occurrence = client.get(
        f"/api/v1/recurring/occurrences?month={period}",
        headers=headers,
    ).json()["occurrences"][0]
    assert updated_occurrence["id"] == occurrence["id"]
    assert updated_occurrence["title"] == "Apartment rent"
    assert updated_occurrence["expectedAmount"] == 13000
    assert updated_occurrence["currency"] == "USD"
    assert updated_occurrence["category"] == "Housing"

    paused = client.put(
        f"/api/v1/recurring/templates/{template_id}",
        headers=headers,
        json={"active": False},
    )
    assert paused.status_code == 200, paused.text
    assert paused.json()["active"] is False
    assert client.get(
        f"/api/v1/recurring/occurrences?month={period}",
        headers=headers,
    ).json()["occurrences"] == []

    resumed = client.put(
        f"/api/v1/recurring/templates/{template_id}",
        headers=headers,
        json={"active": True},
    )
    assert resumed.status_code == 200, resumed.text
    assert client.get(
        f"/api/v1/recurring/occurrences?month={period}",
        headers=headers,
    ).json()["occurrences"] == []
    resumed_occurrences = client.get(
        f"/api/v1/recurring/occurrences?month={next_period}",
        headers=headers,
    ).json()["occurrences"]
    assert len(resumed_occurrences) == 1
    assert resumed_occurrences[0]["expectedAmount"] == 13000

    deleted = client.delete(
        f"/api/v1/recurring/templates/{template_id}",
        headers=headers,
    )
    assert deleted.status_code == 204, deleted.text
    assert client.get("/api/v1/recurring/templates", headers=headers).json()["templates"] == []
    assert client.get(
        f"/api/v1/recurring/occurrences?month={next_period}",
        headers=headers,
    ).json()["occurrences"] == []


def test_weekly_recurring_template_generates_each_due_date_in_month(tmp_path):
    client, _ = make_client(tmp_path)
    headers = register(client)
    period = current_month()
    year, month_number = [int(part) for part in period.split("-")]
    last_day = calendar.monthrange(year, month_number)[1]
    expected_days = list(range(1, last_day + 1, 7))

    created = client.post(
        "/api/v1/recurring/templates",
        headers=headers,
        json={
            "title": "Weekly salary",
            "kind": "income",
            "amount": 1000,
            "currency": "USD",
            "category": "Salary",
            "frequency": "weekly",
            "dayOfMonth": 1,
            "startDate": f"{period}-01T00:00:00Z",
        },
    )
    assert created.status_code == 201, created.text

    listed = client.get(
        f"/api/v1/recurring/occurrences?month={period}",
        headers=headers,
    )
    assert listed.status_code == 200, listed.text
    occurrences = listed.json()["occurrences"]
    due_days = [
        datetime.fromisoformat(item["dueDate"].replace("Z", "+00:00")).day
        for item in occurrences
    ]
    assert due_days == expected_days
    assert len({item["id"] for item in occurrences}) == len(expected_days)
    assert {item["expectedAmount"] for item in occurrences} == {1000}
    assert {item["currency"] for item in occurrences} == {"USD"}

    dashboard = client.get("/api/v1/dashboard/snapshot", headers=headers)
    assert dashboard.status_code == 200, dashboard.text
    occurrence_ids = {item["id"] for item in occurrences}
    assert any(
        item["actionType"] == "confirm_recurring"
        and item["period"] == period
        and item["occurrenceId"] in occurrence_ids
        for item in dashboard.json()["actionItems"]
    )


def test_recurring_index_migration_allows_multiple_occurrences_per_period(tmp_path):
    client, app = make_client(tmp_path)
    headers = register(client)
    app.state.db.recurring_occurrences.drop_indexes()
    app.state.db.recurring_occurrences.create_index(
        [("uid", 1), ("templateId", 1), ("period", 1)],
        unique=True,
        name="legacy_template_period_unique",
    )
    ensure_indexes(app.state.db)
    index_keys = [
        spec.get("key")
        for spec in app.state.db.recurring_occurrences.index_information().values()
        if spec.get("unique")
    ]
    assert [("uid", 1), ("templateId", 1), ("period", 1)] not in index_keys

    period = current_month()
    created = client.post(
        "/api/v1/recurring/templates",
        headers=headers,
        json={
            "title": "Daily medicine",
            "kind": "expense",
            "amount": 25,
            "currency": "INR",
            "category": "Health",
            "frequency": "daily",
            "dayOfMonth": 1,
            "startDate": f"{period}-01T00:00:00Z",
        },
    )
    assert created.status_code == 201, created.text
    occurrences = client.get(
        f"/api/v1/recurring/occurrences?month={period}",
        headers=headers,
    ).json()["occurrences"]
    assert len(occurrences) >= 2


def test_dashboard_materializes_prior_month_weekly_overdue_actions(tmp_path):
    client, _ = make_client(tmp_path)
    headers = register(client)
    period = current_month()
    previous_period = add_months(period, -1)
    previous_start = f"{previous_period}-01T00:00:00Z"

    created = client.post(
        "/api/v1/recurring/templates",
        headers=headers,
        json={
            "title": "Weekly allowance",
            "kind": "income",
            "amount": 500,
            "currency": "INR",
            "category": "Allowance",
            "frequency": "weekly",
            "dayOfMonth": 1,
            "startDate": previous_start,
        },
    )
    assert created.status_code == 201, created.text
    dashboard = client.get("/api/v1/dashboard/snapshot", headers=headers)
    assert dashboard.status_code == 200, dashboard.text
    previous_occurrences = client.get(
        f"/api/v1/recurring/occurrences?month={previous_period}",
        headers=headers,
    ).json()["occurrences"]
    assert previous_occurrences
    previous_occurrence_ids = {item["id"] for item in previous_occurrences}
    assert any(
        item["actionType"] == "confirm_recurring"
        and item["period"] == previous_period
        and item["occurrenceId"] in previous_occurrence_ids
        for item in dashboard.json()["actionItems"]
    )


def test_dashboard_collapses_daily_recurring_actions_by_template(tmp_path):
    client, _ = make_client(tmp_path)
    headers = register(client)
    period = current_month()
    today = now()

    created = client.post(
        "/api/v1/recurring/templates",
        headers=headers,
        json={
            "title": "Daily medicine",
            "kind": "expense",
            "amount": 25,
            "currency": "INR",
            "category": "Health",
            "frequency": "daily",
            "dayOfMonth": 1,
            "startDate": f"{period}-01T00:00:00Z",
        },
    )
    assert created.status_code == 201, created.text

    dashboard = client.get("/api/v1/dashboard/snapshot", headers=headers)
    assert dashboard.status_code == 200, dashboard.text
    medicine_actions = [
        item
        for item in dashboard.json()["actionItems"]
        if item["actionType"] == "confirm_recurring" and item["title"] == "Confirm Daily medicine"
    ]
    assert len(medicine_actions) == 1
    assert medicine_actions[0]["occurrenceCount"] == today.day
    if today.day > 1:
        assert "overdue" in medicine_actions[0]["subtitle"]
        assert "each" in medicine_actions[0]["subtitle"]
    else:
        assert medicine_actions[0]["subtitle"].startswith("Due today")


def test_dashboard_includes_daily_action_items(tmp_path):
    client, _ = make_client(tmp_path)
    headers_a = register(client, "alice@example.com")
    register(client, "bob@example.com")
    period = current_month()
    today = now()

    recurring = client.post(
        "/api/v1/recurring/templates",
        headers=headers_a,
        json={
            "title": "Rent",
            "kind": "expense",
            "amount": 12000,
            "currency": "INR",
            "category": "Rent",
            "frequency": "monthly",
            "dayOfMonth": today.day,
            "startDate": f"{period}-01T00:00:00Z",
        },
    )
    assert recurring.status_code == 201, recurring.text

    group = client.post(
        "/api/v1/groups",
        headers=headers_a,
        json={
            "name": "Our household",
            "groupType": "family",
            "members": ["bob@example.com"],
        },
    )
    assert group.status_code == 201, group.text
    group_id = group.json()["id"]

    expense = client.post(
        f"/api/v1/groups/{group_id}/expenses",
        headers=headers_a,
        json={
            "description": "Monthly grocery run",
            "amount": 250,
            "category": "Groceries",
            "date": iso(today),
        },
    )
    assert expense.status_code == 201, expense.text

    saved = client.put(
        "/api/v1/planning/monthly",
        headers=headers_a,
        json={"month": period, "currency": "INR", "budgets": {"Groceries": 100}},
    )
    assert saved.status_code == 200, saved.text

    dashboard = client.get("/api/v1/dashboard/snapshot", headers=headers_a)
    assert dashboard.status_code == 200, dashboard.text
    actions = dashboard.json()["actionItems"]
    assert any(
        item["destination"] == "recurring"
        and item["actionType"] == "confirm_recurring"
        and item["occurrenceId"]
        and item["period"] == period
        and "Confirm Rent" in item["title"]
        for item in actions
    )
    assert any(item["destination"] == "family" and item["severity"] == "critical" for item in actions)
    assert any(
        item["destination"] == "family"
        and item["actionType"] == "attach_group_receipt"
        and item["groupId"] == group_id
        and item["expenseId"] == expense.json()["id"]
        and item["title"].startswith("Attach receipt")
        for item in actions
    )


def test_dashboard_includes_prior_month_overdue_recurring_action(tmp_path):
    client, app = make_client(tmp_path)
    headers = register(client, "alice@example.com")
    user = client.get("/api/v1/auth/me", headers=headers).json()["user"]
    due_date = now() - timedelta(days=20)
    app.state.db.recurring_occurrences.insert_one({
        "id": "old-insurance",
        "uid": user["uid"],
        "templateId": "old-template",
        "period": f"{due_date.year:04d}-{due_date.month:02d}",
        "kind": "expense",
        "title": "Insurance",
        "category": "Bills",
        "currency": "INR",
        "expectedAmount": 2200,
        "actualAmount": None,
        "actualDate": None,
        "dueDate": due_date,
        "status": "expected",
        "notes": "",
        "createdAt": due_date,
        "updatedAt": due_date,
    })

    dashboard = client.get("/api/v1/dashboard/snapshot", headers=headers)
    assert dashboard.status_code == 200, dashboard.text
    actions = dashboard.json()["actionItems"]
    assert any(
        item["destination"] == "recurring"
        and item["actionType"] == "confirm_recurring"
        and item["occurrenceId"] == "old-insurance"
        and item["period"] == f"{due_date.year:04d}-{due_date.month:02d}"
        and item["title"] == "Confirm Insurance"
        and item["subtitle"].startswith("Overdue")
        for item in actions
    )


def test_dashboard_group_action_skips_settled_group_items(tmp_path):
    client, _ = make_client(tmp_path)
    headers_a = register(client, "alice@example.com")
    register(client, "bob@example.com")

    unsettled = client.post(
        "/api/v1/groups",
        headers=headers_a,
        json={"name": "Weekend Trip", "groupType": "split", "members": ["bob@example.com"]},
    )
    assert unsettled.status_code == 201, unsettled.text
    unsettled_expense = client.post(
        f"/api/v1/groups/{unsettled.json()['id']}/expenses",
        headers=headers_a,
        json={
            "description": "Dinner",
            "amount": 100,
            "date": iso(now()),
        },
    )
    assert unsettled_expense.status_code == 201, unsettled_expense.text

    settled = client.post(
        "/api/v1/groups",
        headers=headers_a,
        json={"name": "Solo planning", "groupType": "split"},
    )
    assert settled.status_code == 201, settled.text
    settled_expense = client.post(
        f"/api/v1/groups/{settled.json()['id']}/expenses",
        headers=headers_a,
        json={
            "description": "Notes",
            "amount": 20,
            "date": iso(now()),
        },
    )
    assert settled_expense.status_code == 201, settled_expense.text

    dashboard = client.get("/api/v1/dashboard/snapshot", headers=headers_a)
    assert dashboard.status_code == 200, dashboard.text
    actions = dashboard.json()["actionItems"]
    assert any(
        item["destination"] == "groups"
        and item["actionType"] == "review_group_balance"
        and item["groupId"] == unsettled.json()["id"]
        and item["title"] == "Review Weekend Trip balance"
        for item in actions
    )


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
        json={"friendUid": added.json()["uid"], "direction": "paid", "amount": 120, "currency": "USD"},
    )
    assert settlement.status_code == 201, settlement.text
    settlement_nok = client.post(
        "/api/v1/friends/settlements",
        headers=headers_a,
        json={"friendUid": added.json()["uid"], "direction": "paid", "amount": 50, "currency": "NOK"},
    )
    assert settlement_nok.status_code == 201, settlement_nok.text

    balances_a = client.get("/api/v1/friends/balances", headers=headers_a)
    balances_b = client.get("/api/v1/friends/balances", headers=headers_b)
    assert balances_a.status_code == 200
    assert balances_b.status_code == 200
    bob_uid = added.json()["uid"]
    alice_uid = client.get("/api/v1/auth/me", headers=headers_a).json()["user"]["uid"]
    assert balances_a.json()["balances"][bob_uid] == 170
    assert balances_b.json()["balances"][alice_uid] == -170
    assert balances_a.json()["balancesByCurrency"][bob_uid] == {"NOK": 50, "USD": 120}
    assert balances_b.json()["balancesByCurrency"][alice_uid] == {"NOK": -50, "USD": -120}

    dashboard = client.get("/api/v1/dashboard/snapshot", headers=headers_a)
    assert dashboard.status_code == 200
    assert dashboard.json()["friendItems"][0]["title"] == "User"
    assert dashboard.json()["friendItems"][0]["subtitle"] == "owes you"
    assert dashboard.json()["friendItems"][0]["amountText"] == "NOK 50.00, USD 120.00"


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


def test_group_expense_persists_exact_split_amounts_in_balances(tmp_path):
    client, _ = make_client(tmp_path)
    headers_a = register(client, "alice@example.com")
    register(client, "bob@example.com")
    register(client, "charlie@example.com")
    alice_uid = client.get("/api/v1/auth/me", headers=headers_a).json()["user"]["uid"]

    group = client.post(
        "/api/v1/groups",
        headers=headers_a,
        json={
            "name": "Family",
            "groupType": "family",
            "members": ["bob@example.com", "charlie@example.com"],
        },
    )
    assert group.status_code == 201, group.text
    group_id = group.json()["id"]
    members = client.get(f"/api/v1/groups/{group_id}/members", headers=headers_a)
    assert members.status_code == 200, members.text
    member_by_email = {item["email"]: item["uid"] for item in members.json()["members"]}
    bob_uid = member_by_email["bob@example.com"]
    charlie_uid = member_by_email["charlie@example.com"]

    created = client.post(
        f"/api/v1/groups/{group_id}/expenses",
        headers=headers_a,
        json={
            "description": "Groceries",
            "paidBy": "alice@example.com",
            "splitMode": "exact",
            "splitAmounts": {
                "alice@example.com": 10,
                "bob@example.com": 20,
                "charlie@example.com": 60,
            },
            "amount": 90,
            "date": "2026-05-20T10:00:00Z",
        },
    )
    assert created.status_code == 201, created.text
    payload = created.json()
    assert payload["splitMode"] == "exact"
    assert payload["splitWith"] == [alice_uid, bob_uid, charlie_uid]
    assert payload["splitAmounts"] == {alice_uid: 10, bob_uid: 20, charlie_uid: 60}
    assert payload["splitAmountsByCurrency"]["INR"] == {
        alice_uid: 10,
        bob_uid: 20,
        charlie_uid: 60,
    }

    groups = client.get("/api/v1/groups", headers=headers_a)
    balances = groups.json()["groups"][0]["displayData"]["memberBalances"]
    assert balances[alice_uid]["net"] == 80
    assert balances[bob_uid]["net"] == -20
    assert balances[charlie_uid]["net"] == -60


def test_group_settlement_is_shared_and_updates_group_balances(tmp_path):
    client, _ = make_client(tmp_path)
    headers_a = register(client, "alice@example.com")
    headers_b = register(client, "bob@example.com")
    alice_uid = client.get("/api/v1/auth/me", headers=headers_a).json()["user"]["uid"]
    bob_uid = client.get("/api/v1/auth/me", headers=headers_b).json()["user"]["uid"]

    group = client.post(
        "/api/v1/groups",
        headers=headers_a,
        json={"name": "Household", "groupType": "family", "members": ["bob@example.com"]},
    )
    assert group.status_code == 201, group.text
    group_id = group.json()["id"]
    created = client.post(
        f"/api/v1/groups/{group_id}/expenses",
        headers=headers_a,
        json={
            "description": "Groceries",
            "paidBy": alice_uid,
            "splitWith": [alice_uid, bob_uid],
            "amount": 100,
            "date": "2026-05-20T10:00:00Z",
        },
    )
    assert created.status_code == 201, created.text

    settlement = client.post(
        f"/api/v1/groups/{group_id}/settlements",
        headers=headers_b,
        json={
            "memberUid": alice_uid,
            "direction": "paid",
            "amount": 50,
            "currency": "INR",
        },
    )
    assert settlement.status_code == 201, settlement.text
    payload = settlement.json()
    assert payload["payerUid"] == bob_uid
    assert payload["receiverUid"] == alice_uid

    history = client.get(f"/api/v1/groups/{group_id}/settlements", headers=headers_a)
    assert history.status_code == 200, history.text
    assert history.json()["settlements"][0]["id"] == payload["id"]

    groups = client.get("/api/v1/groups", headers=headers_a)
    balances = groups.json()["groups"][0]["displayData"]["memberBalances"]
    assert balances[alice_uid]["net"] == 0
    assert balances[bob_uid]["net"] == 0


def test_pending_family_invite_auto_joins_when_member_registers(tmp_path):
    client, _ = make_client(tmp_path)
    headers_a = register(client, "alice@example.com")

    group = client.post(
        "/api/v1/groups",
        headers=headers_a,
        json={
            "name": "Household",
            "groupType": "family",
            "members": ["bob@example.com"],
            "ownerRole": "Husband",
            "memberRolesByContact": {"bob@example.com": "Wife"},
        },
    )
    assert group.status_code == 201, group.text
    assert group.json()["memberCount"] == 1
    assert group.json()["pendingInviteCount"] == 1
    assert group.json()["pendingInvites"][0]["contact"] == "bob@example.com"
    assert group.json()["pendingInvites"][0]["role"] == "Wife"
    group_id = group.json()["id"]

    headers_b = register(client, "bob@example.com")

    bob_groups = client.get("/api/v1/groups", headers=headers_b)
    assert bob_groups.status_code == 200, bob_groups.text
    assert [item["id"] for item in bob_groups.json()["groups"]] == [group_id]
    assert bob_groups.json()["groups"][0]["memberCount"] == 2
    assert bob_groups.json()["groups"][0]["pendingInviteCount"] == 0

    members = client.get(f"/api/v1/groups/{group_id}/members", headers=headers_b)
    assert members.status_code == 200, members.text
    roles_by_email = {
        member["email"]: member["role"]
        for member in members.json()["members"]
    }
    assert roles_by_email["alice@example.com"] == "Husband"
    assert roles_by_email["bob@example.com"] == "Wife"

    alice_groups = client.get("/api/v1/groups", headers=headers_a)
    assert alice_groups.status_code == 200, alice_groups.text
    assert alice_groups.json()["groups"][0]["pendingInviteCount"] == 0


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
    assert groceries["convertedExpenseCount"] == 1

    eur_plan = client.put(
        "/api/v1/planning/monthly",
        headers=headers_a,
        json={"month": "2026-05", "currency": "EUR", "budgets": {"Groceries": 1000}},
    )
    assert eur_plan.status_code == 200, eur_plan.text
    eur_payload = eur_plan.json()
    eur_groceries = next(item for item in eur_payload["categories"] if item["category"] == "Groceries")
    assert eur_payload["totalActual"] == 0
    assert eur_payload["excludedExpenseCount"] == 1
    assert eur_payload["skippedActualExpenseCount"] == 1
    assert eur_payload["excludedActualsByCurrency"] == {"USD": 10}
    assert eur_payload["actualsMetadata"]["uncountedExpenseCount"] == 1
    assert eur_payload["actualsMetadata"]["uncountedSpendByCurrency"] == {"USD": 10}
    assert eur_payload["actualsMetadata"]["uncountedSpendByCategoryByCurrency"] == {
        "Groceries": {"USD": 10}
    }
    assert eur_groceries["actual"] == 0
    assert eur_groceries["excludedExpenseCount"] == 1
    assert eur_groceries["skippedActualExpenseCount"] == 1
    assert eur_groceries["excludedActualsByCurrency"] == {"USD": 10}


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
