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
