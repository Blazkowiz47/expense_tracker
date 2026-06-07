from __future__ import annotations

import calendar
import base64
import csv
import hashlib
import io
import json
import mimetypes
import os
import re
import secrets
import shutil
import uuid
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any

import httpx
from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError
from fastapi import (
    BackgroundTasks,
    Depends,
    FastAPI,
    File,
    Form,
    HTTPException,
    Query,
    Request,
    Response,
    UploadFile,
)
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse, PlainTextResponse
from fastapi.staticfiles import StaticFiles
from pymongo import ASCENDING, MongoClient


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DATA_DIR = ROOT / "data"
ph = PasswordHasher()


def now() -> datetime:
    return datetime.now(UTC)


def iso(value: datetime | None) -> str | None:
    if value is None:
        return None
    if value.tzinfo is None:
        value = value.replace(tzinfo=UTC)
    return value.astimezone(UTC).isoformat().replace("+00:00", "Z")


def parse_dt(value: str | None, fallback: datetime | None = None) -> datetime:
    if not value:
        return fallback or now()
    cleaned = value.replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(cleaned)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", "date must be RFC3339")) from exc
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=UTC)
    return parsed.astimezone(UTC)


def aware(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=UTC)
    return value.astimezone(UTC)


def api_error(code: str, message: str) -> dict[str, str]:
    return {"code": code, "message": message}


def json_ready(value: Any) -> Any:
    if isinstance(value, datetime):
        return iso(value)
    if isinstance(value, list):
        return [json_ready(item) for item in value]
    if isinstance(value, dict):
        return {key: json_ready(item) for key, item in value.items() if key != "_id"}
    return value


