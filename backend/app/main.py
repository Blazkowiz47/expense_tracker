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
from pymongo import ASCENDING, DESCENDING, MongoClient


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


def normalize_currency(value: Any, default: str = "INR") -> str:
    currency = str(value or default).strip().upper()
    if not re.fullmatch(r"[A-Z]{3}", currency):
        raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", "currency must be a 3-letter ISO code"))
    return currency


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

    @app.get("/api/v1/sync/freshness")
    def sync_freshness(
        since: str | None = None,
        sections: str = "",
        user: dict[str, Any] = Depends(current_user),
    ) -> dict[str, Any]:
        since_dt = parse_dt(since) if since else None
        server_time = now()
        section_names = parse_freshness_sections(sections)
        return {
            "serverTime": iso(server_time),
            "sections": {
                section: freshness_section_payload(
                    app.state.db,
                    user["uid"],
                    section,
                    since_dt,
                    server_time,
                )
                for section in section_names
            },
        }

    @app.get("/api/v1/activity")
    def activity_feed(
        since: str | None = None,
        before: str | None = None,
        limit: int = Query(default=80, ge=1, le=200),
        include: str = "personal,group,settlements,recurring",
        user: dict[str, Any] = Depends(current_user),
    ) -> dict[str, Any]:
        since_dt = parse_dt(since) if since else None
        before_dt = parse_dt(before) if before else None
        server_time = now()
        include_sections = parse_activity_include(include)
        feed = activity_feed_entries(
            app.state.db,
            user["uid"],
            since_dt,
            before_dt,
            limit,
            include_sections,
        )
        return {
            "serverTime": iso(server_time),
            **feed,
            "tombstones": activity_tombstones_since(app.state.db, user["uid"], since_dt),
        }

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
        accepted_invites = accept_pending_group_invites(app.state.db, user)
        token = create_session(app.state.db, uid)
        return {"token": token, "user": user_public(user), "acceptedGroupInvites": accepted_invites}

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
        existing = app.state.db.expenses.find_one({"id": expense_id, "uid": user["uid"]})
        if not existing:
            raise HTTPException(status_code=404, detail=api_error("NOT_FOUND", "expense not found"))
        record_expense_tombstone(app.state.db, existing, user["uid"])
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
        writer.writerow(["id", "date", "category", "description", "amount", "currency"])
        for doc in docs:
            writer.writerow([
                doc["id"],
                doc["date"],
                doc["category"],
                doc["description"],
                f"{doc['amount']:.2f}",
                doc.get("currency") or "INR",
            ])
        return PlainTextResponse(buf.getvalue(), media_type="text/csv")

    @app.get("/api/v1/analytics")
    def analytics(user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
        docs = list(app.state.db.expenses.find({"uid": user["uid"]}))
        by_category: dict[str, float] = {}
        by_category_by_currency: dict[str, dict[str, float]] = {}
        by_month: dict[str, float] = {}
        by_month_by_currency: dict[str, dict[str, float]] = {}
        total = 0.0
        total_by_currency: dict[str, float] = {}
        for doc in docs:
            amount = float(doc.get("amount") or 0)
            currency = safe_currency(doc.get("currency"), "INR") or "INR"
            category = doc.get("category") or "Personal"
            total += amount
            total_by_currency[currency] = total_by_currency.get(currency, 0.0) + amount
            by_category[category] = by_category.get(category, 0) + amount
            category_totals = by_category_by_currency.setdefault(category, {})
            category_totals[currency] = category_totals.get(currency, 0.0) + amount
            dt = doc.get("date") or now()
            month = dt.strftime("%Y-%m")
            by_month[month] = by_month.get(month, 0) + amount
            month_totals = by_month_by_currency.setdefault(month, {})
            month_totals[currency] = month_totals.get(currency, 0.0) + amount
        return {
            "totalAmount": total,
            "totalAmountByCurrency": total_by_currency,
            "byCategory": by_category,
            "byCategoryByCurrency": by_category_by_currency,
            "byMonth": by_month,
            "byMonthByCurrency": by_month_by_currency,
        }

    @app.get("/api/v1/planning/monthly")
    def get_monthly_plan(
        month: str = "",
        groupId: str = "",
        user: dict[str, Any] = Depends(current_user),
    ) -> dict[str, Any]:
        plan_month = normalize_month(month)
        owner_uid, group_id = monthly_plan_scope(app.state.db, user["uid"], groupId)
        return monthly_plan_out(app.state.db, owner_uid, plan_month, group_id=group_id)

    @app.put("/api/v1/planning/monthly")
    def save_monthly_plan(body: dict[str, Any], user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
        plan_month = normalize_month(str(body.get("month") or ""))
        owner_uid, group_id = monthly_plan_scope(app.state.db, user["uid"], body.get("groupId"))
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
            "uid": owner_uid,
            "month": plan_month,
            "scope": "group" if group_id else "personal",
            "groupId": group_id,
            "currency": str(body.get("currency") or "INR").strip().upper() or "INR",
            "budgets": budgets,
            "updatedAt": now(),
        }
        app.state.db.monthly_plans.update_one(
            {"uid": owner_uid, "month": plan_month},
            {"$set": doc, "$setOnInsert": {"createdAt": now()}},
            upsert=True,
        )
        return monthly_plan_out(app.state.db, owner_uid, plan_month, group_id=group_id)

    @app.get("/api/v1/dashboard/snapshot")
    def dashboard(user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
        docs = [expense_out(doc) for doc in app.state.db.expenses.find({"uid": user["uid"]}).sort("date", -1).limit(20)]
        return {
            "overallLabel": "You are all settled up",
            "overallAmountText": "INR 0.00",
            "overallPositive": True,
            "friendItems": friend_balance_items(app.state.db, user["uid"]),
            "groupItems": group_balance_items(app.state.db, user["uid"]),
            "actionItems": dashboard_action_items(app.state.db, user["uid"]),
            "activityItems": [personal_dashboard_activity_item(doc) for doc in docs],
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
        return {
            "balances": friend_balance_map(app.state.db, user["uid"]),
            "balancesByCurrency": friend_balance_map_by_currency(app.state.db, user["uid"]),
        }

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
            existing = app.state.db.friendships.find_one({"key": "_".join(pair)})
            if existing:
                record_friendship_tombstone(app.state.db, existing, user["uid"])
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
        member_roles = {user["uid"]: normalize_family_role(body.get("ownerRole") or "")}
        pending_invites: list[dict[str, Any]] = []
        pending_email_set: set[str] = set()
        unresolved_members: list[str] = []
        for contact in body.get("members") or []:
            raw_contact = str(contact).strip()
            if not raw_contact:
                continue
            resolved = resolve_user(app.state.db, raw_contact)
            role = group_member_role_for_contact(body, raw_contact, resolved.get("uid") if resolved else None)
            if resolved and resolved["uid"] not in members:
                members.append(resolved["uid"])
                if role:
                    member_roles[resolved["uid"]] = role
            elif not resolved:
                invite_email = normalize_pending_invite_email(raw_contact)
                if invite_email:
                    if invite_email not in pending_email_set:
                        pending_email_set.add(invite_email)
                        pending_invites.append(
                            {
                                "contact": raw_contact,
                                "emailNormalized": invite_email,
                                "role": role,
                                "invitedBy": user["uid"],
                                "createdAt": now(),
                            }
                        )
                else:
                    unresolved_members.append(raw_contact)
        if unresolved_members:
            raise HTTPException(
                status_code=404,
                detail=api_error("MEMBER_NOT_FOUND", f"member not found: {', '.join(unresolved_members)}"),
            )
        doc = {
            "id": uuid.uuid4().hex,
            "name": str(body["name"]).strip(),
            "groupType": str(body.get("groupType") or "split"),
            "currencyCodes": [normalize_currency(body.get("currency") or body.get("defaultCurrency") or "INR")],
            "createdBy": user["uid"],
            "memberUids": members,
            "memberRoles": member_roles,
            "pendingInvites": pending_invites,
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
            record_group_tombstone(
                app.state.db,
                group,
                user["uid"],
                "deleted" if not members else "left",
            )
            if not members:
                record_group_expense_tombstones_for_group(
                    app.state.db,
                    group,
                    user["uid"],
                )
                app.state.db.groups.delete_one({"id": group_id})
                app.state.db.group_expenses.delete_many({"groupId": group_id})
                app.state.db.group_settlements.delete_many({"groupId": group_id})
                app.state.db.monthly_plans.delete_many({"uid": monthly_plan_group_owner(group_id)})
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
            doc = await build_group_expense(app, body, group, app.state.db, user["uid"])
            app.state.db.group_expenses.insert_one(doc)
            touch_group(app.state.db, group_id)
            return JSONResponse(status_code=201, content=json_ready(group_expense_out(doc)))
        if parts == ["settlements"] and request.method == "GET":
            docs = app.state.db.group_settlements.find({"groupId": group_id}).sort("createdAt", -1)
            return {"settlements": [group_settlement_out(doc) for doc in docs]}
        if parts == ["settlements"] and request.method == "POST":
            body = await request.json()
            member_uid = str(body.get("memberUid") or "").strip()
            if not member_uid:
                raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", "memberUid is required"))
            if member_uid == user["uid"]:
                raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", "cannot settle with yourself"))
            if member_uid not in group.get("memberUids", []):
                raise HTTPException(status_code=404, detail=api_error("NOT_FOUND", "member not found"))
            direction = str(body.get("direction") or "paid").strip().lower()
            if direction not in {"paid", "received"}:
                raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", "direction must be paid or received"))
            amount = float(body.get("amount") or 0)
            if amount <= 0:
                raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", "amount must be positive"))
            payer_uid = user["uid"] if direction == "paid" else member_uid
            receiver_uid = member_uid if direction == "paid" else user["uid"]
            doc = {
                "id": uuid.uuid4().hex,
                "groupId": group_id,
                "payerUid": payer_uid,
                "receiverUid": receiver_uid,
                "amount": amount,
                "currency": normalize_currency(body.get("currency") or "INR"),
                "note": str(body.get("note") or "").strip(),
                "createdBy": user["uid"],
                "createdAt": now(),
            }
            app.state.db.group_settlements.insert_one(doc)
            touch_group(app.state.db, group_id)
            return JSONResponse(status_code=201, content=json_ready(group_settlement_out(doc)))
        if len(parts) == 2 and parts[0] == "expenses" and request.method == "PUT":
            body = await request.json()
            existing = app.state.db.group_expenses.find_one({"groupId": group_id, "id": parts[1]})
            if not existing:
                raise HTTPException(status_code=404, detail=api_error("NOT_FOUND", "group or expense not found"))
            updated = await build_group_expense(app, body, group, app.state.db, user["uid"], expense_id=parts[1], created_by=existing["createdBy"], created_at=existing["createdAt"])
            app.state.db.group_expenses.replace_one({"groupId": group_id, "id": parts[1]}, updated)
            touch_group(app.state.db, group_id)
            return group_expense_out(updated)
        if len(parts) == 2 and parts[0] == "expenses" and request.method == "DELETE":
            existing = app.state.db.group_expenses.find_one({"groupId": group_id, "id": parts[1]})
            if existing:
                record_group_expense_tombstone(app.state.db, group, existing, user["uid"])
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
        docs = app.state.db.recurring_templates.find({
            "uid": user["uid"],
            "deletedAt": {"$exists": False},
        })
        return {"templates": [json_ready(doc) for doc in docs]}

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

    @app.put("/api/v1/recurring/templates/{template_id}")
    def update_recurring_template(
        template_id: str,
        body: dict[str, Any],
        user: dict[str, Any] = Depends(current_user),
    ) -> dict[str, Any]:
        existing = app.state.db.recurring_templates.find_one({
            "id": template_id,
            "uid": user["uid"],
            "deletedAt": {"$exists": False},
        })
        if not existing:
            raise HTTPException(status_code=404, detail=api_error("NOT_FOUND", "recurring template not found"))
        updates = recurring_template_updates(body, existing)
        if not updates:
            return json_ready(existing)
        app.state.db.recurring_templates.update_one(
            {"id": template_id, "uid": user["uid"]},
            {"$set": updates},
        )
        updated = app.state.db.recurring_templates.find_one({"id": template_id, "uid": user["uid"]})
        reconcile_recurring_template_occurrences(app.state.db, user["uid"], updated)
        updated = app.state.db.recurring_templates.find_one({"id": template_id, "uid": user["uid"]})
        return json_ready(updated)

    @app.delete("/api/v1/recurring/templates/{template_id}", status_code=204)
    def delete_recurring_template(template_id: str, user: dict[str, Any] = Depends(current_user)) -> Response:
        existing = app.state.db.recurring_templates.find_one({
            "id": template_id,
            "uid": user["uid"],
            "deletedAt": {"$exists": False},
        })
        if not existing:
            raise HTTPException(status_code=404, detail=api_error("NOT_FOUND", "recurring template not found"))
        current = now()
        app.state.db.recurring_templates.update_one(
            {"id": template_id, "uid": user["uid"]},
            {"$set": {"active": False, "deletedAt": current, "updatedAt": current}},
        )
        app.state.db.recurring_occurrences.delete_many({
            "uid": user["uid"],
            "templateId": template_id,
            "status": {"$ne": "confirmed"},
        })
        return Response(status_code=204)

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
    db.expenses.create_index([("uid", ASCENDING), ("updatedAt", ASCENDING)])
    db.expense_tombstones.create_index([("uid", ASCENDING), ("deletedAt", ASCENDING)])
    db.monthly_plans.create_index([("uid", ASCENDING), ("month", ASCENDING)], unique=True)
    db.friendships.create_index("key", unique=True)
    db.friendships.create_index([("uids", ASCENDING), ("updatedAt", ASCENDING)])
    db.friendship_tombstones.create_index([("uids", ASCENDING), ("deletedAt", ASCENDING)])
    db.friend_settlements.create_index([("uids", ASCENDING), ("createdAt", ASCENDING)])
    db.groups.create_index("memberUids")
    db.groups.create_index("pendingInvites.emailNormalized")
    db.group_expenses.create_index([("groupId", ASCENDING), ("date", ASCENDING)])
    db.group_expenses.create_index([("groupId", ASCENDING), ("updatedAt", ASCENDING)])
    db.group_settlements.create_index([("groupId", ASCENDING), ("createdAt", ASCENDING)])
    db.group_tombstones.create_index([("memberUids", ASCENDING), ("deletedAt", ASCENDING)])
    db.group_expense_tombstones.create_index([("memberUids", ASCENDING), ("deletedAt", ASCENDING)])
    db.ai_jobs.create_index([("uid", ASCENDING), ("createdAt", ASCENDING)])
    db.recurring_templates.create_index([("uid", ASCENDING), ("active", ASCENDING)])
    db.recurring_templates.create_index([("uid", ASCENDING), ("updatedAt", ASCENDING)])
    db.recurring_occurrences.create_index([("uid", ASCENDING), ("period", ASCENDING)])
    db.recurring_occurrences.create_index([("uid", ASCENDING), ("updatedAt", ASCENDING)])
    for name, spec in list(db.recurring_occurrences.index_information().items()):
        if spec.get("unique") and spec.get("key") == [
            ("uid", ASCENDING),
            ("templateId", ASCENDING),
            ("period", ASCENDING),
        ]:
            db.recurring_occurrences.drop_index(name)
    db.recurring_occurrences.create_index(
        [("uid", ASCENDING), ("templateId", ASCENDING), ("period", ASCENDING), ("dueDate", ASCENDING)],
        unique=True,
    )


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


FRESHNESS_SECTIONS = {
    "dashboard",
    "groups",
    "friends",
    "recurring",
    "activity",
    "plans",
}
ACTIVITY_INCLUDE_SECTIONS = {
    "personal",
    "group",
    "friend_settlements",
    "group_settlements",
    "recurring",
}
ACTIVITY_DEFAULT_INCLUDE = set(ACTIVITY_INCLUDE_SECTIONS)


def parse_freshness_sections(raw: str) -> list[str]:
    requested = [
        section.strip().lower()
        for section in raw.split(",")
        if section.strip()
    ]
    if not requested:
        return ["dashboard", "groups", "friends", "recurring", "activity"]
    sections = [section for section in requested if section in FRESHNESS_SECTIONS]
    if not sections:
        raise HTTPException(
            status_code=400,
            detail=api_error("INVALID_ARGUMENT", "sections must include a known freshness section"),
        )
    return sections


def parse_activity_include(raw: str) -> set[str]:
    requested = {
        section.strip().lower()
        for section in raw.split(",")
        if section.strip()
    }
    if not requested:
        return set(ACTIVITY_DEFAULT_INCLUDE)
    if "settlements" in requested:
        requested.update({"friend_settlements", "group_settlements"})
    sections = requested & ACTIVITY_INCLUDE_SECTIONS
    if not sections:
        raise HTTPException(
            status_code=400,
            detail=api_error("INVALID_ARGUMENT", "include must contain a known activity section"),
        )
    return sections


def max_time(*values: datetime | None) -> datetime | None:
    latest: datetime | None = None
    for value in values:
        if value is None:
            continue
        candidate = aware(value)
        if latest is None or candidate > latest:
            latest = candidate
    return latest


def latest_collection_time(
    db: Any,
    collection_name: str,
    filters: dict[str, Any],
    field: str,
) -> datetime | None:
    doc = db[collection_name].find_one(filters, sort=[(field, DESCENDING)])
    value = doc.get(field) if doc else None
    return aware(value) if isinstance(value, datetime) else None


def user_group_ids(db: Any, uid: str) -> list[str]:
    return [
        doc["id"]
        for doc in db.groups.find({"memberUids": uid}, {"id": 1})
        if doc.get("id")
    ]


def personal_expense_freshness(db: Any, uid: str) -> datetime | None:
    return max_time(
        latest_collection_time(db, "expenses", {"uid": uid}, "updatedAt"),
        latest_collection_time(db, "expense_tombstones", {"uid": uid}, "deletedAt"),
    )


def group_freshness(db: Any, uid: str) -> datetime | None:
    group_ids = user_group_ids(db, uid)
    expense_latest = None
    if group_ids:
        expense_latest = latest_collection_time(
            db,
            "group_expenses",
            {"groupId": {"$in": group_ids}},
            "updatedAt",
        )
        settlement_latest = latest_collection_time(
            db,
            "group_settlements",
            {"groupId": {"$in": group_ids}},
            "createdAt",
        )
    else:
        settlement_latest = None
    return max_time(
        latest_collection_time(db, "groups", {"memberUids": uid}, "updatedAt"),
        expense_latest,
        settlement_latest,
        latest_collection_time(db, "group_tombstones", {"memberUids": uid}, "deletedAt"),
        latest_collection_time(db, "group_expense_tombstones", {"memberUids": uid}, "deletedAt"),
    )


def friends_freshness(db: Any, uid: str) -> datetime | None:
    return max_time(
        latest_collection_time(db, "friendships", {"uids": uid}, "updatedAt"),
        latest_collection_time(db, "friendship_tombstones", {"uids": uid}, "deletedAt"),
        latest_collection_time(db, "friend_settlements", {"uids": uid}, "createdAt"),
    )


def recurring_freshness(db: Any, uid: str) -> datetime | None:
    return max_time(
        latest_collection_time(db, "recurring_templates", {"uid": uid}, "updatedAt"),
        latest_collection_time(db, "recurring_occurrences", {"uid": uid}, "updatedAt"),
    )


def monthly_plan_freshness(db: Any, uid: str) -> datetime | None:
    owner_keys = [uid]
    owner_keys.extend(
        f"group:{group_id}"
        for group_id in user_group_ids(db, uid)
        if group_id
    )
    if not owner_keys:
        return None
    return latest_collection_time(
        db,
        "monthly_plans",
        {"uid": {"$in": owner_keys}},
        "updatedAt",
    )


def activity_freshness(db: Any, uid: str) -> datetime | None:
    return max_time(
        personal_expense_freshness(db, uid),
        group_freshness(db, uid),
        latest_collection_time(db, "friend_settlements", {"uids": uid}, "createdAt"),
        latest_collection_time(
            db,
            "recurring_occurrences",
            {"uid": uid, "status": "confirmed"},
            "updatedAt",
        ),
    )


def dashboard_freshness(db: Any, uid: str) -> datetime | None:
    return max_time(
        latest_collection_time(db, "users", {"uid": uid}, "updatedAt"),
        personal_expense_freshness(db, uid),
        group_freshness(db, uid),
        friends_freshness(db, uid),
        recurring_freshness(db, uid),
        monthly_plan_freshness(db, uid),
    )


def section_latest_time(db: Any, uid: str, section: str) -> datetime | None:
    if section == "dashboard":
        return dashboard_freshness(db, uid)
    if section == "groups":
        return group_freshness(db, uid)
    if section == "friends":
        return friends_freshness(db, uid)
    if section == "recurring":
        return recurring_freshness(db, uid)
    if section == "activity":
        return activity_freshness(db, uid)
    if section == "plans":
        return monthly_plan_freshness(db, uid)
    return None


def tombstone_since_filter(field: str, since: datetime | None) -> dict[str, Any]:
    return {} if since is None else {field: {"$gt": since}}


def activity_tombstones_since(db: Any, uid: str, since: datetime | None) -> dict[str, Any]:
    personal_deleted = [
        doc.get("expenseId")
        for doc in db.expense_tombstones.find(
            {"uid": uid, **tombstone_since_filter("deletedAt", since)}
        )
        if doc.get("expenseId")
    ]
    group_deleted = [
        {
            "groupId": doc.get("groupId"),
            "expenseId": doc.get("expenseId"),
        }
        for doc in db.group_expense_tombstones.find(
            {"memberUids": uid, **tombstone_since_filter("deletedAt", since)}
        )
        if doc.get("groupId") and doc.get("expenseId")
    ]
    deleted_group_ids = [
        doc.get("groupId")
        for doc in db.group_tombstones.find(
            {"memberUids": uid, **tombstone_since_filter("deletedAt", since)}
        )
        if doc.get("groupId")
    ]
    return {
        "personalDeletedIds": personal_deleted,
        "groupDeleted": group_deleted,
        "deletedGroupIds": deleted_group_ids,
    }


def activity_group_summary(group: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": group.get("id", ""),
        "name": group.get("name") or "Group",
        "groupType": group.get("groupType") or "split",
        "memberCount": len(group.get("memberUids") or []),
    }


def activity_since_filter(since: datetime | None, field: str = "updatedAt") -> dict[str, Any]:
    return {} if since is None else {field: {"$gt": since}}


def activity_entry_sort_time(entry: dict[str, Any]) -> datetime:
    for key in ["updatedAt", "date"]:
        value = entry.get(key)
        if isinstance(value, datetime):
            return aware(value)
    return now()


def activity_user_summary(user: dict[str, Any] | None, fallback_uid: str = "") -> dict[str, Any]:
    if user:
        return user_public(user)
    return {
        "uid": fallback_uid,
        "email": "",
        "displayName": "Someone",
        "photoUrl": None,
        "phone": "",
    }


def activity_users_by_uid(db: Any, uids: set[str]) -> dict[str, dict[str, Any]]:
    cleaned = {uid for uid in uids if uid}
    if not cleaned:
        return {}
    return {doc["uid"]: doc for doc in db.users.find({"uid": {"$in": list(cleaned)}})}


def activity_feed_entries(
    db: Any,
    uid: str,
    since: datetime | None,
    before: datetime | None,
    limit: int,
    include_sections: set[str],
) -> dict[str, Any]:
    entries: list[dict[str, Any]] = []
    if "personal" in include_sections:
        personal_filter = {"uid": uid, **activity_since_filter(since)}
        for expense in db.expenses.find(personal_filter):
            entries.append(
                {
                    "kind": "personalExpense",
                    "id": expense.get("id", ""),
                    "date": expense.get("date"),
                    "updatedAt": expense.get("updatedAt"),
                    "expense": expense_out(expense),
                }
            )

    if "group" in include_sections:
        groups = list(db.groups.find({"memberUids": uid}))
        groups_by_id = {group.get("id"): group for group in groups if group.get("id")}
        if groups_by_id:
            group_filter = {
                "groupId": {"$in": list(groups_by_id.keys())},
                **activity_since_filter(since),
            }
            for expense in db.group_expenses.find(group_filter):
                group = groups_by_id.get(expense.get("groupId"))
                if not group:
                    continue
                entries.append(
                    {
                        "kind": "groupExpense",
                        "id": expense.get("id", ""),
                        "groupId": expense.get("groupId", ""),
                        "date": expense.get("date"),
                        "updatedAt": expense.get("updatedAt"),
                        "group": activity_group_summary(group),
                        "expense": group_expense_out(expense),
                    }
                )

    if "friend_settlements" in include_sections:
        settlement_filter = {
            "uids": uid,
            **activity_since_filter(since, "createdAt"),
        }
        settlements = list(db.friend_settlements.find(settlement_filter))
        user_ids = {
            str(settlement.get("payerUid") or "")
            for settlement in settlements
        } | {
            str(settlement.get("receiverUid") or "")
            for settlement in settlements
        }
        users_by_uid = activity_users_by_uid(db, user_ids)
        for settlement in settlements:
            payer_uid = str(settlement.get("payerUid") or "")
            receiver_uid = str(settlement.get("receiverUid") or "")
            entries.append(
                {
                    "kind": "friendSettlement",
                    "id": settlement.get("id", ""),
                    "date": settlement.get("createdAt"),
                    "updatedAt": settlement.get("createdAt"),
                    "viewerUid": uid,
                    "payer": activity_user_summary(
                        users_by_uid.get(payer_uid),
                        payer_uid,
                    ),
                    "receiver": activity_user_summary(
                        users_by_uid.get(receiver_uid),
                        receiver_uid,
                    ),
                    "settlement": friend_settlement_out(settlement),
                }
            )

    if "group_settlements" in include_sections:
        groups = list(db.groups.find({"memberUids": uid}))
        groups_by_id = {group.get("id"): group for group in groups if group.get("id")}
        if groups_by_id:
            settlement_filter = {
                "groupId": {"$in": list(groups_by_id.keys())},
                **activity_since_filter(since, "createdAt"),
            }
            settlements = list(db.group_settlements.find(settlement_filter))
            user_ids = {
                str(settlement.get("payerUid") or "")
                for settlement in settlements
            } | {
                str(settlement.get("receiverUid") or "")
                for settlement in settlements
            }
            users_by_uid = activity_users_by_uid(db, user_ids)
            for settlement in settlements:
                group = groups_by_id.get(settlement.get("groupId"))
                if not group:
                    continue
                payer_uid = str(settlement.get("payerUid") or "")
                receiver_uid = str(settlement.get("receiverUid") or "")
                entries.append(
                    {
                        "kind": "groupSettlement",
                        "id": settlement.get("id", ""),
                        "groupId": settlement.get("groupId", ""),
                        "date": settlement.get("createdAt"),
                        "updatedAt": settlement.get("createdAt"),
                        "viewerUid": uid,
                        "group": activity_group_summary(group),
                        "payer": activity_user_summary(
                            users_by_uid.get(payer_uid),
                            payer_uid,
                        ),
                        "receiver": activity_user_summary(
                            users_by_uid.get(receiver_uid),
                            receiver_uid,
                        ),
                        "settlement": group_settlement_out(settlement),
                    }
                )

    if "recurring" in include_sections:
        occurrence_filter = {
            "uid": uid,
            "status": "confirmed",
            **activity_since_filter(since),
        }
        for occurrence in db.recurring_occurrences.find(occurrence_filter):
            entries.append(
                {
                    "kind": "recurringConfirmation",
                    "id": occurrence.get("id", ""),
                    "date": occurrence.get("actualDate") or occurrence.get("dueDate"),
                    "updatedAt": occurrence.get("updatedAt"),
                    "viewerUid": uid,
                    "occurrence": recurring_occurrence_out(occurrence),
                }
            )

    if before is not None:
        before_dt = aware(before)
        entries = [
            entry
            for entry in entries
            if activity_entry_sort_time(entry) < before_dt
        ]

    entries.sort(key=activity_entry_sort_time, reverse=True)
    limited = entries[: limit + 1]
    has_more = len(limited) > limit
    visible_entries = limited[:limit]
    next_cursor = None
    if has_more and visible_entries:
        next_cursor = iso(activity_entry_sort_time(visible_entries[-1]))
    return {
        "entries": json_ready(visible_entries),
        "hasMore": has_more,
        "nextCursor": next_cursor,
    }


def group_tombstones_since(db: Any, uid: str, since: datetime | None) -> dict[str, Any]:
    deleted_group_ids = [
        doc.get("groupId")
        for doc in db.group_tombstones.find(
            {"memberUids": uid, **tombstone_since_filter("deletedAt", since)}
        )
        if doc.get("groupId")
    ]
    return {"deletedGroupIds": deleted_group_ids}


def freshness_section_payload(
    db: Any,
    uid: str,
    section: str,
    since: datetime | None,
    server_time: datetime,
) -> dict[str, Any]:
    latest = section_latest_time(db, uid, section)
    changed = since is None or (latest is not None and latest > since)
    payload: dict[str, Any] = {
        "changed": changed,
        "watermark": iso(latest or server_time),
    }
    if section == "activity":
        payload.update(activity_tombstones_since(db, uid, since))
    if section == "groups":
        payload.update(group_tombstones_since(db, uid, since))
    return payload


def record_expense_tombstone(db: Any, expense: dict[str, Any], deleted_by: str) -> None:
    db.expense_tombstones.insert_one(
        {
            "id": uuid.uuid4().hex,
            "uid": expense.get("uid"),
            "expenseId": expense.get("id"),
            "deletedBy": deleted_by,
            "deletedAt": now(),
        }
    )


def record_group_tombstone(db: Any, group: dict[str, Any], deleted_by: str, reason: str) -> None:
    db.group_tombstones.insert_one(
        {
            "id": uuid.uuid4().hex,
            "groupId": group.get("id"),
            "memberUids": list(group.get("memberUids") or []),
            "reason": reason,
            "deletedBy": deleted_by,
            "deletedAt": now(),
        }
    )


def record_group_expense_tombstone(
    db: Any,
    group: dict[str, Any],
    expense: dict[str, Any],
    deleted_by: str,
) -> None:
    db.group_expense_tombstones.insert_one(
        {
            "id": uuid.uuid4().hex,
            "groupId": group.get("id"),
            "expenseId": expense.get("id"),
            "memberUids": list(group.get("memberUids") or []),
            "deletedBy": deleted_by,
            "deletedAt": now(),
        }
    )


def record_group_expense_tombstones_for_group(
    db: Any,
    group: dict[str, Any],
    deleted_by: str,
) -> None:
    for expense in db.group_expenses.find({"groupId": group.get("id")}):
        record_group_expense_tombstone(db, group, expense, deleted_by)


def record_friendship_tombstone(db: Any, friendship: dict[str, Any], deleted_by: str) -> None:
    db.friendship_tombstones.insert_one(
        {
            "id": uuid.uuid4().hex,
            "key": friendship.get("key"),
            "uids": list(friendship.get("uids") or []),
            "deletedBy": deleted_by,
            "deletedAt": now(),
        }
    )


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


def add_months(month: str, delta: int) -> str:
    year, month_number = [int(part) for part in normalize_month(month).split("-")]
    zero_based = (year * 12 + (month_number - 1)) + delta
    new_year, new_month_zero = divmod(zero_based, 12)
    return f"{new_year:04d}-{new_month_zero + 1:02d}"


def month_range(month: str) -> tuple[datetime, datetime]:
    year, month_number = [int(part) for part in month.split("-")]
    start = datetime(year, month_number, 1, tzinfo=UTC)
    if month_number == 12:
        end = datetime(year + 1, 1, 1, tzinfo=UTC)
    else:
        end = datetime(year, month_number + 1, 1, tzinfo=UTC)
    return start, end


def parse_bool_field(value: Any, field: str) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        normalized = value.strip().lower()
        if normalized in {"true", "1", "yes"}:
            return True
        if normalized in {"false", "0", "no"}:
            return False
    raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", f"{field} must be true or false"))


def recurring_template_updates(body: dict[str, Any], existing: dict[str, Any]) -> dict[str, Any]:
    updates: dict[str, Any] = {}
    if "title" in body:
        title = str(body.get("title") or "").strip()
        if not title:
            raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", "title is required"))
        updates["title"] = title
    if "kind" in body:
        kind = str(body.get("kind") or "expense").strip().lower()
        if kind not in {"expense", "income"}:
            raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", "kind must be expense or income"))
        updates["kind"] = kind
    if "amount" in body or "expectedAmount" in body:
        amount = float(body.get("amount") or body.get("expectedAmount") or 0)
        if amount <= 0:
            raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", "amount must be positive"))
        updates["amount"] = amount
        updates["expectedAmount"] = amount
    if "currency" in body:
        updates["currency"] = normalize_currency(body.get("currency"), "INR")
    if "category" in body:
        category = str(body.get("category") or "").strip()
        if not category:
            raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", "category is required"))
        updates["category"] = category
    if "frequency" in body:
        frequency = str(body.get("frequency") or "monthly").strip().lower()
        if frequency not in {"daily", "weekly", "monthly"}:
            raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", "frequency must be daily, weekly or monthly"))
        updates["frequency"] = frequency
    if "startDate" in body:
        updates["startDate"] = parse_dt(str(body.get("startDate") or ""))
    if "dayOfMonth" in body:
        day_of_month = int(body.get("dayOfMonth") or 0)
        if day_of_month < 1 or day_of_month > 31:
            raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", "dayOfMonth must be between 1 and 31"))
        updates["dayOfMonth"] = day_of_month
    if "active" in body:
        active = parse_bool_field(body.get("active"), "active")
        updates["active"] = active
        if active and not existing.get("active", True):
            updates["resumedAt"] = now()
        elif not active and existing.get("active", True):
            updates["pausedAt"] = now()
    if not updates:
        return {}
    merged = {**existing, **updates}
    if any(field in updates for field in {"startDate", "dayOfMonth", "frequency", "active"}):
        start = aware(merged.get("startDate") or now())
        updates["nextDueDate"] = recurring_due_date_for_month(
            merged,
            max(current_month(), f"{start.year:04d}-{start.month:02d}"),
        )
    updates["updatedAt"] = now()
    return updates


def reconcile_recurring_template_occurrences(db: Any, uid: str, template: dict[str, Any] | None) -> None:
    if not template or template.get("deletedAt"):
        return
    template_id = template.get("id")
    if not template_id:
        return
    if not template.get("active", True):
        db.recurring_occurrences.delete_many({
            "uid": uid,
            "templateId": template_id,
            "status": {"$ne": "confirmed"},
        })
        return
    used_due_dates: set[tuple[str, datetime]] = set()
    cursor = db.recurring_occurrences.find({
        "uid": uid,
        "templateId": template_id,
        "status": {"$ne": "confirmed"},
    })
    for occurrence in cursor:
        period = normalize_month(str(occurrence.get("period") or current_month()))
        due_dates = recurring_due_dates_for_month(template, period)
        due_date = aware(occurrence.get("dueDate") or now())
        replacement_due_date: datetime | None = None
        if due_date in due_dates and (period, due_date) not in used_due_dates:
            replacement_due_date = due_date
        elif len(due_dates) == 1 and (period, due_dates[0]) not in used_due_dates:
            replacement_due_date = due_dates[0]
        if replacement_due_date is None:
            db.recurring_occurrences.delete_one({"id": occurrence["id"], "uid": uid})
            continue
        used_due_dates.add((period, replacement_due_date))
        db.recurring_occurrences.update_one(
            {"id": occurrence["id"], "uid": uid},
            {
                "$set": {
                    "kind": template.get("kind") or "expense",
                    "title": template.get("title") or "Recurring item",
                    "category": template.get("category") or "Personal",
                    "currency": template.get("currency") or "INR",
                    "expectedAmount": float(template.get("expectedAmount") or template.get("amount") or 0),
                    "dueDate": replacement_due_date,
                    "updatedAt": now(),
                }
            },
        )
    ensure_recurring_occurrences(db, uid, current_month())


def recurring_occurrence_id(uid: str, template_id: str, due_date: datetime) -> str:
    seed = f"{uid}:{template_id}:{iso(due_date)}"
    return hashlib.sha1(seed.encode("utf-8")).hexdigest()


def recurring_due_dates_for_month(template: dict[str, Any], month: str) -> list[datetime]:
    start, end = month_range(month)
    frequency = str(template.get("frequency") or "monthly").lower()
    template_start = aware(template.get("startDate") or start)
    active_from = aware(template.get("resumedAt") or template_start)
    earliest = max(start, template_start, active_from)
    if template_start >= end or active_from >= end:
        return []
    if frequency == "monthly":
        due_date = recurring_due_date_for_month(template, month)
        if due_date < start or due_date >= end or due_date < template_start or due_date < active_from:
            return []
        return [due_date]

    if frequency not in {"daily", "weekly"}:
        return []
    interval = timedelta(days=1 if frequency == "daily" else 7)
    due_date = template_start
    if due_date < earliest:
        interval_seconds = interval.total_seconds()
        skipped = int((earliest - due_date).total_seconds() // interval_seconds)
        due_date += interval * max(0, skipped)
        while due_date < earliest:
            due_date += interval
    due_dates: list[datetime] = []
    while due_date < end:
        if due_date >= start and due_date >= template_start and due_date >= active_from:
            due_dates.append(due_date)
        due_date += interval
    return due_dates


def recurring_due_date_for_month(template: dict[str, Any], month: str) -> datetime:
    year, month_number = [int(part) for part in month.split("-")]
    frequency = str(template.get("frequency") or "monthly").lower()
    start = aware(template.get("startDate") or now())
    if frequency == "daily" or frequency == "weekly":
        dates = recurring_due_dates_for_month(template, month)
        return dates[0] if dates else next_due(start, frequency)
    last_day = calendar.monthrange(year, month_number)[1]
    day = int(template.get("dayOfMonth") or start.day)
    return datetime(year, month_number, min(day, last_day), tzinfo=UTC)


def ensure_recurring_occurrences(db: Any, uid: str, month: str) -> int:
    period = normalize_month(month)
    start, end = month_range(period)
    created = 0
    for template in db.recurring_templates.find({
        "uid": uid,
        "active": True,
        "deletedAt": {"$exists": False},
    }):
        for due_date in recurring_due_dates_for_month(template, period):
            doc = {
                "id": recurring_occurrence_id(uid, template["id"], due_date),
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
                {
                    "uid": uid,
                    "templateId": template["id"],
                    "period": period,
                    "dueDate": due_date,
                },
                {"$setOnInsert": doc},
                upsert=True,
            )
            if getattr(result, "upserted_id", None) is not None:
                created += 1
    return created


def recurring_occurrence_out(doc: dict[str, Any] | None) -> dict[str, Any]:
    return json_ready(doc or {})


def safe_currency(value: Any, default: str | None = None) -> str | None:
    try:
        return normalize_currency(value, default or "INR")
    except HTTPException:
        return default


def expense_amounts_by_currency(expense: dict[str, Any]) -> dict[str, float]:
    amounts: dict[str, float] = {}
    raw_converted = expense.get("convertedAmounts")
    if isinstance(raw_converted, dict):
        for raw_currency, raw_amount in raw_converted.items():
            currency = safe_currency(raw_currency, None)
            if not currency:
                continue
            if isinstance(raw_amount, dict):
                raw_amount = raw_amount.get("amount")
            try:
                amount = float(raw_amount or 0)
            except (TypeError, ValueError):
                continue
            amounts[currency] = amount

    base_currency = safe_currency(expense.get("currency"), "INR") or "INR"
    if base_currency not in amounts:
        try:
            amounts[base_currency] = float(expense.get("amount") or 0)
        except (TypeError, ValueError):
            amounts[base_currency] = 0.0
    return amounts


def expense_amount_for_currency(expense: dict[str, Any], currency: str) -> float | None:
    amounts = expense_amounts_by_currency(expense)
    return amounts.get(currency)


def group_currency_codes(group: dict[str, Any], expenses: list[dict[str, Any]] | None = None, extra: list[str] | None = None) -> list[str]:
    codes: list[str] = []

    def add(raw: Any) -> None:
        currency = safe_currency(raw, None)
        if currency and currency not in codes:
            codes.append(currency)

    raw_codes = group.get("currencyCodes") or group.get("currencies") or []
    if isinstance(raw_codes, list):
        for item in raw_codes:
            add(item)
    if expenses:
        for expense in expenses:
            for currency in expense_amounts_by_currency(expense).keys():
                add(currency)
    for item in extra or []:
        add(item)
    if not codes:
        codes.append("INR")
    return codes


def requested_conversion_currencies(body: dict[str, Any]) -> list[str]:
    requested: list[Any] = []
    for key in ["targetCurrencies", "conversionCurrencies"]:
        raw = body.get(key)
        if isinstance(raw, list):
            requested.extend(raw)
        elif isinstance(raw, str):
            requested.extend(item.strip() for item in raw.split(","))
    for key in ["targetCurrency", "conversionCurrency", "reportingCurrency"]:
        if body.get(key):
            requested.append(body.get(key))
    codes: list[str] = []
    for item in requested:
        if not str(item or "").strip():
            continue
        currency = normalize_currency(item)
        if currency not in codes:
            codes.append(currency)
    return codes


def format_currency_amount(currency: str, amount: float) -> str:
    return f"{currency} {amount:.2f}"


def personal_dashboard_activity_item(doc: dict[str, Any]) -> dict[str, Any]:
    currency = safe_currency(doc.get("currency"), "INR") or "INR"
    amount = float(doc.get("amount") or 0)
    return {
        "title": doc.get("description") or doc.get("category") or "Expense",
        "subtitle": doc.get("date"),
        "amountText": f"You spent {format_currency_amount(currency, amount)}",
        "positive": False,
    }


def format_currency_amounts(amounts: dict[str, float]) -> str:
    non_zero = [(currency, amount) for currency, amount in amounts.items() if abs(amount) > 0.005]
    if not non_zero:
        return "INR 0.00"
    return ", ".join(format_currency_amount(currency, abs(amount)) for currency, amount in sorted(non_zero))


def monthly_plan_group_owner(group_id: str) -> str:
    return f"group:{group_id}"


def monthly_plan_scope(db: Any, uid: str, raw_group_id: Any = "") -> tuple[str, str | None]:
    group_id = str(raw_group_id or "").strip()
    if not group_id:
        return uid, None
    require_group_member(db, group_id, uid)
    return monthly_plan_group_owner(group_id), group_id


def monthly_plan_out(db: Any, uid: str, month: str, group_id: str | None = None) -> dict[str, Any]:
    plan = db.monthly_plans.find_one({"uid": uid, "month": month}) or {}
    plan_currency = safe_currency(plan.get("currency"), "INR") or "INR"
    raw_budgets = plan.get("budgets") if isinstance(plan.get("budgets"), dict) else {}
    budgets = {str(key): float(value or 0) for key, value in raw_budgets.items()}
    start, end = month_range(month)
    actuals: dict[str, float] = {}
    if group_id:
        family_expenses = db.group_expenses.find({
            "groupId": group_id,
            "date": {"$gte": start, "$lt": end},
        })
        for expense in family_expenses:
            amount = expense_amount_for_currency(expense, plan_currency)
            if amount is None:
                continue
            category = str(expense.get("category") or "Personal").strip() or "Personal"
            actuals[category] = actuals.get(category, 0.0) + amount
    else:
        expenses = db.expenses.find({"uid": uid, "date": {"$gte": start, "$lt": end}})
        for expense in expenses:
            amount = expense_amount_for_currency(expense, plan_currency)
            if amount is None:
                continue
            category = str(expense.get("category") or "Personal").strip() or "Personal"
            actuals[category] = actuals.get(category, 0.0) + amount
        family_groups = list(db.groups.find({"memberUids": uid, "groupType": "family"}))
        family_group_ids = [group.get("id") for group in family_groups if group.get("id")]
        if family_group_ids:
            family_expenses = db.group_expenses.find({
                "groupId": {"$in": family_group_ids},
                "date": {"$gte": start, "$lt": end},
            })
            for expense in family_expenses:
                amount = expense_amount_for_currency(expense, plan_currency)
                if amount is None:
                    continue
                category = str(expense.get("category") or "Personal").strip() or "Personal"
                actuals[category] = actuals.get(category, 0.0) + amount
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
        "groupId": group_id,
        "currency": plan_currency,
        "totalBudget": total_budget,
        "totalActual": total_actual,
        "totalRemaining": total_budget - total_actual,
        "categories": rows,
        "updatedAt": plan.get("updatedAt"),
    })


def dashboard_action_items(db: Any, uid: str) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    current = now()
    today_start = datetime(current.year, current.month, current.day, tzinfo=UTC)
    tomorrow_start = today_start + timedelta(days=1)
    period = current_month()
    ensure_recurring_occurrences(db, uid, add_months(period, -1))
    ensure_recurring_occurrences(db, uid, period)

    recurring_docs = list(db.recurring_occurrences.find({
        "uid": uid,
        "status": {"$ne": "confirmed"},
        "dueDate": {"$lt": tomorrow_start},
    }).sort("dueDate", ASCENDING).limit(100))
    recurring_groups: list[list[dict[str, Any]]] = []
    recurring_group_indexes: dict[str, int] = {}
    for occurrence in recurring_docs:
        key = str(occurrence.get("templateId") or occurrence.get("id") or "")
        if not key or key not in recurring_group_indexes:
            recurring_group_indexes[key] = len(recurring_groups)
            recurring_groups.append([])
        recurring_groups[recurring_group_indexes[key]].append(occurrence)

    for group in recurring_groups[:3]:
        occurrence = group[0]
        due_date = aware(occurrence.get("dueDate") or current)
        overdue = due_date < today_start
        amount = float(occurrence.get("expectedAmount") or 0)
        currency = safe_currency(occurrence.get("currency"), "INR") or "INR"
        overdue_count = sum(1 for item in group if aware(item.get("dueDate") or current) < today_start)
        due_today_count = len(group) - overdue_count
        if len(group) == 1:
            due_label = "Overdue" if overdue else "Due today"
            subtitle = f"{due_label} - {format_currency_amount(currency, amount)}"
        elif overdue_count and due_today_count:
            subtitle = f"{overdue_count} overdue, {due_today_count} due today - {format_currency_amount(currency, amount)} each"
        elif overdue_count:
            subtitle = f"{overdue_count} overdue - {format_currency_amount(currency, amount)} each"
        else:
            subtitle = f"{due_today_count} due today - {format_currency_amount(currency, amount)} each"
        items.append({
            "title": f"Confirm {occurrence.get('title') or 'recurring item'}",
            "subtitle": subtitle,
            "severity": "warning" if overdue_count else "info",
            "destination": "recurring",
            "actionType": "confirm_recurring",
            "occurrenceId": occurrence.get("id") or "",
            "occurrenceCount": len(group),
            "templateId": occurrence.get("templateId") or "",
            "period": occurrence.get("period") or period,
        })

    plan = monthly_plan_out(db, uid, period)
    plan_currency = str(plan.get("currency") or "INR")
    over_budget_categories = [
        row
        for row in plan.get("categories", [])
        if isinstance(row, dict) and row.get("overBudget")
    ]
    for row in sorted(over_budget_categories, key=lambda item: float(item.get("remaining") or 0)):
        over_amount = abs(float(row.get("remaining") or 0))
        category = str(row.get("category") or "Monthly plan")
        items.append({
            "title": f"{category} is over budget",
            "subtitle": f"{format_currency_amount(plan_currency, over_amount)} over this month",
            "severity": "critical",
            "destination": "family",
            "actionType": "review_budget_category",
            "category": category,
        })

    for item in friend_balance_items(db, uid)[:1]:
        verb = "Collect from" if item.get("positive") else "Pay"
        items.append({
            "title": f"{verb} {item.get('title') or 'friend'}",
            "subtitle": f"{item.get('subtitle') or 'balance'} - {item.get('amountText') or ''}".strip(" -"),
            "severity": "info",
            "destination": "friends",
            "actionType": "settle_friend",
            "friendUid": item.get("friendUid") or "",
        })

    for item in group_balance_items(db, uid):
        if str(item.get("subtitle") or "").lower() == "settled up":
            continue
        items.append({
            "title": f"Review {item.get('title') or 'group'} balance",
            "subtitle": f"{item.get('subtitle') or 'balance'} - {item.get('amountText') or ''}".strip(" -"),
            "severity": "info",
            "destination": "groups",
            "actionType": "review_group_balance",
            "groupId": item.get("groupId") or "",
        })
        break

    recent_cutoff = current - timedelta(days=7)
    groups = list(db.groups.find({"memberUids": uid}, {"id": 1, "name": 1, "groupType": 1}))
    group_meta = {
        group.get("id"): {
            "name": group.get("name") or "Group",
            "destination": "family" if group.get("groupType") == "family" else "groups",
        }
        for group in groups
        if group.get("id")
    }
    if group_meta:
        recent_expenses = db.group_expenses.find({
            "groupId": {"$in": list(group_meta.keys())},
            "date": {"$gte": recent_cutoff},
        }).sort("date", DESCENDING).limit(20)
        for expense in recent_expenses:
            attachments = expense.get("attachments")
            if isinstance(attachments, list) and attachments:
                continue
            meta = group_meta.get(expense.get("groupId"), {})
            items.append({
                "title": f"Attach receipt for {expense.get('description') or 'expense'}",
                "subtitle": str(meta.get("name") or "Group"),
                "severity": "info",
                "destination": str(meta.get("destination") or "groups"),
                "actionType": "attach_group_receipt",
                "groupId": expense.get("groupId") or "",
                "expenseId": expense.get("id") or "",
            })
            break

    return items[:5]


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


def group_settlement_out(doc: dict[str, Any]) -> dict[str, Any]:
    return json_ready({
        key: doc.get(key)
        for key in [
            "id",
            "groupId",
            "payerUid",
            "receiverUid",
            "amount",
            "currency",
            "note",
            "createdBy",
            "createdAt",
        ]
    })


def friend_balance_map_by_currency(db: Any, uid: str) -> dict[str, dict[str, float]]:
    balances: dict[str, dict[str, float]] = {}
    for settlement in db.friend_settlements.find({"uids": uid}):
        payer_uid = settlement.get("payerUid")
        receiver_uid = settlement.get("receiverUid")
        amount = float(settlement.get("amount") or 0)
        currency = safe_currency(settlement.get("currency"), "INR") or "INR"
        if payer_uid == uid and receiver_uid:
            friend_balances = balances.setdefault(receiver_uid, {})
            friend_balances[currency] = friend_balances.get(currency, 0.0) + amount
        elif receiver_uid == uid and payer_uid:
            friend_balances = balances.setdefault(payer_uid, {})
            friend_balances[currency] = friend_balances.get(currency, 0.0) - amount
    return balances


def friend_balance_map(db: Any, uid: str) -> dict[str, float]:
    balances_by_currency = friend_balance_map_by_currency(db, uid)
    return {
        friend_uid: sum(amounts.values())
        for friend_uid, amounts in balances_by_currency.items()
    }


def friend_balance_items(db: Any, uid: str) -> list[dict[str, Any]]:
    balances = friend_balance_map_by_currency(db, uid)
    if not balances:
        return []
    users = {doc["uid"]: doc for doc in db.users.find({"uid": {"$in": list(balances.keys())}})}
    items = []
    for friend_uid, amounts in sorted(balances.items(), key=lambda item: sum(abs(amount) for amount in item[1].values()), reverse=True):
        non_zero = {currency: amount for currency, amount in amounts.items() if abs(amount) > 0.005}
        if not non_zero:
            continue
        friend = users.get(friend_uid, {"uid": friend_uid, "displayName": "Friend", "email": ""})
        label = user_public(friend)["displayName"]
        positive = all(amount > 0 for amount in non_zero.values())
        negative = all(amount < 0 for amount in non_zero.values())
        items.append({
            "title": label,
            "subtitle": "owes you" if positive else "you owe" if negative else "mixed balances",
            "amountText": format_currency_amounts(non_zero),
            "positive": not negative,
            "friendUid": friend_uid,
        })
    return items


def group_balance_items(db: Any, uid: str) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    groups = db.groups.find({"memberUids": uid, "groupType": {"$ne": "family"}}).sort("updatedAt", -1)
    for group in groups:
        expenses = list(db.group_expenses.find({"groupId": group["id"]}))
        settlements = list(db.group_settlements.find({"groupId": group["id"]}))
        if not expenses and not settlements:
            continue
        member_uids = group.get("memberUids", [])
        users = list(db.users.find({"uid": {"$in": member_uids}}))
        settlement_currencies = [settlement.get("currency") for settlement in settlements]
        currency_codes = group_currency_codes(group, expenses, settlement_currencies)
        display_data = compute_display_data(member_uids, expenses, group_member_aliases(member_uids, users), currency_codes, settlements)
        member_balances_by_currency = display_data.get("memberBalancesByCurrency", {})
        net_by_currency: dict[str, float] = {}
        for currency, balances in member_balances_by_currency.items():
            if not isinstance(balances, dict):
                continue
            member_balance = balances.get(uid, {})
            if isinstance(member_balance, dict):
                net_by_currency[str(currency)] = float(member_balance.get("net") or 0)
        non_zero = {currency: amount for currency, amount in net_by_currency.items() if abs(amount) > 0.005}
        if not non_zero:
            subtitle = "settled up"
            positive = True
        elif all(amount > 0 for amount in non_zero.values()):
            subtitle = "you are owed"
            positive = True
        elif all(amount < 0 for amount in non_zero.values()):
            subtitle = "you owe"
            positive = False
        else:
            subtitle = "mixed balances"
            positive = True
        items.append({
            "groupId": group.get("id") or "",
            "title": group.get("name") or "Group",
            "subtitle": subtitle,
            "amountText": format_currency_amounts(non_zero),
            "positive": positive,
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


def normalize_pending_invite_email(contact: str) -> str | None:
    email = contact.strip().lower()
    if "@" not in email:
        return None
    return normalize_email(email)


def group_member_role_for_contact(body: dict[str, Any], contact: str, uid: str | None = None) -> str:
    raw_roles = body.get("memberRolesByContact") or body.get("memberRoles") or {}
    if not isinstance(raw_roles, dict):
        return ""
    contact_key = contact.strip()
    lower_key = contact_key.lower()
    for key in [contact_key, lower_key, uid or ""]:
        if key and key in raw_roles:
            return normalize_family_role(raw_roles[key])
    return ""


def group_pending_invites(group: dict[str, Any]) -> list[dict[str, Any]]:
    invites = []
    for invite in group.get("pendingInvites") or []:
        if not isinstance(invite, dict):
            continue
        contact = str(invite.get("contact") or invite.get("emailNormalized") or "").strip()
        email = normalize_pending_invite_email(str(invite.get("emailNormalized") or contact))
        if not contact or not email:
            continue
        invites.append(
            {
                "contact": contact,
                "emailNormalized": email,
                "role": normalize_family_role(invite.get("role") or ""),
                "createdAt": invite.get("createdAt"),
            }
        )
    return invites


def accept_pending_group_invites(db: Any, user: dict[str, Any]) -> int:
    email = normalize_email(str(user.get("emailNormalized") or user.get("email") or ""))
    if not email:
        return 0
    accepted = 0
    for group in list(db.groups.find({"pendingInvites.emailNormalized": email})):
        pending = group_pending_invites(group)
        accepted_invites = [invite for invite in pending if invite["emailNormalized"] == email]
        if not accepted_invites:
            continue
        remaining_invites = [invite for invite in pending if invite["emailNormalized"] != email]
        member_uids = list(dict.fromkeys([*(group.get("memberUids") or []), user["uid"]]))
        role = next((invite["role"] for invite in accepted_invites if invite["role"]), "")
        updates: dict[str, Any] = {
            "memberUids": member_uids,
            "memberCount": len(member_uids),
            "pendingInvites": remaining_invites,
            "updatedAt": now(),
        }
        if role:
            updates[f"memberRoles.{user['uid']}"] = role
        db.groups.update_one({"id": group["id"]}, {"$set": updates})
        accepted += len(accepted_invites)
    return accepted


def require_group_member(db: Any, group_id: str, uid: str) -> dict[str, Any]:
    group = db.groups.find_one({"id": group_id})
    if not group:
        raise HTTPException(status_code=404, detail=api_error("NOT_FOUND", "group not found"))
    if uid not in group.get("memberUids", []):
        raise HTTPException(status_code=403, detail=api_error("FORBIDDEN", "you are not a group member"))
    return group


def group_out(db: Any, group: dict[str, Any]) -> dict[str, Any]:
    expenses = list(db.group_expenses.find({"groupId": group["id"]}))
    settlements = list(db.group_settlements.find({"groupId": group["id"]}))
    member_uids = group.get("memberUids", [])
    users = list(db.users.find({"uid": {"$in": member_uids}}))
    settlement_currencies = [settlement.get("currency") for settlement in settlements]
    currency_codes = group_currency_codes(group, expenses, settlement_currencies)
    display_data = compute_display_data(member_uids, expenses, group_member_aliases(member_uids, users), currency_codes, settlements)
    pending_invites = group_pending_invites(group)
    return json_ready(
        {
            **group,
            "currencyCodes": currency_codes,
            "memberCount": len(group.get("memberUids", [])),
            "pendingInvites": pending_invites,
            "pendingInviteCount": len(pending_invites),
            "displayData": display_data,
        }
    )


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


def normalize_split_amounts(raw: Any, member_uids: list[str], aliases: dict[str, str]) -> dict[str, float]:
    if not isinstance(raw, dict):
        return {}
    split_amounts: dict[str, float] = {}
    for raw_member, raw_amount in raw.items():
        member_uid = normalize_group_member_ref(raw_member, member_uids, aliases)
        if not member_uid:
            raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", "splitAmounts must contain only group members"))
        try:
            amount = round(float(raw_amount or 0), 4)
        except (TypeError, ValueError):
            raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", "splitAmounts must contain numeric amounts"))
        if amount <= 0:
            continue
        split_amounts[member_uid] = round(split_amounts.get(member_uid, 0.0) + amount, 4)
    return split_amounts


def split_amounts_by_currency(
    amount: float,
    split_amounts: dict[str, float],
    converted_amounts: dict[str, float],
) -> dict[str, dict[str, float]]:
    if amount <= 0 or not split_amounts:
        return {}
    by_currency: dict[str, dict[str, float]] = {}
    for currency, currency_amount in converted_amounts.items():
        ratio = float(currency_amount or 0) / amount
        by_currency[currency] = {
            uid: round(split_amount * ratio, 4)
            for uid, split_amount in split_amounts.items()
            if split_amount > 0
        }
    return by_currency


def split_shares_for_amount(
    expense: dict[str, Any],
    member_uids: list[str],
    aliases: dict[str, str],
    currency: str,
    amount: float,
) -> dict[str, float]:
    raw_by_currency = expense.get("splitAmountsByCurrency")
    if isinstance(raw_by_currency, dict):
        try:
            currency_amounts = normalize_split_amounts(raw_by_currency.get(currency), member_uids, aliases)
        except HTTPException:
            currency_amounts = {}
        if currency_amounts:
            return currency_amounts

    try:
        base_split_amounts = normalize_split_amounts(expense.get("splitAmounts"), member_uids, aliases)
    except HTTPException:
        base_split_amounts = {}
    if base_split_amounts:
        try:
            base_amount = float(expense.get("amount") or 0)
        except (TypeError, ValueError):
            base_amount = 0
        denominator = base_amount if base_amount > 0 else sum(base_split_amounts.values())
        if denominator > 0:
            ratio = amount / denominator
            return {
                uid: round(split_amount * ratio, 4)
                for uid, split_amount in base_split_amounts.items()
                if split_amount > 0
            }

    member_set = set(member_uids)
    split_with = [
        uid
        for uid in (normalize_group_member_ref(item, member_uids, aliases) for item in (expense.get("splitWith") or []))
        if uid in member_set
    ] or member_uids
    if not split_with:
        return {}
    share = amount / len(split_with)
    return {uid: share for uid in split_with}


def compute_display_data(
    member_uids: list[str],
    expenses: list[dict[str, Any]],
    aliases: dict[str, str] | None = None,
    currency_codes: list[str] | None = None,
    settlements: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    aliases = aliases or {}
    primary_currency = (currency_codes or ["INR"])[0]
    totals_by_currency = {currency: 0.0 for currency in (currency_codes or ["INR"])}
    balances_by_currency = {
        currency: {uid: {"owes": 0.0, "owed": 0.0, "net": 0.0} for uid in member_uids}
        for currency in (currency_codes or ["INR"])
    }
    member_set = set(member_uids)
    attachments = 0
    for expense in expenses:
        amounts_by_currency = expense_amounts_by_currency(expense)
        if not amounts_by_currency:
            continue
        split_with = [
            uid
            for uid in (normalize_group_member_ref(item, member_uids, aliases) for item in (expense.get("splitWith") or []))
            if uid in member_set
        ] or member_uids
        paid_by = normalize_group_member_ref(expense.get("paidBy") or expense.get("createdBy"), member_uids, aliases)
        attachments += len(expense.get("attachments") or [])
        if not paid_by:
            continue
        for currency, amount in amounts_by_currency.items():
            totals_by_currency[currency] = totals_by_currency.get(currency, 0.0) + amount
            balances = balances_by_currency.setdefault(
                currency,
                {uid: {"owes": 0.0, "owed": 0.0, "net": 0.0} for uid in member_uids},
            )
            split_shares = split_shares_for_amount(expense, member_uids, aliases, currency, amount)
            for uid, share in split_shares.items():
                balances.setdefault(uid, {"owes": 0.0, "owed": 0.0, "net": 0.0})
                if uid != paid_by:
                    balances[uid]["owes"] += share
                    balances[uid]["net"] -= share
                    balances.setdefault(paid_by, {"owes": 0.0, "owed": 0.0, "net": 0.0})
                    balances[paid_by]["owed"] += share
                    balances[paid_by]["net"] += share
    member_set = set(member_uids)
    for settlement in settlements or []:
        payer_uid = str(settlement.get("payerUid") or "")
        receiver_uid = str(settlement.get("receiverUid") or "")
        if payer_uid not in member_set or receiver_uid not in member_set:
            continue
        currency = safe_currency(settlement.get("currency"), primary_currency) or primary_currency
        try:
            amount = float(settlement.get("amount") or 0)
        except (TypeError, ValueError):
            continue
        if amount <= 0:
            continue
        totals_by_currency.setdefault(currency, totals_by_currency.get(currency, 0.0))
        balances = balances_by_currency.setdefault(
            currency,
            {uid: {"owes": 0.0, "owed": 0.0, "net": 0.0} for uid in member_uids},
        )
        balances.setdefault(payer_uid, {"owes": 0.0, "owed": 0.0, "net": 0.0})
        balances.setdefault(receiver_uid, {"owes": 0.0, "owed": 0.0, "net": 0.0})
        balances[payer_uid]["owed"] += amount
        balances[payer_uid]["net"] += amount
        balances[receiver_uid]["owes"] += amount
        balances[receiver_uid]["net"] -= amount
    primary_balances = balances_by_currency.get(primary_currency) or {uid: {"owes": 0.0, "owed": 0.0, "net": 0.0} for uid in member_uids}
    return {
        "expenseCount": len(expenses),
        "currency": primary_currency,
        "currencyCodes": sorted(totals_by_currency.keys()),
        "totalSpend": totals_by_currency.get(primary_currency, 0.0),
        "totalSpendByCurrency": totals_by_currency,
        "totalAttachments": attachments,
        "attachmentCounts": {},
        "memberBalances": primary_balances,
        "memberBalancesByCurrency": balances_by_currency,
        "updatedAt": iso(now()),
    }


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


def unpack_fx_rates(result: Any, quotes: list[str], provider: str = "custom") -> dict[str, Any]:
    rate_as_of = iso(now())
    raw_rates: dict[str, Any] = {}
    if isinstance(result, list):
        for item in result:
            if not isinstance(item, dict):
                continue
            quote = safe_currency(item.get("quote"), None)
            if quote:
                raw_rates[quote] = item.get("rate")
                rate_as_of = str(item.get("date") or rate_as_of)
                provider = str(item.get("provider") or provider)
    elif isinstance(result, dict):
        provider = str(result.get("provider") or provider)
        rate_as_of = str(result.get("rateAsOf") or result.get("date") or rate_as_of)
        rates = result.get("rates")
        if isinstance(rates, dict):
            raw_rates = rates
        else:
            raw_rates = {
                key: value
                for key, value in result.items()
                if key not in {"provider", "rateAsOf", "date", "base", "amount"}
            }
    rates_out: dict[str, float] = {}
    missing: list[str] = []
    for quote in quotes:
        try:
            rates_out[quote] = float(raw_rates[quote])
        except (KeyError, TypeError, ValueError):
            missing.append(quote)
    if missing:
        raise HTTPException(
            status_code=502,
            detail=api_error("FX_RATE_UNAVAILABLE", f"exchange rate unavailable for {', '.join(missing)}"),
        )
    return {"provider": provider, "rateAsOf": rate_as_of, "rates": rates_out}


async def fetch_fx_rates(app: FastAPI, base_currency: str, quote_currencies: list[str]) -> dict[str, Any]:
    quote_currencies = [currency for currency in quote_currencies if currency != base_currency]
    if not quote_currencies:
        return {"provider": "self", "rateAsOf": iso(now()), "rates": {}}
    fetcher = getattr(app.state, "fx_rate_fetcher", None)
    try:
        if fetcher is not None:
            result = fetcher(base_currency, quote_currencies)
            if hasattr(result, "__await__"):
                result = await result
            return unpack_fx_rates(result, quote_currencies)

        base_url = os.getenv("FX_BASE_URL", "https://api.frankfurter.dev/v2").rstrip("/")
        try:
            timeout = float(os.getenv("FX_TIMEOUT_SECONDS", "10"))
        except ValueError:
            timeout = 10.0
        async with httpx.AsyncClient(timeout=timeout) as client:
            response = await client.get(
                f"{base_url}/rates",
                params={"base": base_currency, "quotes": ",".join(quote_currencies)},
            )
            response.raise_for_status()
            return unpack_fx_rates(response.json(), quote_currencies, provider="frankfurter")
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(
            status_code=502,
            detail=api_error("FX_RATE_UNAVAILABLE", f"exchange rate lookup failed: {exc}"),
        ) from exc


async def conversion_snapshot(app: FastAPI, amount: float, currency: str, target_currencies: list[str]) -> dict[str, Any]:
    target_codes = sorted({*target_currencies, currency})
    quote_codes = [code for code in target_codes if code != currency]
    fetched = await fetch_fx_rates(app, currency, quote_codes)
    fetched_at = iso(now())
    converted_amounts: dict[str, float] = {}
    converted_details: dict[str, dict[str, Any]] = {}
    exchange_rates: dict[str, float] = {}
    for code in target_codes:
        rate = 1.0 if code == currency else float(fetched["rates"][code])
        converted = round(amount * rate, 4)
        provider = "self" if code == currency else fetched["provider"]
        converted_amounts[code] = converted
        exchange_rates[code] = rate
        converted_details[code] = {
            "amount": converted,
            "rate": rate,
            "rateAsOf": fetched["rateAsOf"] if code != currency else fetched_at,
            "provider": provider,
        }
    return {
        "convertedAmounts": converted_amounts,
        "convertedAmountDetails": converted_details,
        "exchangeRates": exchange_rates,
        "exchangeRateProvider": fetched["provider"] if quote_codes else "self",
        "exchangeRateFetchedAt": fetched_at,
        "exchangeRateAsOf": fetched["rateAsOf"],
    }


def sync_group_currency_codes(db: Any, group_id: str, currency_codes: list[str]) -> None:
    if currency_codes:
        db.groups.update_one({"id": group_id}, {"$set": {"currencyCodes": currency_codes, "updatedAt": now()}})


async def build_group_expense(
    app: FastAPI,
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
    currency = normalize_currency(body.get("currency") or group_currency_codes(group)[0])
    existing_expenses = list(db.group_expenses.find({"groupId": group["id"]}))
    requested_targets = requested_conversion_currencies(body)
    target_currencies = group_currency_codes(group, existing_expenses, [currency, *requested_targets])
    snapshot = await conversion_snapshot(app, amount, currency, target_currencies)
    sync_group_currency_codes(db, group["id"], target_currencies)
    member_uids = [str(item) for item in group.get("memberUids", []) if str(item)]
    aliases = group_member_aliases(member_uids, list(db.users.find({"uid": {"$in": member_uids}})))
    split_mode = str(body.get("splitMode") or "equally").strip().lower()
    supported_split_modes = {"equally", "custom", "exact", "percent", "shares", "adjustment"}
    if split_mode not in supported_split_modes:
        raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", "unsupported splitMode"))
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
    split_amounts = normalize_split_amounts(body.get("splitAmounts"), member_uids, aliases)
    if split_amounts:
        total_split = sum(split_amounts.values())
        if abs(total_split - amount) > 0.05:
            raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", "splitAmounts must add up to the expense amount"))
        split_with = list(split_amounts.keys())
    elif split_mode in {"exact", "percent", "shares", "adjustment"}:
        raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", "splitAmounts are required for this splitMode"))
    return {
        "id": expense_id or str(body.get("id") or "").strip() or uuid.uuid4().hex,
        "groupId": group["id"],
        "createdBy": created_by or uid,
        "updatedBy": uid,
        "paidBy": paid_by,
        "splitMode": split_mode,
        "splitWith": split_with,
        "splitAmounts": split_amounts,
        "splitAmountsByCurrency": split_amounts_by_currency(amount, split_amounts, snapshot["convertedAmounts"]),
        "amount": amount,
        "currency": currency,
        **snapshot,
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
