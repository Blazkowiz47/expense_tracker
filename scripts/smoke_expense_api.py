#!/usr/bin/env python3
"""Smoke test the core expense-tracker API journey.

The script creates a disposable user, then verifies the minimum path a new user
needs: accounts, cards, monthly planning, expenses, income, transfers, activity,
and dashboard reads. It uses only the Python standard library so it can run on
developer machines and simple CI jobs.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any


DEFAULT_BASE_URL = "http://127.0.0.1:8080"


@dataclass
class ApiClient:
    base_url: str
    timeout: float
    token: str = ""

    def request(
        self,
        method: str,
        path: str,
        body: dict[str, Any] | None = None,
        query: dict[str, str] | None = None,
    ) -> Any:
        url = self.base_url.rstrip("/") + path
        if query:
            url += "?" + urllib.parse.urlencode(query)
        data = None
        headers = {"Accept": "application/json"}
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"
        if body is not None:
            data = json.dumps(body).encode("utf-8")
            headers["Content-Type"] = "application/json"
        request = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                content = response.read().decode("utf-8")
                if not content:
                    return {}
                return json.loads(content)
        except urllib.error.HTTPError as exc:
            content = exc.read().decode("utf-8", errors="replace")
            raise AssertionError(f"{method} {path} failed with {exc.code}: {content}") from exc

    def get(self, path: str, query: dict[str, str] | None = None) -> Any:
        return self.request("GET", path, query=query)

    def post(self, path: str, body: dict[str, Any]) -> Any:
        return self.request("POST", path, body=body)

    def put(self, path: str, body: dict[str, Any]) -> Any:
        return self.request("PUT", path, body=body)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run the expense API smoke journey.")
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL)
    parser.add_argument("--email", default="")
    parser.add_argument("--password", default="SmokePassw0rd!")
    parser.add_argument("--timeout", type=float, default=20)
    return parser.parse_args(argv)


def assert_close(actual: Any, expected: float, label: str) -> None:
    try:
        value = float(actual)
    except (TypeError, ValueError) as exc:
        raise AssertionError(f"{label}: expected numeric {expected}, got {actual!r}") from exc
    if not math.isclose(value, expected, rel_tol=0, abs_tol=0.01):
        raise AssertionError(f"{label}: expected {expected}, got {value}")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def iso_date(day: int) -> str:
    current = datetime.now(timezone.utc)
    return current.replace(day=day, hour=12, minute=0, second=0, microsecond=0).isoformat().replace("+00:00", "Z")


def current_month() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m")


def unique_email() -> str:
    return f"smoke+{int(time.time())}@example.com"


def create_session(client: ApiClient, email: str, password: str) -> None:
    payload = client.post(
        "/api/v1/auth/register",
        {"email": email, "password": password, "displayName": "Smoke User"},
    )
    token = payload.get("token")
    require(isinstance(token, str) and bool(token), "register response did not include a token")
    client.token = token
    profile = client.get("/api/v1/auth/me")
    require(profile.get("user", {}).get("email") == email, "auth/me did not return the registered user")


def run_smoke(client: ApiClient, email: str, password: str) -> None:
    print(f"Smoke user: {email}")
    create_session(client, email, password)

    salary = client.post(
        "/api/v1/accounts",
        {
            "name": "Smoke Salary",
            "institution": "Smoke Bank",
            "accountType": "checking",
            "currency": "NOK",
            "openingBalance": 1000,
        },
    )
    savings = client.post(
        "/api/v1/accounts",
        {
            "name": "Smoke Savings",
            "institution": "Smoke Bank",
            "accountType": "savings",
            "currency": "NOK",
            "openingBalance": 200,
        },
    )
    salary_id = salary["id"]
    savings_id = savings["id"]
    card = client.post(
        "/api/v1/credit-cards",
        {
            "name": "Smoke Card",
            "issuer": "Smoke Issuer",
            "last4": "4242",
            "currency": "NOK",
            "creditLimit": 10000,
            "currentBalance": 0,
            "statementDay": 20,
            "dueDay": 5,
        },
    )
    card_id = card["id"]

    month = current_month()
    plan = client.put(
        "/api/v1/planning/monthly",
        {
            "month": month,
            "currency": "NOK",
            "income": 500,
            "budgets": {
                "Groceries": 125,
                "Savings - Smoke": 300,
                "Transport": 59,
            },
        },
    )
    require(plan.get("month") == month, "monthly plan month did not round-trip")
    require(plan.get("currency") == "NOK", "monthly plan currency did not round-trip")

    income = client.post(
        "/api/v1/expenses",
        {
            "amount": 500,
            "currency": "NOK",
            "category": "Salary",
            "description": "Smoke salary",
            "paymentMethod": f"account:{salary_id}",
            "sourcePaymentType": "income",
            "date": iso_date(15),
        },
    )
    grocery = client.post(
        "/api/v1/expenses",
        {
            "amount": 125,
            "currency": "NOK",
            "category": "Groceries",
            "description": "Smoke grocery",
            "paymentMethod": f"account:{salary_id}",
            "date": iso_date(16),
            "tags": ["smoke", "groceries"],
        },
    )
    transfer = client.post(
        "/api/v1/expenses",
        {
            "amount": 300,
            "currency": "NOK",
            "category": "Savings - Smoke",
            "description": "Smoke savings transfer",
            "paymentMethod": f"account:{salary_id}",
            "sourceDestinationAccountId": savings_id,
            "date": iso_date(17),
            "tags": ["smoke", "transfer"],
        },
    )
    card_spend = client.post(
        f"/api/v1/credit-cards/{card_id}/spend",
        {
            "amount": 59,
            "category": "Transport",
            "description": "Smoke train pass",
            "date": iso_date(18),
            "tags": ["smoke", "card"],
        },
    )

    require(income.get("sourcePaymentType") == "income", "income row did not preserve income type")
    require(grocery.get("sourceAccountId") == salary_id, "account expense did not store source account")
    require(transfer.get("sourceDestinationAccountId") == savings_id, "transfer did not store destination account")
    assert_close(card_spend.get("card", {}).get("currentBalance"), 59, "credit card balance after spend")

    account_payload = client.get("/api/v1/accounts")
    accounts = {account["id"]: account for account in account_payload.get("accounts", [])}
    require(salary_id in accounts, "salary account missing from account list")
    require(savings_id in accounts, "savings account missing from account list")
    assert_close(accounts[salary_id]["currentBalance"], 1075, "salary account reconciled balance")
    assert_close(accounts[savings_id]["currentBalance"], 500, "savings account reconciled balance")

    card_payload = client.get("/api/v1/credit-cards")
    cards = {item["id"]: item for item in card_payload.get("cards", [])}
    require(card_id in cards, "credit card missing from card list")
    assert_close(cards[card_id]["currentBalance"], 59, "credit card list reconciled balance")

    expenses = client.get("/api/v1/expenses", {"limit": "20"}).get("expenses", [])
    descriptions = {expense.get("description") for expense in expenses}
    for expected in {"Smoke salary", "Smoke grocery", "Smoke savings transfer", "Smoke train pass"}:
        require(expected in descriptions, f"{expected!r} missing from expenses list")

    activity = client.get("/api/v1/activity", {"include": "personal", "limit": "20"}).get("entries", [])
    activity_descriptions = {
        entry.get("expense", {}).get("description")
        for entry in activity
        if entry.get("kind") == "personalExpense"
    }
    require("Smoke grocery" in activity_descriptions, "activity feed did not include personal expense")

    dashboard = client.get("/api/v1/dashboard/snapshot", {"includeAi": "false"})
    require("summary" in dashboard or "monthlyPlan" in dashboard or "actionItems" in dashboard, "dashboard snapshot returned an unexpected shape")

    print("Smoke passed:")
    print(f"  accounts: salary={salary_id} savings={savings_id}")
    print(f"  card: {card_id}")
    print(f"  expenses: {', '.join(sorted(descriptions & {'Smoke salary', 'Smoke grocery', 'Smoke savings transfer', 'Smoke train pass'}))}")


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    client = ApiClient(base_url=args.base_url, timeout=args.timeout)
    email = args.email.strip() or unique_email()
    try:
        run_smoke(client, email, args.password)
    except Exception as exc:
        print(f"Smoke failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