def token_hash(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def normalize_email(email: str) -> str:
    return email.strip().lower()


def user_public(user: dict[str, Any]) -> dict[str, Any]:
    return {
        "uid": user["uid"],
        "email": user.get("email", ""),
        "displayName": user.get("displayName") or user.get("email", "User"),
        "photoUrl": user.get("photoUrl"),
        "phone": user.get("phone", ""),
    }


def require_json(body: dict[str, Any], *keys: str) -> None:
    missing = [key for key in keys if str(body.get(key, "")).strip() == ""]
    if missing:
        raise HTTPException(
            status_code=400,
            detail=api_error("INVALID_ARGUMENT", f"missing required fields: {', '.join(missing)}"),
        )


class LocalGemmaBillExtractor:
    def __init__(self, base_url: str | None, model: str):
        self.base_url = (base_url or "").strip()
        self.model = model

    async def extract(self, file_path: Path, original_name: str) -> dict[str, Any]:
        if self.base_url:
            try:
                async with httpx.AsyncClient(timeout=60) as client:
                    response = await client.post(
                        self.base_url.rstrip("/") + "/api/v1/extract-bill",
                        json={"path": str(file_path), "fileName": original_name, "model": self.model},
                    )
                    response.raise_for_status()
                    data = response.json()
                    if isinstance(data, dict):
                        return self._normalize(data, original_name, [])
            except Exception as exc:  # pragma: no cover - exercised through fake provider tests
                return self._fallback(original_name, [f"Local Gemma provider unavailable: {exc}"])
        return self._fallback(original_name, ["Local Gemma provider is not configured."])

    def _fallback(self, original_name: str, warnings: list[str]) -> dict[str, Any]:
        stem = Path(original_name).stem.replace("_", " ").replace("-", " ").strip()
        merchant = stem.title() if stem else "Uploaded bill"
        return self._normalize(
            {
                "merchant": merchant,
                "date": iso(now()),
                "amount": 0,
                "currency": "INR",
                "category": "Personal",
                "notes": "Review this extraction before saving.",
                "lineItems": [],
                "confidence": 0.2,
            },
            original_name,
            warnings,
        )

    def _normalize(self, raw: dict[str, Any], original_name: str, warnings: list[str]) -> dict[str, Any]:
        amount = raw.get("amount", 0)
        try:
            amount = float(amount)
        except (TypeError, ValueError):
            amount = 0
            warnings.append("Amount could not be parsed.")
        return {
            "merchant": str(raw.get("merchant") or Path(original_name).stem or "Uploaded bill").strip(),
            "date": str(raw.get("date") or iso(now())),
            "amount": amount,
            "currency": str(raw.get("currency") or "INR"),
            "category": str(raw.get("category") or "Personal"),
            "notes": str(raw.get("notes") or ""),
            "lineItems": raw.get("lineItems") if isinstance(raw.get("lineItems"), list) else [],
            "confidence": max(0.0, min(float(raw.get("confidence") or 0), 1.0)),
            "warnings": warnings + [str(item) for item in raw.get("warnings", []) if str(item).strip()],
        }


class LlamaServerBillExtractor(LocalGemmaBillExtractor):
    def __init__(self, base_url: str | None, model: str):
        super().__init__(base_url, model)

    async def extract(self, file_path: Path, original_name: str) -> dict[str, Any]:
        if not self.base_url:
            return self._fallback(original_name, ["Local llama-server provider is not configured."])
        try:
            data_url = self._file_data_url(file_path, original_name)
            async with httpx.AsyncClient(timeout=120) as client:
                response = await client.post(
                    self.base_url.rstrip("/") + "/v1/chat/completions",
                    json={
                        "model": self.model,
                        "temperature": 0,
                        "messages": [
                            {
                                "role": "system",
                                "content": (
                                    "You extract receipt and bill fields for an expense tracker. "
                                    "Return only valid JSON. Do not include reasoning or markdown."
                                ),
                            },
                            {
                                "role": "user",
                                "content": [
                                    {"type": "image_url", "image_url": {"url": data_url}},
                                    {
                                        "type": "text",
                                        "text": (
                                            "Extract merchant, date, amount, currency, category, notes, "
                                            "lineItems, confidence, and warnings from this bill. "
                                            "Use ISO 8601 for date when visible. category should be a short "
                                            "expense category. lineItems should be an array of objects with "
                                            "name, quantity, amount when visible."
                                        ),
                                    },
                                ],
                            },
                        ],
                    },
                )
                response.raise_for_status()
                content = response.json()["choices"][0]["message"]["content"]
                return self._normalize(parse_model_json(content), original_name, [])
        except Exception as exc:  # pragma: no cover - network path is covered by integration tests
            return self._fallback(original_name, [f"Local llama-server provider unavailable: {exc}"])

    def _file_data_url(self, file_path: Path, original_name: str) -> str:
        mime_type = mimetypes.guess_type(original_name)[0] or "application/octet-stream"
        encoded = base64.b64encode(file_path.read_bytes()).decode("ascii")
        return f"data:{mime_type};base64,{encoded}"


def parse_model_json(content: Any) -> dict[str, Any]:
    if isinstance(content, dict):
        return content
    text = str(content or "").strip()
    if text.startswith("```"):
        text = re.sub(r"^```(?:json)?\s*", "", text)
        text = re.sub(r"\s*```$", "", text).strip()
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError:
        match = re.search(r"\{.*\}", text, re.DOTALL)
        if not match:
            raise
        parsed = json.loads(match.group(0))
    if not isinstance(parsed, dict):
        raise ValueError("model response must be a JSON object")
    return parsed


def build_ai_provider() -> LocalGemmaBillExtractor:
    base_url = os.getenv("AI_BASE_URL")
    model = os.getenv("AI_MODEL", "unsloth/gemma-4-E4B-it-GGUF")
    provider = os.getenv("AI_PROVIDER", "custom").strip().lower()
    if provider in {"llama-server", "llama_cpp", "openai-compatible", "openai_compatible"}:
        return LlamaServerBillExtractor(base_url, model)
    return LocalGemmaBillExtractor(base_url, model)


def create_app(database: Any | None = None, ai_provider: LocalGemmaBillExtractor | None = None) -> FastAPI:
    app = FastAPI(title="Expense Tracker API")
    data_dir = Path(os.getenv("DATA_DIR", str(DEFAULT_DATA_DIR)))
    upload_dir = data_dir / "uploads"
    upload_dir.mkdir(parents=True, exist_ok=True)

    if database is None:
        client = MongoClient(os.getenv("MONGO_URI", "mongodb://127.0.0.1:27017"), serverSelectionTimeoutMS=1000)
        database = client[os.getenv("MONGO_DB", "expense_tracker_local")]
        app.state.mongo_client = client
    app.state.db = database
    app.state.upload_dir = upload_dir
    app.state.ai_provider = ai_provider or build_ai_provider()

    app.add_middleware(
        CORSMiddleware,
        allow_origins=[item.strip() for item in os.getenv("CORS_ALLOWED_ORIGINS", "*").split(",") if item.strip()],
        allow_credentials=False,
        allow_methods=["*"],
        allow_headers=["Authorization", "Content-Type"],
    )

    @app.on_event("startup")
    def startup() -> None:
        ensure_indexes(app.state.db)

    def current_user(request: Request) -> dict[str, Any]:
        auth = request.headers.get("Authorization", "")
        if not auth.startswith("Bearer "):
            raise HTTPException(status_code=401, detail=api_error("MISSING_TOKEN", "missing Authorization header"))
        token = auth.removeprefix("Bearer ").strip()
        if os.getenv("AUTH_MODE") == "dev" and token == os.getenv("DEV_AUTH_TOKEN", "dev-token"):
            uid = os.getenv("DEV_AUTH_UID", "local-user")
            user = app.state.db.users.find_one({"uid": uid})
            if not user:
                user = create_user_doc(uid, "local@example.com", "Local User", ph.hash(secrets.token_urlsafe(16)))
                app.state.db.users.insert_one(user)
            return user
        session = app.state.db.sessions.find_one({"tokenHash": token_hash(token)})
        expires_at = session.get("expiresAt", now()) if session else now()
        if not session or aware(expires_at) < now():
            raise HTTPException(status_code=401, detail=api_error("INVALID_TOKEN", "token verification failed"))
        user = app.state.db.users.find_one({"uid": session["uid"]})
        if not user:
            raise HTTPException(status_code=401, detail=api_error("INVALID_TOKEN", "token verification failed"))
        return user

    @app.exception_handler(HTTPException)
    async def http_exception_handler(_: Request, exc: HTTPException) -> JSONResponse:
        detail = exc.detail if isinstance(exc.detail, dict) else api_error("ERROR", str(exc.detail))
        return JSONResponse(status_code=exc.status_code, content={"error": detail})

    @app.get("/health")
    def health() -> dict[str, str]:
        return {"status": "ok"}

    @app.post("/api/v1/auth/register", status_code=201)
    def register(body: dict[str, Any]) -> dict[str, Any]:
        require_json(body, "email", "password")
        email = normalize_email(str(body["email"]))
        if len(str(body["password"])) < 8:
            raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", "password must be at least 8 characters"))
        if app.state.db.users.find_one({"emailNormalized": email}):
            raise HTTPException(status_code=409, detail=api_error("ALREADY_EXISTS", "email already registered"))
        uid = uuid.uuid4().hex
        user = create_user_doc(
            uid,
            email,
            str(body.get("displayName") or email.split("@")[0] or "User"),
            ph.hash(str(body["password"])),
        )
        app.state.db.users.insert_one(user)
        token = create_session(app.state.db, uid)
        return {"token": token, "user": user_public(user)}

    @app.post("/api/v1/auth/login")
    def login(body: dict[str, Any]) -> dict[str, Any]:
        require_json(body, "email", "password")
        user = app.state.db.users.find_one({"emailNormalized": normalize_email(str(body["email"]))})
        if not user:
            raise HTTPException(status_code=401, detail=api_error("INVALID_CREDENTIALS", "invalid email or password"))
        try:
            ph.verify(user["passwordHash"], str(body["password"]))
        except VerifyMismatchError as exc:
            raise HTTPException(status_code=401, detail=api_error("INVALID_CREDENTIALS", "invalid email or password")) from exc
        token = create_session(app.state.db, user["uid"])
        return {"token": token, "user": user_public(user)}

    @app.post("/api/v1/auth/logout")
    def logout(request: Request, user: dict[str, Any] = Depends(current_user)) -> dict[str, bool]:
        auth = request.headers.get("Authorization", "")
        token = auth.removeprefix("Bearer ").strip()
        app.state.db.sessions.delete_many({"uid": user["uid"], "tokenHash": token_hash(token)})
        return {"loggedOut": True}

    @app.get("/api/v1/auth/me")
    def me(user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
        return {"user": user_public(user)}

    @app.get("/api/v1/profile")
    def profile(user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
        return user_public(user)

    @app.put("/api/v1/profile")
    def update_profile(body: dict[str, Any], user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
        display_name = str(body.get("displayName") or "").strip()
        if not display_name:
            raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", "displayName is required"))
        app.state.db.users.update_one({"uid": user["uid"]}, {"$set": {"displayName": display_name, "updatedAt": now()}})
        return user_public(app.state.db.users.find_one({"uid": user["uid"]}))

    @app.post("/api/v1/profile/photo")
    async def upload_profile_photo(file: UploadFile = File(...), user: dict[str, Any] = Depends(current_user)) -> dict[str, str]:
        url = await save_upload(app, file, f"users/{user['uid']}")
        app.state.db.users.update_one({"uid": user["uid"]}, {"$set": {"photoUrl": url, "updatedAt": now()}})
        return {"url": url}

    @app.get("/api/v1/theme-packs")
    def theme_packs() -> list[dict[str, Any]]:
        return [
            {"familyId": "splitwise", "displayName": "Splitwise", "lightAccent": 0xFF26A17B, "darkAccent": 0xFF1A8F6C, "highContrastAccent": 0xFF000000},
            {"familyId": "tokyoNight", "displayName": "Tokyo Night", "lightAccent": 0xFF7AA2F7, "darkAccent": 0xFF7DCFFF, "highContrastAccent": 0xFF1D1D1D},
            {"familyId": "mint", "displayName": "Mint", "lightAccent": 0xFF3FBF9B, "darkAccent": 0xFF2FAE8E, "highContrastAccent": 0xFF0B3D2E},
        ]

    @app.get("/api/v1/expenses")
    def list_expenses(
        page: int = 1,
        limit: int = 20,
        category: str = "",
        from_: str | None = Query(default=None, alias="from"),
        to: str | None = None,
        user: dict[str, Any] = Depends(current_user),
    ) -> dict[str, Any]:
        filters: dict[str, Any] = {"uid": user["uid"]}
        if category.strip():
            filters["category"] = category.strip()
        add_date_filter(filters, from_, to)
        docs = list(app.state.db.expenses.find(filters).sort("date", -1).skip(max(page - 1, 0) * limit).limit(max(1, min(limit, 1000))))
        return {"expenses": [expense_out(doc) for doc in docs]}

    @app.post("/api/v1/expenses", status_code=201)
    def create_expense(body: dict[str, Any], user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
        expense = build_expense(body, user["uid"])
        app.state.db.expenses.insert_one(expense)
        return expense_out(expense)

    @app.put("/api/v1/expenses/{expense_id}")
    def update_expense(expense_id: str, body: dict[str, Any], user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
        existing = app.state.db.expenses.find_one({"id": expense_id, "uid": user["uid"]})
        if not existing:
            raise HTTPException(status_code=404, detail=api_error("NOT_FOUND", "expense not found"))
        updated = build_expense(body, user["uid"], expense_id=expense_id, created_at=existing["createdAt"])
        app.state.db.expenses.replace_one({"id": expense_id, "uid": user["uid"]}, updated)
        return expense_out(updated)

    @app.delete("/api/v1/expenses/{expense_id}", status_code=204)
    def delete_expense(expense_id: str, user: dict[str, Any] = Depends(current_user)) -> Response:
        result = app.state.db.expenses.delete_one({"id": expense_id, "uid": user["uid"]})
        if result.deleted_count == 0:
            raise HTTPException(status_code=404, detail=api_error("NOT_FOUND", "expense not found"))
        return Response(status_code=204)

    @app.get("/api/v1/expenses-export.csv")
    def export_expenses(
        category: str = "",
        q: str = "",
        from_: str | None = Query(default=None, alias="from"),
        to: str | None = None,
        user: dict[str, Any] = Depends(current_user),
    ) -> PlainTextResponse:
        filters: dict[str, Any] = {"uid": user["uid"]}
        if category.strip():
            filters["category"] = category.strip()
        add_date_filter(filters, from_, to)
        docs = [expense_out(doc) for doc in app.state.db.expenses.find(filters).sort("date", -1)]
        if q.strip():
            needle = q.lower().strip()
            docs = [doc for doc in docs if needle in (doc["description"] + " " + doc["category"]).lower()]
        buf = io.StringIO()
        writer = csv.writer(buf)
        writer.writerow(["id", "date", "category", "description", "amount"])
        for doc in docs:
            writer.writerow([doc["id"], doc["date"], doc["category"], doc["description"], f"{doc['amount']:.2f}"])
        return PlainTextResponse(buf.getvalue(), media_type="text/csv")

    @app.get("/api/v1/analytics")
    def analytics(user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
        docs = list(app.state.db.expenses.find({"uid": user["uid"]}))
        by_category: dict[str, float] = {}
        by_month: dict[str, float] = {}
        total = 0.0
        for doc in docs:
            amount = float(doc.get("amount") or 0)
            total += amount
            by_category[doc.get("category") or "Personal"] = by_category.get(doc.get("category") or "Personal", 0) + amount
            dt = doc.get("date") or now()
            by_month[dt.strftime("%Y-%m")] = by_month.get(dt.strftime("%Y-%m"), 0) + amount
        return {"totalAmount": total, "byCategory": by_category, "byMonth": by_month}

    @app.get("/api/v1/planning/monthly")
    def get_monthly_plan(
        month: str = "",
        user: dict[str, Any] = Depends(current_user),
    ) -> dict[str, Any]:
        plan_month = normalize_month(month)
        return monthly_plan_out(app.state.db, user["uid"], plan_month)

    @app.put("/api/v1/planning/monthly")
    def save_monthly_plan(body: dict[str, Any], user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
        plan_month = normalize_month(str(body.get("month") or ""))
        raw_budgets = body.get("budgets") if isinstance(body.get("budgets"), dict) else {}
        budgets: dict[str, float] = {}
        for category, amount in raw_budgets.items():
            label = str(category).strip()
            if not label:
                continue
            try:
                value = max(0.0, float(amount or 0))
            except (TypeError, ValueError):
                raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", "budget amounts must be numbers")) from None
            budgets[label] = value
        doc = {
            "uid": user["uid"],
            "month": plan_month,
            "currency": str(body.get("currency") or "INR").strip().upper() or "INR",
            "budgets": budgets,
            "updatedAt": now(),
        }
        app.state.db.monthly_plans.update_one(
            {"uid": user["uid"], "month": plan_month},
            {"$set": doc, "$setOnInsert": {"createdAt": now()}},
            upsert=True,
        )
        return monthly_plan_out(app.state.db, user["uid"], plan_month)

    @app.get("/api/v1/dashboard/snapshot")
    def dashboard(user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
        docs = [expense_out(doc) for doc in app.state.db.expenses.find({"uid": user["uid"]}).sort("date", -1).limit(20)]
        return {
            "overallLabel": "You are all settled up",
            "overallAmountText": "INR 0.00",
            "overallPositive": True,
            "friendItems": friend_balance_items(app.state.db, user["uid"]),
            "groupItems": group_balance_items(app.state.db, user["uid"]),
            "activityItems": [
                {"title": doc["description"] or doc["category"], "subtitle": doc["date"], "amountText": f"You spent INR {doc['amount']:.2f}", "positive": False}
                for doc in docs
            ],
            "accountName": user.get("displayName") or "User",
            "accountEmail": user.get("email") or "",
        }

    @app.get("/api/v1/friends")
    def list_friends(user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
        links = list(app.state.db.friendships.find({"uids": user["uid"]}))
        friend_uids = [uid for link in links for uid in link["uids"] if uid != user["uid"]]
        friends = [user_public(doc) for doc in app.state.db.users.find({"uid": {"$in": friend_uids}})]
        return {"friends": friends}

    @app.post("/api/v1/friends/resolve")
    def resolve_friend(body: dict[str, Any], user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
        resolved = resolve_user(app.state.db, str(body.get("emailOrPhone") or ""))
        if not resolved or resolved["uid"] == user["uid"]:
            return {"exists": False}
        return {"exists": True, **user_public(resolved)}

    @app.post("/api/v1/friends/add")
    def add_friend(body: dict[str, Any], user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
        target = resolve_user(app.state.db, str(body.get("emailOrPhone") or ""))
        if not target:
            raise HTTPException(status_code=404, detail=api_error("NOT_FOUND", "user not found"))
        if target["uid"] == user["uid"]:
            raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", "cannot add yourself as friend"))
        pair = sorted([user["uid"], target["uid"]])
        app.state.db.friendships.update_one({"key": "_".join(pair)}, {"$set": {"key": "_".join(pair), "uids": pair, "updatedAt": now()}, "$setOnInsert": {"createdAt": now()}}, upsert=True)
        return {"added": True, "uid": target["uid"]}

    @app.get("/api/v1/friends/balances")
    def friend_balances(user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
        return {"balances": friend_balance_map(app.state.db, user["uid"])}

    @app.post("/api/v1/friends/settlements", status_code=201)
    def create_friend_settlement(body: dict[str, Any], user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
        friend_uid = str(body.get("friendUid") or "").strip()
        if not friend_uid:
            raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", "friendUid is required"))
        if friend_uid == user["uid"]:
            raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", "cannot settle with yourself"))
        friend = app.state.db.users.find_one({"uid": friend_uid})
        if not friend:
            raise HTTPException(status_code=404, detail=api_error("NOT_FOUND", "friend not found"))
        pair = sorted([user["uid"], friend_uid])
        if not app.state.db.friendships.find_one({"key": "_".join(pair)}):
            raise HTTPException(status_code=404, detail=api_error("NOT_FOUND", "friendship not found"))
        direction = str(body.get("direction") or "paid").strip().lower()
        if direction not in {"paid", "received"}:
            raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", "direction must be paid or received"))
        amount = float(body.get("amount") or 0)
        if amount <= 0:
            raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", "amount must be positive"))
        payer_uid = user["uid"] if direction == "paid" else friend_uid
        receiver_uid = friend_uid if direction == "paid" else user["uid"]
        doc = {
            "id": uuid.uuid4().hex,
            "uids": pair,
            "payerUid": payer_uid,
            "receiverUid": receiver_uid,
            "amount": amount,
            "currency": str(body.get("currency") or "INR").strip().upper() or "INR",
            "note": str(body.get("note") or "").strip(),
            "createdBy": user["uid"],
            "createdAt": now(),
        }
        app.state.db.friend_settlements.insert_one(doc)
        return json_ready(friend_settlement_out(doc))

    @app.post("/api/v1/friends/remove")
    def remove_friend(body: dict[str, Any], user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
        target = resolve_user(app.state.db, str(body.get("emailOrPhone") or ""))
        if target:
            pair = sorted([user["uid"], target["uid"]])
            app.state.db.friendships.delete_one({"key": "_".join(pair)})
        return {"removed": True}

    @app.get("/api/v1/groups")
    def list_groups(user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
        groups = [group_out(app.state.db, doc) for doc in app.state.db.groups.find({"memberUids": user["uid"]}).sort("name", ASCENDING)]
        return {"groups": groups}

    @app.post("/api/v1/groups", status_code=201)
    def create_group(body: dict[str, Any], user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
        require_json(body, "name")
        members = [user["uid"]]
        for contact in body.get("members") or []:
            resolved = resolve_user(app.state.db, str(contact))
            if resolved and resolved["uid"] not in members:
                members.append(resolved["uid"])
        doc = {
            "id": uuid.uuid4().hex,
            "name": str(body["name"]).strip(),
            "groupType": str(body.get("groupType") or "split"),
            "createdBy": user["uid"],
            "memberUids": members,
            "memberRoles": {user["uid"]: normalize_family_role(body.get("ownerRole") or "")},
            "memberCount": len(members),
            "createdAt": now(),
            "updatedAt": now(),
        }
        app.state.db.groups.insert_one(doc)
        return group_out(app.state.db, doc)

    @app.api_route("/api/v1/groups/{group_id}/{path:path}", methods=["GET", "POST", "PUT", "DELETE"])
    async def group_detail(group_id: str, path: str, request: Request, background_tasks: BackgroundTasks, user: dict[str, Any] = Depends(current_user)) -> Any:
        group = require_group_member(app.state.db, group_id, user["uid"])
        parts = [part for part in path.split("/") if part]
        if parts == ["leave"] and request.method == "POST":
            members = [uid for uid in group["memberUids"] if uid != user["uid"]]
            if not members:
                app.state.db.groups.delete_one({"id": group_id})
                app.state.db.group_expenses.delete_many({"groupId": group_id})
                return {"left": True, "deleted": True}
            app.state.db.groups.update_one({"id": group_id}, {"$set": {"memberUids": members, "memberCount": len(members), "updatedAt": now()}, "$unset": {f"memberRoles.{user['uid']}": ""}})
            return {"left": True, "deleted": False}
        if parts == ["members"] and request.method == "GET":
            users = list(app.state.db.users.find({"uid": {"$in": group["memberUids"]}}))
            roles = group.get("memberRoles") if isinstance(group.get("memberRoles"), dict) else {}
            return {"members": [member_out(uid, users, roles.get(uid, "")) for uid in group["memberUids"]]}
        if parts == ["members", "add"] and request.method == "POST":
            body = await request.json()
            resolved = resolve_user(app.state.db, str(body.get("emailOrPhone") or ""))
            if not resolved:
                raise HTTPException(status_code=404, detail=api_error("NOT_FOUND", "member not found"))
            role = normalize_family_role(body.get("role") or "")
            if resolved["uid"] not in group["memberUids"]:
                app.state.db.groups.update_one({"id": group_id}, {"$addToSet": {"memberUids": resolved["uid"]}, "$set": {f"memberRoles.{resolved['uid']}": role, "updatedAt": now()}})
            elif role:
                app.state.db.groups.update_one({"id": group_id}, {"$set": {f"memberRoles.{resolved['uid']}": role, "updatedAt": now()}})
            updated = app.state.db.groups.find_one({"id": group_id})
            updated["memberCount"] = len(updated.get("memberUids") or [])
            app.state.db.groups.update_one({"id": group_id}, {"$set": {"memberCount": updated["memberCount"]}})
            return group_out(app.state.db, updated)
        if len(parts) == 3 and parts[0] == "members" and parts[2] == "role" and request.method == "PUT":
            body = await request.json()
            member_uid = parts[1]
            if member_uid not in group.get("memberUids", []):
                raise HTTPException(status_code=404, detail=api_error("NOT_FOUND", "member not found"))
            role = normalize_family_role(body.get("role") or "")
            app.state.db.groups.update_one({"id": group_id}, {"$set": {f"memberRoles.{member_uid}": role, "updatedAt": now()}})
            updated = app.state.db.groups.find_one({"id": group_id})
            users = list(app.state.db.users.find({"uid": {"$in": updated["memberUids"]}}))
            roles = updated.get("memberRoles") if isinstance(updated.get("memberRoles"), dict) else {}
            return member_out(member_uid, users, roles.get(member_uid, ""))
        if parts == ["expenses"] and request.method == "GET":
            return {"expenses": [group_expense_out(doc) for doc in app.state.db.group_expenses.find({"groupId": group_id}).sort("date", -1)]}
        if parts == ["expenses"] and request.method == "POST":
            body = await request.json()
            doc = build_group_expense(body, group, app.state.db, user["uid"])
            app.state.db.group_expenses.insert_one(doc)
            touch_group(app.state.db, group_id)
            return JSONResponse(status_code=201, content=json_ready(group_expense_out(doc)))
        if len(parts) == 2 and parts[0] == "expenses" and request.method == "PUT":
            body = await request.json()
            existing = app.state.db.group_expenses.find_one({"groupId": group_id, "id": parts[1]})
            if not existing:
                raise HTTPException(status_code=404, detail=api_error("NOT_FOUND", "group or expense not found"))
            updated = build_group_expense(body, group, app.state.db, user["uid"], expense_id=parts[1], created_by=existing["createdBy"], created_at=existing["createdAt"])
            app.state.db.group_expenses.replace_one({"groupId": group_id, "id": parts[1]}, updated)
            touch_group(app.state.db, group_id)
            return group_expense_out(updated)
        if len(parts) == 2 and parts[0] == "expenses" and request.method == "DELETE":
            app.state.db.group_expenses.delete_one({"groupId": group_id, "id": parts[1]})
            touch_group(app.state.db, group_id)
            return Response(status_code=204)
        if parts == ["attachments"] and request.method == "POST":
            form = await request.form()
            file = form.get("file")
            expense_id = str(form.get("expenseId") or "")
            if not expense_id or not hasattr(file, "filename") or not hasattr(file, "read"):
                raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", "file and expenseId are required"))
            if not app.state.db.group_expenses.find_one({"groupId": group_id, "id": expense_id}):
                raise HTTPException(status_code=404, detail=api_error("NOT_FOUND", "expense not found"))
            url = await save_upload(app, file, f"groups/{group_id}/{expense_id}")
            app.state.db.group_expenses.update_one({"groupId": group_id, "id": expense_id}, {"$addToSet": {"attachments": url}, "$set": {"updatedBy": user["uid"], "updatedAt": now()}})
            return JSONResponse(status_code=201, content={"url": url})
        if len(parts) == 4 and parts[0] == "expenses" and parts[2:] == ["attachments", "preview"] and request.method == "GET":
            attachment_url = request.query_params.get("url") or ""
            expense = app.state.db.group_expenses.find_one({"groupId": group_id, "id": parts[1], "attachments": attachment_url})
            if not expense:
                raise HTTPException(status_code=403, detail=api_error("FORBIDDEN", "attachment not found for expense"))
            path = upload_path_from_url(app, attachment_url)
            return FileResponse(path)
        raise HTTPException(status_code=404, detail=api_error("NOT_FOUND", "route not found"))

    @app.get("/api/v1/recurring/templates")
    def recurring_templates(user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
        return {"templates": [json_ready(doc) for doc in app.state.db.recurring_templates.find({"uid": user["uid"]})]}

    @app.post("/api/v1/recurring/templates", status_code=201)
    def create_recurring(body: dict[str, Any], user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
        require_json(body, "title", "category", "frequency", "startDate")
        frequency = str(body["frequency"]).strip().lower()
        if frequency not in {"daily", "weekly", "monthly"}:
            raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", "frequency must be daily, weekly or monthly"))
        kind = str(body.get("kind") or "expense").strip().lower()
        if kind not in {"expense", "income"}:
            raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", "kind must be expense or income"))
        amount = float(body.get("amount") or body.get("expectedAmount") or 0)
        if amount <= 0:
            raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", "amount must be positive"))
        start = parse_dt(str(body["startDate"]))
        day_of_month = int(body.get("dayOfMonth") or start.day)
        if day_of_month < 1 or day_of_month > 31:
            raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", "dayOfMonth must be between 1 and 31"))
        doc = {
            "id": uuid.uuid4().hex,
            "uid": user["uid"],
            "title": str(body["title"]).strip(),
            "kind": kind,
            "amount": amount,
            "expectedAmount": amount,
            "currency": str(body.get("currency") or "INR").strip().upper() or "INR",
            "category": str(body["category"]).strip(),
            "frequency": frequency,
            "dayOfMonth": day_of_month,
            "startDate": start,
            "nextDueDate": recurring_due_date_for_month(
                {"startDate": start, "dayOfMonth": day_of_month, "frequency": frequency},
                max(current_month(), f"{start.year:04d}-{start.month:02d}"),
            ),
            "active": True,
            "createdAt": now(),
            "updatedAt": now(),
        }
        app.state.db.recurring_templates.insert_one(doc)
        ensure_recurring_occurrences(app.state.db, user["uid"], current_month())
        return json_ready(doc)

    @app.get("/api/v1/recurring/occurrences")
    def recurring_occurrences(month: str = Query(default=""), user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
        period = normalize_month(month)
        ensure_recurring_occurrences(app.state.db, user["uid"], period)
        docs = app.state.db.recurring_occurrences.find({"uid": user["uid"], "period": period}).sort("dueDate", ASCENDING)
        return {"occurrences": [recurring_occurrence_out(doc) for doc in docs]}

    @app.post("/api/v1/recurring/occurrences/{occurrence_id}/confirm")
    def confirm_recurring_occurrence(occurrence_id: str, body: dict[str, Any], user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
        occurrence = app.state.db.recurring_occurrences.find_one({"id": occurrence_id, "uid": user["uid"]})
        if not occurrence:
            raise HTTPException(status_code=404, detail=api_error("NOT_FOUND", "recurring occurrence not found"))
        actual_amount = float(body.get("actualAmount") or 0)
        if actual_amount <= 0:
            raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", "actualAmount must be positive"))
        actual_date = parse_dt(str(body.get("actualDate") or iso(occurrence.get("dueDate") or now())))
        updates: dict[str, Any] = {
            "actualAmount": actual_amount,
            "actualDate": actual_date,
            "status": "confirmed",
            "updatedAt": now(),
        }
        if "notes" in body:
            updates["notes"] = str(body.get("notes") or "").strip()
        if occurrence.get("kind") == "expense":
            expense_body = {
                "amount": actual_amount,
                "currency": occurrence.get("currency") or "INR",
                "category": occurrence.get("category") or "Personal",
                "description": f"Recurring: {occurrence.get('title') or 'Payment'}",
                "date": iso(actual_date),
                "paymentMethod": body.get("paymentMethod") or "recurring",
            }
            existing_expense = None
            if occurrence.get("expenseId"):
                existing_expense = app.state.db.expenses.find_one({"id": occurrence["expenseId"], "uid": user["uid"]})
            expense = build_expense(
                expense_body,
                user["uid"],
                expense_id=(existing_expense or {}).get("id") or uuid.uuid4().hex,
                created_at=(existing_expense or {}).get("createdAt"),
            )
            app.state.db.expenses.replace_one({"id": expense["id"], "uid": user["uid"]}, expense, upsert=True)
            updates["expenseId"] = expense["id"]
        app.state.db.recurring_occurrences.update_one({"id": occurrence_id, "uid": user["uid"]}, {"$set": updates})
        updated = app.state.db.recurring_occurrences.find_one({"id": occurrence_id, "uid": user["uid"]})
        return recurring_occurrence_out(updated)

    @app.post("/api/v1/recurring/process-due")
    def process_due(user: dict[str, Any] = Depends(current_user)) -> dict[str, int]:
        return {"created": ensure_recurring_occurrences(app.state.db, user["uid"], current_month())}

    @app.post("/api/v1/bills", status_code=201)
    async def upload_bill(background_tasks: BackgroundTasks, file: UploadFile = File(...), user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
        url = await save_upload(app, file, f"bills/{user['uid']}")
        job = {"id": uuid.uuid4().hex, "uid": user["uid"], "status": "queued", "fileUrl": url, "fileName": file.filename or "bill", "createdAt": now(), "updatedAt": now()}
        app.state.db.ai_jobs.insert_one(job)
        background_tasks.add_task(run_bill_extraction, app, job["id"])
        return json_ready(job)

    @app.get("/api/v1/bills/{job_id}")
    def bill_job(job_id: str, user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
        job = app.state.db.ai_jobs.find_one({"id": job_id, "uid": user["uid"]})
        if not job:
            raise HTTPException(status_code=404, detail=api_error("NOT_FOUND", "bill job not found"))
        return json_ready(job)

    @app.post("/api/v1/bills/{job_id}/create-expense", status_code=201)
    def bill_to_expense(job_id: str, body: dict[str, Any] | None = None, user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
        job = app.state.db.ai_jobs.find_one({"id": job_id, "uid": user["uid"]})
        if not job or not job.get("result"):
            raise HTTPException(status_code=404, detail=api_error("NOT_FOUND", "bill extraction not found"))
        result = {**job["result"], **(body or {})}
        expense = build_expense(
            {
                "amount": result.get("amount") or 0,
                "category": result.get("category") or "Personal",
                "description": result.get("merchant") or result.get("notes") or "Bill",
                "date": result.get("date") or iso(now()),
            },
            user["uid"],
        )
        app.state.db.expenses.insert_one(expense)
        app.state.db.ai_jobs.update_one({"id": job_id}, {"$set": {"expenseId": expense["id"], "updatedAt": now()}})
        return expense_out(expense)

    @app.post("/api/v1/ai/summaries/{period}")
    def generate_summary(period: str, user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
        if period not in {"daily", "monthly"}:
            raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", "period must be daily or monthly"))
        docs = list(app.state.db.expenses.find({"uid": user["uid"]}))
        total = sum(float(doc.get("amount") or 0) for doc in docs)
        summary = {
            "id": uuid.uuid4().hex,
            "uid": user["uid"],
            "period": period,
            "summary": f"{period.title()} total: INR {total:.2f} across {len(docs)} expenses.",
            "suggestions": ["Review uncategorized expenses."] if docs else ["Add your first expense to unlock summaries."],
            "createdAt": now(),
        }
        app.state.db.ai_suggestions.insert_one(summary)
        return json_ready(summary)

    @app.get("/uploads/{path:path}")
    def serve_upload(path: str) -> FileResponse:
        full = (upload_dir / path).resolve()
        if upload_dir.resolve() not in full.parents and full != upload_dir.resolve():
            raise HTTPException(status_code=403, detail=api_error("FORBIDDEN", "invalid upload path"))
        if not full.exists():
            raise HTTPException(status_code=404, detail=api_error("NOT_FOUND", "upload not found"))
        return FileResponse(full)

    frontend_dist = Path(os.getenv("FRONTEND_DIST", str(ROOT.parent / "frontend" / "build" / "web")))
    if frontend_dist.exists():
        app.mount("/assets", StaticFiles(directory=frontend_dist / "assets"), name="assets")

        @app.get("/{path:path}")
        def serve_flutter(path: str) -> FileResponse:
            target = (frontend_dist / path).resolve()
            if target.exists() and frontend_dist.resolve() in target.parents:
                return FileResponse(target)
            return FileResponse(frontend_dist / "index.html")

    return app


def ensure_indexes(db: Any) -> None:
    db.users.create_index("emailNormalized", unique=True)
    db.users.create_index("uid", unique=True)
    db.sessions.create_index("tokenHash", unique=True)
    db.sessions.create_index("expiresAt")
    db.expenses.create_index([("uid", ASCENDING), ("date", ASCENDING)])
    db.monthly_plans.create_index([("uid", ASCENDING), ("month", ASCENDING)], unique=True)
    db.friendships.create_index("key", unique=True)
    db.friend_settlements.create_index([("uids", ASCENDING), ("createdAt", ASCENDING)])
    db.groups.create_index("memberUids")
    db.group_expenses.create_index([("groupId", ASCENDING), ("date", ASCENDING)])
    db.ai_jobs.create_index([("uid", ASCENDING), ("createdAt", ASCENDING)])
    db.recurring_templates.create_index([("uid", ASCENDING), ("active", ASCENDING)])
    db.recurring_occurrences.create_index([("uid", ASCENDING), ("period", ASCENDING)])
    db.recurring_occurrences.create_index([("uid", ASCENDING), ("templateId", ASCENDING), ("period", ASCENDING)], unique=True)


def create_user_doc(uid: str, email: str, display_name: str, password_hash: str) -> dict[str, Any]:
    current = now()
    return {
        "uid": uid,
        "email": email,
        "emailNormalized": normalize_email(email),
        "displayName": display_name.strip() or "User",
        "photoUrl": None,
        "phone": "",
        "passwordHash": password_hash,
        "createdAt": current,
        "updatedAt": current,
    }


def create_session(db: Any, uid: str) -> str:
    token = secrets.token_urlsafe(32)
    db.sessions.insert_one({"uid": uid, "tokenHash": token_hash(token), "createdAt": now(), "expiresAt": now() + timedelta(days=30)})
    return token


def build_expense(body: dict[str, Any], uid: str, expense_id: str | None = None, created_at: datetime | None = None) -> dict[str, Any]:
    amount = float(body.get("amount") or 0)
    if amount <= 0:
        raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", "amount must be positive"))
    current = now()
    return {
        "id": expense_id or uuid.uuid4().hex,
        "uid": uid,
        "amount": amount,
        "currency": str(body.get("currency") or "INR").strip().upper() or "INR",
        "category": str(body.get("category") or "Personal").strip() or "Personal",
        "description": str(body.get("description") or "").strip(),
        "paymentMethod": str(body.get("paymentMethod") or "cash").strip() or "cash",
        "date": parse_dt(str(body.get("date") or iso(current))),
        "createdAt": created_at or current,
        "updatedAt": current,
    }


def expense_out(doc: dict[str, Any]) -> dict[str, Any]:
    return json_ready({
        key: doc.get(key)
        for key in [
            "id",
            "amount",
            "currency",
            "category",
            "description",
            "paymentMethod",
            "date",
            "createdAt",
            "updatedAt",
        ]
    })


def normalize_month(value: str) -> str:
    raw = value.strip()
    if not raw:
        current = now()
        return f"{current.year:04d}-{current.month:02d}"
    if not re.fullmatch(r"\d{4}-\d{2}", raw):
        raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", "month must be YYYY-MM"))
    year, month_number = [int(part) for part in raw.split("-")]
    if month_number < 1 or month_number > 12:
        raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", "month must be YYYY-MM"))
    return f"{year:04d}-{month_number:02d}"


def current_month() -> str:
    current = now()
    return f"{current.year:04d}-{current.month:02d}"


def month_range(month: str) -> tuple[datetime, datetime]:
    year, month_number = [int(part) for part in month.split("-")]
    start = datetime(year, month_number, 1, tzinfo=UTC)
    if month_number == 12:
        end = datetime(year + 1, 1, 1, tzinfo=UTC)
    else:
        end = datetime(year, month_number + 1, 1, tzinfo=UTC)
    return start, end


def recurring_due_date_for_month(template: dict[str, Any], month: str) -> datetime:
    year, month_number = [int(part) for part in month.split("-")]
    frequency = str(template.get("frequency") or "monthly").lower()
    start = aware(template.get("startDate") or now())
    if frequency != "monthly":
        return next_due(start, frequency)
    last_day = calendar.monthrange(year, month_number)[1]
    day = int(template.get("dayOfMonth") or start.day)
    return datetime(year, month_number, min(day, last_day), tzinfo=UTC)


def ensure_recurring_occurrences(db: Any, uid: str, month: str) -> int:
    period = normalize_month(month)
    start, end = month_range(period)
    created = 0
    for template in db.recurring_templates.find({"uid": uid, "active": True}):
        template_start = aware(template.get("startDate") or start)
        if template_start >= end:
            continue
        due_date = recurring_due_date_for_month(template, period)
        if due_date < start or due_date >= end or due_date < template_start:
            continue
        doc = {
            "id": uuid.uuid4().hex,
            "uid": uid,
            "templateId": template["id"],
            "period": period,
            "kind": template.get("kind") or "expense",
            "title": template.get("title") or "Recurring item",
            "category": template.get("category") or "Personal",
            "currency": template.get("currency") or "INR",
            "expectedAmount": float(template.get("expectedAmount") or template.get("amount") or 0),
            "actualAmount": None,
            "actualDate": None,
            "dueDate": due_date,
            "status": "expected",
            "notes": "",
            "createdAt": now(),
            "updatedAt": now(),
        }
        result = db.recurring_occurrences.update_one(
            {"uid": uid, "templateId": template["id"], "period": period},
            {"$setOnInsert": doc},
            upsert=True,
        )
        if getattr(result, "upserted_id", None) is not None:
            created += 1
    return created


def recurring_occurrence_out(doc: dict[str, Any] | None) -> dict[str, Any]:
    return json_ready(doc or {})


def monthly_plan_out(db: Any, uid: str, month: str) -> dict[str, Any]:
    plan = db.monthly_plans.find_one({"uid": uid, "month": month}) or {}
    raw_budgets = plan.get("budgets") if isinstance(plan.get("budgets"), dict) else {}
    budgets = {str(key): float(value or 0) for key, value in raw_budgets.items()}
    start, end = month_range(month)
    expenses = db.expenses.find({"uid": uid, "date": {"$gte": start, "$lt": end}})
    actuals: dict[str, float] = {}
    for expense in expenses:
        category = str(expense.get("category") or "Personal").strip() or "Personal"
        actuals[category] = actuals.get(category, 0.0) + float(expense.get("amount") or 0)
    family_groups = list(db.groups.find({"memberUids": uid, "groupType": "family"}))
    family_group_ids = [group.get("id") for group in family_groups if group.get("id")]
    if family_group_ids:
        family_expenses = db.group_expenses.find({
            "groupId": {"$in": family_group_ids},
            "date": {"$gte": start, "$lt": end},
        })
        for expense in family_expenses:
            category = str(expense.get("category") or "Personal").strip() or "Personal"
            actuals[category] = actuals.get(category, 0.0) + float(expense.get("amount") or 0)
    rows = []
    for category in sorted(set(budgets.keys()) | set(actuals.keys())):
        budget = budgets.get(category, 0.0)
        actual = actuals.get(category, 0.0)
        rows.append({
            "category": category,
            "budget": budget,
            "actual": actual,
            "remaining": budget - actual,
            "progress": 0 if budget <= 0 else min(actual / budget, 1.5),
            "overBudget": budget > 0 and actual > budget,
        })
    total_budget = sum(budgets.values())
    total_actual = sum(actuals.values())
    return json_ready({
        "month": month,
        "currency": plan.get("currency") or "INR",
        "totalBudget": total_budget,
        "totalActual": total_actual,
        "totalRemaining": total_budget - total_actual,
        "categories": rows,
        "updatedAt": plan.get("updatedAt"),
    })


def friend_settlement_out(doc: dict[str, Any]) -> dict[str, Any]:
    return json_ready({
        key: doc.get(key)
        for key in [
            "id",
            "uids",
            "payerUid",
            "receiverUid",
            "amount",
            "currency",
            "note",
            "createdBy",
            "createdAt",
        ]
    })


def friend_balance_map(db: Any, uid: str) -> dict[str, float]:
    balances: dict[str, float] = {}
    for settlement in db.friend_settlements.find({"uids": uid}):
        payer_uid = settlement.get("payerUid")
        receiver_uid = settlement.get("receiverUid")
        amount = float(settlement.get("amount") or 0)
        if payer_uid == uid and receiver_uid:
            balances[receiver_uid] = balances.get(receiver_uid, 0.0) + amount
        elif receiver_uid == uid and payer_uid:
            balances[payer_uid] = balances.get(payer_uid, 0.0) - amount
    return balances


def friend_balance_items(db: Any, uid: str) -> list[dict[str, Any]]:
    balances = friend_balance_map(db, uid)
    if not balances:
        return []
    users = {doc["uid"]: doc for doc in db.users.find({"uid": {"$in": list(balances.keys())}})}
    items = []
    for friend_uid, amount in sorted(balances.items(), key=lambda item: abs(item[1]), reverse=True):
        if abs(amount) <= 0.005:
            continue
        friend = users.get(friend_uid, {"uid": friend_uid, "displayName": "Friend", "email": ""})
        label = user_public(friend)["displayName"]
        items.append({
            "title": label,
            "subtitle": "owes you" if amount > 0 else "you owe",
            "amountText": f"INR {abs(amount):.2f}",
            "positive": amount > 0,
        })
    return items


def group_balance_items(db: Any, uid: str) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    groups = db.groups.find({"memberUids": uid, "groupType": {"$ne": "family"}}).sort("updatedAt", -1)
    for group in groups:
        expenses = list(db.group_expenses.find({"groupId": group["id"]}))
        if not expenses:
            continue
        member_uids = group.get("memberUids", [])
        users = list(db.users.find({"uid": {"$in": member_uids}}))
        display_data = compute_display_data(member_uids, expenses, group_member_aliases(member_uids, users))
        member_balance = display_data.get("memberBalances", {}).get(uid, {})
        amount = float(member_balance.get("net") or 0)
        if abs(amount) <= 0.005:
            subtitle = "settled up"
        else:
            subtitle = "you are owed" if amount > 0 else "you owe"
        items.append({
            "title": group.get("name") or "Group",
            "subtitle": subtitle,
            "amountText": f"INR {abs(amount):.2f}",
            "positive": amount >= 0,
        })
    return items[:5]


def add_date_filter(filters: dict[str, Any], from_value: str | None, to_value: str | None) -> None:
    date_filter: dict[str, Any] = {}
    if from_value:
        date_filter["$gte"] = parse_dt(from_value)
    if to_value:
        date_filter["$lte"] = parse_dt(to_value)
    if date_filter:
        filters["date"] = date_filter


def resolve_user(db: Any, email_or_phone: str) -> dict[str, Any] | None:
    query = email_or_phone.strip().lower()
    if not query:
        return None
    if "@" in query:
        return db.users.find_one({"emailNormalized": query})
    return db.users.find_one({"phone": query})


def require_group_member(db: Any, group_id: str, uid: str) -> dict[str, Any]:
    group = db.groups.find_one({"id": group_id})
    if not group:
        raise HTTPException(status_code=404, detail=api_error("NOT_FOUND", "group not found"))
    if uid not in group.get("memberUids", []):
        raise HTTPException(status_code=403, detail=api_error("FORBIDDEN", "you are not a group member"))
    return group


def group_out(db: Any, group: dict[str, Any]) -> dict[str, Any]:
    expenses = list(db.group_expenses.find({"groupId": group["id"]}))
    member_uids = group.get("memberUids", [])
    users = list(db.users.find({"uid": {"$in": member_uids}}))
    display_data = compute_display_data(member_uids, expenses, group_member_aliases(member_uids, users))
    return json_ready({**group, "memberCount": len(group.get("memberUids", [])), "displayData": display_data})


def group_member_aliases(member_uids: list[str], users: list[dict[str, Any]]) -> dict[str, str]:
    aliases: dict[str, str] = {}
    users_by_uid = {user.get("uid"): user for user in users}
    for uid in member_uids:
        user = users_by_uid.get(uid, {})
        for value in [uid, user.get("displayName"), user.get("email"), user.get("phone")]:
            key = str(value or "").strip().lower()
            if key:
                aliases[key] = uid
    return aliases


def normalize_group_member_ref(raw: Any, member_uids: list[str], aliases: dict[str, str]) -> str | None:
    value = str(raw or "").strip()
    if not value:
        return None
    if value in member_uids:
        return value
    return aliases.get(value.lower())


def compute_display_data(
    member_uids: list[str],
    expenses: list[dict[str, Any]],
    aliases: dict[str, str] | None = None,
) -> dict[str, Any]:
    aliases = aliases or {}
    balances = {uid: {"owes": 0.0, "owed": 0.0, "net": 0.0} for uid in member_uids}
    member_set = set(member_uids)
    total = 0.0
    attachments = 0
    for expense in expenses:
        amount = float(expense.get("amount") or 0)
        total += amount
        split_with = [
            uid
            for uid in (normalize_group_member_ref(item, member_uids, aliases) for item in (expense.get("splitWith") or []))
            if uid in member_set
        ] or member_uids
        share = amount / max(len(split_with), 1)
        paid_by = normalize_group_member_ref(expense.get("paidBy") or expense.get("createdBy"), member_uids, aliases)
        attachments += len(expense.get("attachments") or [])
        if not paid_by:
            continue
        for uid in split_with:
            balances.setdefault(uid, {"owes": 0.0, "owed": 0.0, "net": 0.0})
            if uid != paid_by:
                balances[uid]["owes"] += share
                balances[uid]["net"] -= share
                balances.setdefault(paid_by, {"owes": 0.0, "owed": 0.0, "net": 0.0})
                balances[paid_by]["owed"] += share
                balances[paid_by]["net"] += share
    return {"expenseCount": len(expenses), "totalSpend": total, "totalAttachments": attachments, "attachmentCounts": {}, "memberBalances": balances, "updatedAt": iso(now())}


def normalize_family_role(value: Any) -> str:
    role = str(value or "").strip()
    return role[:40]


def member_out(uid: str, users: list[dict[str, Any]], role: str = "") -> dict[str, Any]:
    user = next((item for item in users if item.get("uid") == uid), None)
    if not user:
        return {"uid": uid, "displayName": uid, "email": "", "phone": "", "role": normalize_family_role(role)}
    return {
        "uid": uid,
        "displayName": user.get("displayName") or uid,
        "email": user.get("email") or "",
        "phone": user.get("phone") or "",
        "role": normalize_family_role(role),
    }


def build_group_expense(
    body: dict[str, Any],
    group: dict[str, Any],
    db: Any,
    uid: str,
    expense_id: str | None = None,
    created_by: str | None = None,
    created_at: datetime | None = None,
) -> dict[str, Any]:
    amount = float(body.get("amount") or 0)
    description = str(body.get("description") or "").strip()
    if amount <= 0 or not description:
        raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", "description and positive amount required"))
    current = now()
    split_mode = str(body.get("splitMode") or "equally").strip().lower()
    if split_mode not in {"equally", "custom"}:
        split_mode = "equally"
    member_uids = [str(item) for item in group.get("memberUids", []) if str(item)]
    aliases = group_member_aliases(member_uids, list(db.users.find({"uid": {"$in": member_uids}})))
    paid_by = normalize_group_member_ref(body.get("paidBy") or uid, member_uids, aliases)
    if not paid_by:
        raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", "paidBy must be a group member"))
    raw_split_with = body.get("splitWith") or member_uids
    split_with: list[str] = []
    for item in raw_split_with:
        member_uid = normalize_group_member_ref(item, member_uids, aliases)
        if not member_uid:
            raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", "splitWith must contain only group members"))
        if member_uid not in split_with:
            split_with.append(member_uid)
    if not split_with:
        split_with = member_uids
    return {
        "id": expense_id or str(body.get("id") or "").strip() or uuid.uuid4().hex,
        "groupId": group["id"],
        "createdBy": created_by or uid,
        "updatedBy": uid,
        "paidBy": paid_by,
        "splitMode": split_mode,
        "splitWith": split_with,
        "amount": amount,
        "category": str(body.get("category") or "").strip(),
        "description": description,
        "attachments": [str(item).strip() for item in body.get("attachments") or [] if str(item).strip()],
        "date": parse_dt(str(body.get("date") or iso(current))),
        "createdAt": created_at or current,
        "updatedAt": current,
    }


def group_expense_out(doc: dict[str, Any]) -> dict[str, Any]:
    return json_ready(doc)


def touch_group(db: Any, group_id: str) -> None:
    group = db.groups.find_one({"id": group_id})
    if group:
        db.groups.update_one({"id": group_id}, {"$set": {"updatedAt": now(), "memberCount": len(group.get("memberUids") or [])}})


def next_due(start: datetime, frequency: str) -> datetime:
    if frequency == "daily":
        return start + timedelta(days=1)
    if frequency == "weekly":
        return start + timedelta(days=7)
    month = start.month + 1
    year = start.year + (month - 1) // 12
    month = ((month - 1) % 12) + 1
    day = min(start.day, 28)
    return start.replace(year=year, month=month, day=day)


async def save_upload(app: FastAPI, file: UploadFile, prefix: str) -> str:
    safe_name = re.sub(r"[^A-Za-z0-9._-]+", "_", file.filename or "upload.bin")
    rel = Path(prefix) / f"{uuid.uuid4().hex}_{safe_name}"
    target = app.state.upload_dir / rel
    target.parent.mkdir(parents=True, exist_ok=True)
    with target.open("wb") as out:
        shutil.copyfileobj(file.file, out)
    return "/uploads/" + rel.as_posix()


def upload_path_from_url(app: FastAPI, url: str) -> Path:
    if not url.startswith("/uploads/"):
        raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", "unsupported attachment url"))
    full = (app.state.upload_dir / url.removeprefix("/uploads/")).resolve()
    if not full.exists():
        raise HTTPException(status_code=404, detail=api_error("NOT_FOUND", "attachment not found"))
    return full


async def run_bill_extraction(app: FastAPI, job_id: str) -> None:
    job = app.state.db.ai_jobs.find_one({"id": job_id})
    if not job:
        return
    app.state.db.ai_jobs.update_one({"id": job_id}, {"$set": {"status": "processing", "updatedAt": now()}})
    try:
        file_path = upload_path_from_url(app, job["fileUrl"])
        result = await app.state.ai_provider.extract(file_path, job.get("fileName") or "bill")
        app.state.db.ai_jobs.update_one({"id": job_id}, {"$set": {"status": "completed", "result": result, "updatedAt": now()}})
    except Exception as exc:
        app.state.db.ai_jobs.update_one({"id": job_id}, {"$set": {"status": "failed", "error": str(exc), "updatedAt": now()}})


app = create_app()
