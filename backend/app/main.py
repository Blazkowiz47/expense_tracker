from __future__ import annotations

import calendar
import base64
import csv
import hashlib
import io
import json
import math
import mimetypes
import os
import re
import secrets
import shutil
import time
import unicodedata
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

from app.ai_prompts import load_prompt, load_prompt_json


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DATA_DIR = ROOT / "data"
ph = PasswordHasher()


def ai_terminal_log(event: str, **fields: Any) -> None:
    if os.getenv("AI_LOG_INTERACTIONS", "1").strip().lower() in {"0", "false", "no", "off"}:
        return
    payload = {
        "event": event,
        "at": iso(now()),
        **fields,
    }
    print("[ai] " + json.dumps(payload, default=str, ensure_ascii=False), flush=True)


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


_MISSING = object()


def body_first(body: dict[str, Any], names: tuple[str, ...], default: Any = _MISSING) -> Any:
    for name in names:
        if name in body:
            return body.get(name)
    if default is _MISSING:
        return None
    return default


def finite_number(value: Any, field: str) -> float:
    if isinstance(value, bool):
        raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", f"{field} must be a number"))
    if isinstance(value, str):
        value = value.strip().replace(",", "").replace(" ", "")
    try:
        parsed = float(value)
    except (TypeError, ValueError) as exc:
        raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", f"{field} must be a number")) from exc
    if not math.isfinite(parsed):
        raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", f"{field} must be finite"))
    return parsed


def positive_number(value: Any, field: str) -> float:
    parsed = finite_number(value, field)
    if parsed <= 0:
        raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", f"{field} must be positive"))
    return parsed


def non_negative_number(value: Any, field: str) -> float:
    parsed = finite_number(value, field)
    if parsed < 0:
        raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", f"{field} cannot be negative"))
    return parsed


def non_negative_int(value: Any, field: str) -> int:
    parsed = finite_number(value, field)
    if parsed < 0 or not parsed.is_integer():
        raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", f"{field} must be a non-negative integer"))
    return int(parsed)


def bounded_int(value: Any, field: str, minimum: int, maximum: int) -> int:
    parsed = finite_number(value, field)
    if not parsed.is_integer() or parsed < minimum or parsed > maximum:
        raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", f"{field} must be between {minimum} and {maximum}"))
    return int(parsed)


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
        "onboardingCompleted": bool(user.get("onboardingCompleted", False)),
    }


def require_json(body: dict[str, Any], *keys: str) -> None:
    missing = [key for key in keys if str(body.get(key, "")).strip() == ""]
    if missing:
        raise HTTPException(
            status_code=400,
            detail=api_error("INVALID_ARGUMENT", f"missing required fields: {', '.join(missing)}"),
        )


def parse_optional_float(value: Any) -> float | None:
    if value is None or isinstance(value, bool):
        return None
    if isinstance(value, str):
        value = value.strip().replace(",", ".")
        if not value:
            return None
        match = re.search(r"-?\d+(?:\.\d+)?", value)
        if not match:
            return None
        value = match.group(0)
    try:
        parsed = float(value)
    except (TypeError, ValueError):
        return None
    return parsed if math.isfinite(parsed) else None


def receipt_reference_date(original_name: str) -> datetime | None:
    match = re.search(r"(20\d{2})[-_. ](\d{2})[-_. ](\d{2})", original_name or "")
    if not match:
        return None
    try:
        return datetime(int(match.group(1)), int(match.group(2)), int(match.group(3)), tzinfo=UTC)
    except ValueError:
        return None


def normalize_receipt_date(raw_date: Any, original_name: str, warnings: list[str]) -> str:
    text = str(raw_date or "").strip()
    if not text:
        return ""
    iso_text = text.replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(iso_text)
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=UTC)
        return text if "T" in text else parsed.date().isoformat()
    except ValueError:
        pass

    parsed_date: datetime | None = None
    for pattern in ("%d.%m.%Y", "%d/%m/%Y", "%d-%m-%Y"):
        try:
            parsed_date = datetime.strptime(text, pattern).replace(tzinfo=UTC)
            break
        except ValueError:
            continue
    if parsed_date is None:
        warnings.append("Receipt date could not be parsed; date field stays editable.")
        return ""

    reference = receipt_reference_date(original_name) or now()
    corrected = parsed_date
    if parsed_date.year < reference.year - 1:
        candidate = parsed_date.replace(year=reference.year)
        if abs((candidate.date() - reference.date()).days) <= 45 and candidate.date() <= now().date() + timedelta(days=1):
            corrected = candidate
            warnings.append(f"Adjusted receipt year from {parsed_date.year} to {candidate.year}.")
    return corrected.date().isoformat()


def normalized_text(value: Any) -> str:
    text = str(value or "").strip().lower()
    text = unicodedata.normalize("NFKD", text)
    text = "".join(ch for ch in text if not unicodedata.combining(ch))
    text = re.sub(r"[^a-z0-9\s]+", " ", text)
    text = re.sub(r"\b\d+(?:[.,]\d+)?\s*(?:g|kg|ml|l|stk|pcs|pk|x)\b", " ", text)
    return re.sub(r"\s+", " ", text).strip()


ITEM_NAME_ALIASES = {
    "melk": "milk",
    "lettmelk": "milk",
    "helmelk": "milk",
    "milk": "milk",
    "doodh": "milk",
    "brod": "bread",
    "bread": "bread",
    "kylling": "chicken",
    "chicken": "chicken",
    "ris": "rice",
    "rice": "rice",
    "eggs": "egg",
    "egg": "egg",
    "banan": "banana",
    "banana": "banana",
    "potet": "potato",
    "potato": "potato",
    "tomat": "tomato",
    "tomato": "tomato",
    "lok": "onion",
    "onion": "onion",
}


def canonical_item_name(value: Any) -> str:
    cleaned = normalized_text(value)
    if not cleaned:
        return ""
    for token in cleaned.split():
        if token in ITEM_NAME_ALIASES:
            return ITEM_NAME_ALIASES[token]
    return ITEM_NAME_ALIASES.get(cleaned, cleaned)


def infer_receipt_unit(raw_unit: Any, quantity_raw: Any) -> str:
    unit = normalized_text(raw_unit)
    if unit in {"kilogram", "kilo", "kg"}:
        return "kg"
    if unit in {"gram", "grams", "g"}:
        return "g"
    if unit in {"liter", "litre", "liters", "litres", "l"}:
        return "l"
    if unit in {"milliliter", "millilitre", "milliliters", "millilitres", "ml"}:
        return "ml"
    if unit in {"stk", "pc", "pcs", "piece", "pieces", "each", "ea"}:
        return "each"
    quantity_text = str(quantity_raw or "").lower()
    match = re.search(r"\b(kg|g|ml|l|stk|pcs|pc)\b", quantity_text)
    if match:
        return infer_receipt_unit(match.group(1), None)
    return unit or "each"


def normalized_receipt_quantity(quantity: float | None, unit: str) -> tuple[float | None, str]:
    if quantity is None or quantity <= 0:
        return None, unit or "each"
    if unit == "g":
        return quantity / 1000, "kg"
    if unit == "ml":
        return quantity / 1000, "l"
    if unit in {"kg", "l"}:
        return quantity, unit
    return quantity, "each"


def normalize_receipt_line_item(raw: Any) -> dict[str, Any] | None:
    if not isinstance(raw, dict):
        return None
    original_text = str(raw.get("originalText") or raw.get("rawText") or raw.get("name") or raw.get("title") or "").strip()
    item_name = str(raw.get("itemName") or raw.get("name") or raw.get("title") or original_text).strip()
    normalized_name = canonical_item_name(raw.get("normalizedName") or item_name or original_text)
    if not item_name and not normalized_name:
        return None
    quantity_raw = raw.get("quantity")
    quantity = parse_optional_float(quantity_raw)
    unit = infer_receipt_unit(raw.get("unit"), quantity_raw)
    line_total = parse_optional_float(raw.get("lineTotal") if "lineTotal" in raw else raw.get("amount") or raw.get("total"))
    unit_price = parse_optional_float(raw.get("unitPrice") or raw.get("priceEach"))
    discount = parse_optional_float(raw.get("discount")) or 0.0
    normalized_quantity, normalized_unit = normalized_receipt_quantity(quantity, unit)
    normalized_unit_price = None
    if line_total is not None and normalized_quantity and normalized_quantity > 0:
        normalized_unit_price = round(line_total / normalized_quantity, 4)
    elif unit_price is not None:
        normalized_unit_price = unit_price
    confidence = parse_optional_float(raw.get("confidence"))
    if confidence is None:
        confidence = 0.7
    return {
        "originalText": original_text or item_name,
        "detectedLanguage": str(raw.get("detectedLanguage") or raw.get("language") or "").strip(),
        "itemName": item_name or normalized_name,
        "normalizedName": normalized_name,
        "brand": str(raw.get("brand") or "").strip(),
        "quantity": quantity,
        "unit": unit,
        "normalizedQuantity": normalized_quantity,
        "normalizedUnit": normalized_unit,
        "unitPrice": unit_price,
        "lineTotal": line_total,
        "discount": discount,
        "unitPriceNormalized": normalized_unit_price,
        "category": str(raw.get("category") or "").strip(),
        "confidence": max(0.0, min(confidence, 1.0)),
    }


def normalize_receipt_line_items(raw_items: Any) -> list[dict[str, Any]]:
    if not isinstance(raw_items, list):
        return []
    normalized = []
    for raw in raw_items[:200]:
        item = normalize_receipt_line_item(raw)
        if item:
            normalized.append(item)
    return normalized


def receipt_store_quirk_rules() -> list[dict[str, Any]]:
    data = load_prompt_json("receipt_store_quirks.json")
    rules = data.get("rules", [])
    return rules if isinstance(rules, list) else []


def text_matches_any_pattern(text: str, patterns: Any) -> bool:
    if not isinstance(patterns, list):
        return False
    for pattern in patterns:
        try:
            if re.search(str(pattern), text, re.IGNORECASE):
                return True
        except re.error:
            continue
    return False


def apply_receipt_store_quirks(merchant: str, line_items: list[dict[str, Any]], warnings: list[str]) -> list[dict[str, Any]]:
    filtered = line_items
    for rule in receipt_store_quirk_rules():
        if not isinstance(rule, dict) or rule.get("action") != "drop_line_item":
            continue
        if not text_matches_any_pattern(merchant, rule.get("merchantPatterns")):
            continue
        kept: list[dict[str, Any]] = []
        dropped = False
        for item in filtered:
            searchable = " ".join(
                str(item.get(key) or "")
                for key in ("originalText", "itemName", "normalizedName")
            )
            if text_matches_any_pattern(searchable, rule.get("lineItemOriginalTextPatterns")):
                dropped = True
                continue
            kept.append(item)
        if dropped:
            warning = str(rule.get("warning") or "").strip()
            if warning and warning not in warnings:
                warnings.append(warning)
        filtered = kept
    return filtered


class LocalGemmaBillExtractor:
    schema_version = "finance-ai-v1"

    def __init__(self, base_url: str | None, model: str):
        self.base_url = (base_url or "").strip()
        self.model = model

    async def extract(self, file_path: Path, original_name: str) -> dict[str, Any]:
        if self.base_url:
            payload = {"path": str(file_path), "fileName": original_name, "model": self.model}
            started = time.perf_counter()
            timeout = float(os.getenv("AI_RECEIPT_TIMEOUT_SECONDS", "180"))
            ai_terminal_log(
                "receipt.extract.request",
                provider="huggingface-sidecar",
                baseUrl=self.base_url,
                timeoutSeconds=timeout,
                payload=payload,
            )
            try:
                async with httpx.AsyncClient(timeout=timeout) as client:
                    response = await client.post(
                        self.base_url.rstrip("/") + "/api/v1/extract-bill",
                        json=payload,
                    )
                    elapsed_ms = round((time.perf_counter() - started) * 1000)
                    ai_terminal_log(
                        "receipt.extract.http_response",
                        provider="huggingface-sidecar",
                        statusCode=response.status_code,
                        elapsedMs=elapsed_ms,
                        body=response.text,
                    )
                    response.raise_for_status()
                    data = response.json()
                    if isinstance(data, dict):
                        normalized = self._normalize(data, original_name, [])
                        ai_terminal_log(
                            "receipt.extract.normalized",
                            provider="huggingface-sidecar",
                            elapsedMs=round((time.perf_counter() - started) * 1000),
                            result=normalized,
                        )
                        return normalized
            except Exception as exc:  # pragma: no cover - exercised through fake provider tests
                ai_terminal_log(
                    "receipt.extract.error",
                    provider="huggingface-sidecar",
                    elapsedMs=round((time.perf_counter() - started) * 1000),
                    error=repr(exc),
                )
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
        merchant = str(raw.get("merchant") or Path(original_name).stem or "Uploaded bill").strip()
        line_items = apply_receipt_store_quirks(
            merchant,
            normalize_receipt_line_items(raw.get("lineItems")),
            warnings,
        )
        date = normalize_receipt_date(raw.get("date"), original_name, warnings)
        currency = str(raw.get("currency") or "INR")
        category = str(raw.get("category") or "Personal")
        notes = str(raw.get("notes") or "")
        result = {
            "task": "receipt_extraction",
            "schemaVersion": self.schema_version,
            "merchant": merchant,
            "date": date,
            "amount": amount,
            "currency": currency,
            "category": category,
            "notes": notes,
            "lineItems": line_items,
            "confidence": max(0.0, min(float(raw.get("confidence") or 0), 1.0)),
            "warnings": warnings + [str(item) for item in raw.get("warnings", []) if str(item).strip()],
        }
        result["expenseDraft"] = {
            "description": merchant,
            "amount": amount,
            "currency": currency,
            "category": category,
            "date": date,
            "notes": notes,
            "receiptItems": line_items,
        }
        return result

    async def dashboard_summary(self, context: dict[str, Any]) -> dict[str, Any]:
        fallback = fallback_ai_dashboard_summary(context)
        return await self._complete_structured(
            "dashboard_summary",
            context,
            (
                "Write two concise finance summary cards for the home screen. "
                "Use the provided finance-context-v1 packet; do not request raw transactions. "
                "Return JSON with cards: [{label, message, tone, actions}]. "
                "Use tone positive, warning, critical, or neutral. Keep each message under 150 characters."
            ),
            fallback,
        )

    async def finance_chat(self, context: dict[str, Any], question: str) -> dict[str, Any]:
        fallback = fallback_ai_finance_chat(context, question)
        payload = {**context, "question": question}
        return await self._complete_structured(
            "finance_chat",
            payload,
            (
                "Answer a personal finance planning question for an expense tracker. "
                "Use the provided finance-context-v1 packet; backend math is authoritative. "
                "Return JSON with question, title, answer, steps, and suggestions. "
                "steps must be short actionable strings. Use only facts in the provided context."
            ),
            fallback,
        )

    async def _complete_structured(
        self,
        task: str,
        context: dict[str, Any],
        instructions: str,
        fallback: dict[str, Any],
    ) -> dict[str, Any]:
        if not self.base_url:
            return with_ai_warning(fallback, "Local Gemma provider is not configured.")
        payload = {
            "task": task,
            "schemaVersion": self.schema_version,
            "model": self.model,
            "instructions": instructions,
            "context": context,
        }
        started = time.perf_counter()
        ai_terminal_log(
            "structured.request",
            provider="huggingface-sidecar",
            baseUrl=self.base_url,
            timeoutSeconds=90,
            payload=payload,
        )
        try:
            async with httpx.AsyncClient(timeout=90) as client:
                response = await client.post(
                    self.base_url.rstrip("/") + "/api/v1/finance-ai",
                    json=payload,
                )
                ai_terminal_log(
                    "structured.http_response",
                    provider="huggingface-sidecar",
                    task=task,
                    statusCode=response.status_code,
                    elapsedMs=round((time.perf_counter() - started) * 1000),
                    body=response.text,
                )
                response.raise_for_status()
                data = response.json()
                normalized = normalize_structured_ai_response(task, data, fallback)
                ai_terminal_log(
                    "structured.normalized",
                    provider="huggingface-sidecar",
                    task=task,
                    elapsedMs=round((time.perf_counter() - started) * 1000),
                    result=normalized,
                )
                return normalized
        except Exception as exc:  # pragma: no cover - exercised through fake provider tests
            ai_terminal_log(
                "structured.error",
                provider="huggingface-sidecar",
                task=task,
                elapsedMs=round((time.perf_counter() - started) * 1000),
                error=repr(exc),
            )
            return with_ai_warning(fallback, f"Local Gemma provider unavailable: {exc}")


class LlamaServerBillExtractor(LocalGemmaBillExtractor):
    def __init__(self, base_url: str | None, model: str):
        super().__init__(base_url, model)

    async def extract(self, file_path: Path, original_name: str) -> dict[str, Any]:
        if not self.base_url:
            return self._fallback(original_name, ["Local llama-server provider is not configured."])
        system_prompt = load_prompt("receipt_extraction_system.md")
        user_prompt = load_prompt("receipt_extraction_user.md")
        started = time.perf_counter()
        try:
            data_url = self._file_data_url(file_path, original_name)
            log_payload = {
                "model": self.model,
                "temperature": 0,
                "messages": [
                    {"role": "system", "content": system_prompt},
                    {
                        "role": "user",
                        "content": [
                            {"type": "image_url", "image_url": {"url": f"[redacted {len(data_url)} chars data URL]"}},
                            {"type": "text", "text": user_prompt},
                        ],
                    },
                ],
            }
            ai_terminal_log(
                "receipt.extract.request",
                provider="llama-server",
                baseUrl=self.base_url,
                timeoutSeconds=120,
                payload=log_payload,
            )
            async with httpx.AsyncClient(timeout=120) as client:
                response = await client.post(
                    self.base_url.rstrip("/") + "/v1/chat/completions",
                    json={
                        "model": self.model,
                        "temperature": 0,
                        "messages": [
                            {
                                "role": "system",
                                "content": system_prompt,
                            },
                            {
                                "role": "user",
                                "content": [
                                    {"type": "image_url", "image_url": {"url": data_url}},
                                    {
                                        "type": "text",
                                        "text": user_prompt,
                                    },
                                ],
                            },
                        ],
                    },
                )
                ai_terminal_log(
                    "receipt.extract.http_response",
                    provider="llama-server",
                    statusCode=response.status_code,
                    elapsedMs=round((time.perf_counter() - started) * 1000),
                    body=response.text,
                )
                response.raise_for_status()
                content = response.json()["choices"][0]["message"]["content"]
                ai_terminal_log(
                    "receipt.extract.raw_model_text",
                    provider="llama-server",
                    elapsedMs=round((time.perf_counter() - started) * 1000),
                    content=content,
                )
                normalized = self._normalize(parse_model_json(content), original_name, [])
                ai_terminal_log(
                    "receipt.extract.normalized",
                    provider="llama-server",
                    elapsedMs=round((time.perf_counter() - started) * 1000),
                    result=normalized,
                )
                return normalized
        except Exception as exc:  # pragma: no cover - network path is covered by integration tests
            ai_terminal_log(
                "receipt.extract.error",
                provider="llama-server",
                elapsedMs=round((time.perf_counter() - started) * 1000),
                error=repr(exc),
            )
            return self._fallback(original_name, [f"Local llama-server provider unavailable: {exc}"])

    def _file_data_url(self, file_path: Path, original_name: str) -> str:
        mime_type = mimetypes.guess_type(original_name)[0] or "application/octet-stream"
        encoded = base64.b64encode(file_path.read_bytes()).decode("ascii")
        return f"data:{mime_type};base64,{encoded}"

    async def _complete_structured(
        self,
        task: str,
        context: dict[str, Any],
        instructions: str,
        fallback: dict[str, Any],
    ) -> dict[str, Any]:
        if not self.base_url:
            return with_ai_warning(fallback, "Local llama-server provider is not configured.")
        system_prompt = load_prompt("structured_json_system.md").format(
            schema_version=self.schema_version,
            instructions=instructions,
        )
        payload = {
            "model": self.model,
            "temperature": 0.2,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": json.dumps(context, default=str)},
            ],
        }
        started = time.perf_counter()
        ai_terminal_log(
            "structured.request",
            provider="llama-server",
            task=task,
            baseUrl=self.base_url,
            timeoutSeconds=90,
            payload=payload,
        )
        try:
            async with httpx.AsyncClient(timeout=90) as client:
                response = await client.post(
                    self.base_url.rstrip("/") + "/v1/chat/completions",
                    json=payload,
                )
                ai_terminal_log(
                    "structured.http_response",
                    provider="llama-server",
                    task=task,
                    statusCode=response.status_code,
                    elapsedMs=round((time.perf_counter() - started) * 1000),
                    body=response.text,
                )
                response.raise_for_status()
                content = response.json()["choices"][0]["message"]["content"]
                ai_terminal_log(
                    "structured.raw_model_text",
                    provider="llama-server",
                    task=task,
                    elapsedMs=round((time.perf_counter() - started) * 1000),
                    content=content,
                )
                normalized = normalize_structured_ai_response(task, parse_model_json(content), fallback)
                ai_terminal_log(
                    "structured.normalized",
                    provider="llama-server",
                    task=task,
                    elapsedMs=round((time.perf_counter() - started) * 1000),
                    result=normalized,
                )
                return normalized
        except Exception as exc:  # pragma: no cover - network path is covered by integration tests
            ai_terminal_log(
                "structured.error",
                provider="llama-server",
                task=task,
                elapsedMs=round((time.perf_counter() - started) * 1000),
                error=repr(exc),
            )
            return with_ai_warning(fallback, f"Local llama-server provider unavailable: {exc}")


def parse_model_json(content: Any) -> dict[str, Any]:
    if isinstance(content, dict):
        return content
    text = str(content or "").strip()
    if text.startswith("```"):
        text = re.sub(r"^```(?:json)?\s*", "", text)
        text = re.sub(r"\s*```$", "", text).strip()
    text = repair_model_json_text(text)
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError:
        match = re.search(r"\{.*\}", text, re.DOTALL)
        if not match:
            raise
        parsed = json.loads(repair_model_json_text(match.group(0)))
    if not isinstance(parsed, dict):
        raise ValueError("model response must be a JSON object")
    return parsed


def repair_model_json_text(text: str) -> str:
    text = re.sub(r"(:\s*-?\d+)\.(?=\s*[,}\]])", r"\1.0", text)
    text = re.sub(r",+(?=\s*,)", "", text)
    text = re.sub(r",+(\s*[}\]])", r"\1", text)
    return text


def ai_base_response(task: str) -> dict[str, Any]:
    return {"task": task, "schemaVersion": LocalGemmaBillExtractor.schema_version, "generatedAt": iso(now())}


def with_ai_warning(payload: dict[str, Any], warning: str) -> dict[str, Any]:
    warnings = [str(item) for item in payload.get("warnings", []) if str(item).strip()]
    warnings.append(warning)
    return {**payload, "warnings": warnings}


def normalize_ai_tone(value: Any) -> str:
    tone = str(value or "neutral").strip().lower()
    return tone if tone in {"positive", "warning", "critical", "neutral"} else "neutral"


def normalize_ai_actions(raw: Any) -> list[dict[str, str]]:
    if not isinstance(raw, list):
        return []
    actions = []
    for item in raw[:2]:
        if not isinstance(item, dict):
            continue
        label = str(item.get("label") or "").strip()
        prompt = str(item.get("prompt") or item.get("question") or "").strip()
        if label:
            actions.append({"label": label[:40], "prompt": prompt[:160]})
    return actions


def normalize_structured_ai_response(task: str, raw: dict[str, Any], fallback: dict[str, Any]) -> dict[str, Any]:
    if task == "dashboard_summary":
        cards = []
        for item in raw.get("cards", []) if isinstance(raw.get("cards"), list) else []:
            if not isinstance(item, dict):
                continue
            message = str(item.get("message") or item.get("summary") or "").strip()
            if not message:
                continue
            cards.append({
                "label": str(item.get("label") or "AI summary").strip()[:40],
                "message": message[:240],
                "tone": normalize_ai_tone(item.get("tone")),
                "actions": normalize_ai_actions(item.get("actions")),
            })
        if not cards:
            cards = fallback.get("cards", [])
        return {**ai_base_response(task), "cards": cards[:2], "warnings": [str(item) for item in raw.get("warnings", []) if str(item).strip()]}
    if task == "finance_chat":
        steps = [str(item).strip() for item in raw.get("steps", []) if str(item).strip()] if isinstance(raw.get("steps"), list) else []
        suggestions = [str(item).strip() for item in raw.get("suggestions", []) if str(item).strip()] if isinstance(raw.get("suggestions"), list) else []
        answer = str(raw.get("answer") or "").strip()
        if not answer:
            answer = str(fallback.get("answer") or "")
        return {
            **ai_base_response(task),
            "question": str(raw.get("question") or fallback.get("question") or "").strip(),
            "title": str(raw.get("title") or fallback.get("title") or "AI plan").strip()[:80],
            "answer": answer[:600],
            "steps": (steps or fallback.get("steps", []))[:5],
            "suggestions": (suggestions or fallback.get("suggestions", []))[:4],
            "warnings": [str(item) for item in raw.get("warnings", []) if str(item).strip()],
        }
    return fallback


def fallback_ai_dashboard_summary(context: dict[str, Any]) -> dict[str, Any]:
    overall = context.get("overall") if isinstance(context.get("overall"), dict) else {}
    plan = context.get("monthlyPlan") if isinstance(context.get("monthlyPlan"), dict) else {}
    action_items = context.get("actionItems") if isinstance(context.get("actionItems"), list) else []
    currency = str(plan.get("currency") or "INR")
    total_budget = float(plan.get("totalBudget") or 0)
    total_actual = float(plan.get("totalActual") or 0)
    total_remaining = float(plan.get("totalRemaining") or 0)
    budget_message = (
        f"{format_currency_amount(currency, total_actual)} spent so far of your "
        f"{format_currency_amount(currency, total_budget)} planned budget this month."
        if total_budget > 0
        else f"{overall.get('overallLabel') or 'Summary'}. {overall.get('overallAmountText') or 'No spend yet'}."
    )
    if total_budget > 0 and total_remaining >= 0:
        budget_message += f" {format_currency_amount(currency, total_remaining)} remains."
    attention_message = (
        "No follow-ups are waiting. Your receipts, recurring reminders, and shared balances are quiet."
        if not action_items
        else f"{len(action_items)} {'item needs' if len(action_items) == 1 else 'items need'} attention. Start with {action_items[0].get('title') or 'the first item'}."
    )
    return {
        **ai_base_response("dashboard_summary"),
        "cards": [
            {"label": "AI summary", "message": budget_message, "tone": "positive", "actions": [{"label": "Regenerate", "prompt": "Refresh my monthly summary"}]},
            {"label": "AI summary", "message": attention_message, "tone": "neutral" if not action_items else "warning", "actions": [{"label": "Ask a follow-up", "prompt": "What should I handle first?"}]},
        ],
        "warnings": [],
    }


def fallback_ai_finance_chat(context: dict[str, Any], question: str) -> dict[str, Any]:
    plan = context.get("monthlyPlan") if isinstance(context.get("monthlyPlan"), dict) else {}
    currency = str(plan.get("currency") or "INR")
    remaining = float(plan.get("totalRemaining") or 0)
    categories = [item for item in plan.get("categories", []) if isinstance(item, dict)] if isinstance(plan.get("categories"), list) else []
    largest = max(categories, key=lambda item: float(item.get("budget") or 0), default={})
    steps = [
        f"Use your current surplus of {format_currency_amount(currency, max(remaining, 0))} as the planning limit.",
        "Keep required bills and recurring commitments funded before adding new goals.",
        f"Review {largest.get('category') or 'your largest category'} first if you need to free up cash.",
    ]
    return {
        **ai_base_response("finance_chat"),
        "question": question,
        "title": "AI plan",
        "answer": "Here is a conservative plan based on your current budget, expenses, and open follow-ups.",
        "steps": steps,
        "suggestions": [
            "Save NOK 50,000 by December",
            "Can I afford a NOK 30,000 laptop?",
            "Cut my monthly spending",
        ],
        "warnings": [],
    }


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
        ensure_setup_month_activity_entries(app.state.db, user["uid"])
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

    @app.post("/api/v1/auth/firebase")
    def firebase_login(body: dict[str, Any]) -> dict[str, Any]:
        require_json(body, "idToken")
        claims = verify_firebase_claims(app, str(body["idToken"]))
        user = find_or_create_firebase_user(app.state.db, claims)
        accepted_invites = accept_pending_group_invites(app.state.db, user)
        token = create_session(app.state.db, user["uid"])
        return {"token": token, "user": user_public(user), "acceptedGroupInvites": accepted_invites}

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

    @app.put("/api/v1/profile/onboarding")
    def update_onboarding(body: dict[str, Any], user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
        completed = bool(body.get("completed", True))
        app.state.db.users.update_one(
            {"uid": user["uid"]},
            {"$set": {"onboardingCompleted": completed, "updatedAt": now()}},
        )
        return user_public(app.state.db.users.find_one({"uid": user["uid"]}))

    @app.post("/api/v1/profile/photo")
    async def upload_profile_photo(file: UploadFile = File(...), user: dict[str, Any] = Depends(current_user)) -> dict[str, str]:
        url = await save_upload(app, file, f"users/{user['uid']}")
        app.state.db.users.update_one({"uid": user["uid"]}, {"$set": {"photoUrl": url, "updatedAt": now()}})
        return {"url": url}

    @app.get("/api/v1/accounts")
    def list_financial_accounts(
        includeArchived: bool = False,
        user: dict[str, Any] = Depends(current_user),
    ) -> dict[str, Any]:
        filters: dict[str, Any] = {"uid": user["uid"]}
        if not includeArchived:
            filters["archivedAt"] = {"$exists": False}
        docs = list(app.state.db.financial_accounts.find(filters).sort("updatedAt", DESCENDING))
        return {"accounts": [financial_account_out(doc) for doc in docs]}

    @app.post("/api/v1/accounts", status_code=201)
    def create_financial_account(body: dict[str, Any], user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
        account = build_financial_account(body, user["uid"])
        app.state.db.financial_accounts.insert_one(account)
        return financial_account_out(account)

    @app.put("/api/v1/accounts/{account_id}")
    def update_financial_account(account_id: str, body: dict[str, Any], user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
        existing = app.state.db.financial_accounts.find_one({"id": account_id, "uid": user["uid"]})
        if not existing:
            raise HTTPException(status_code=404, detail=api_error("NOT_FOUND", "account not found"))
        updated = build_financial_account(
            {**existing, **body},
            user["uid"],
            account_id=account_id,
            created_at=existing.get("createdAt"),
            archived_at=existing.get("archivedAt"),
        )
        app.state.db.financial_accounts.replace_one({"id": account_id, "uid": user["uid"]}, updated)
        return financial_account_out(updated)

    @app.delete("/api/v1/accounts/{account_id}", status_code=204)
    def archive_financial_account(account_id: str, user: dict[str, Any] = Depends(current_user)) -> Response:
        existing = app.state.db.financial_accounts.find_one({"id": account_id, "uid": user["uid"]})
        if not existing:
            raise HTTPException(status_code=404, detail=api_error("NOT_FOUND", "account not found"))
        app.state.db.financial_accounts.update_one(
            {"id": account_id, "uid": user["uid"]},
            {"$set": {"archivedAt": now(), "updatedAt": now()}},
        )
        return Response(status_code=204)

    @app.get("/api/v1/credit-cards")
    def list_credit_cards(
        includeArchived: bool = False,
        user: dict[str, Any] = Depends(current_user),
    ) -> dict[str, Any]:
        filters: dict[str, Any] = {"uid": user["uid"]}
        if not includeArchived:
            filters["archivedAt"] = {"$exists": False}
        docs = list(app.state.db.credit_cards.find(filters).sort("updatedAt", DESCENDING))
        return {"cards": [credit_card_out(app.state.db, doc) for doc in docs]}

    @app.post("/api/v1/credit-cards", status_code=201)
    def create_credit_card(body: dict[str, Any], user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
        card = build_credit_card(body, user["uid"])
        app.state.db.credit_cards.insert_one(card)
        return credit_card_out(app.state.db, card)

    @app.put("/api/v1/credit-cards/{card_id}")
    def update_credit_card(card_id: str, body: dict[str, Any], user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
        existing = app.state.db.credit_cards.find_one({"id": card_id, "uid": user["uid"]})
        if not existing:
            raise HTTPException(status_code=404, detail=api_error("NOT_FOUND", "credit card not found"))
        updated = build_credit_card(
            {**existing, **body},
            user["uid"],
            card_id=card_id,
            created_at=existing.get("createdAt"),
            archived_at=existing.get("archivedAt"),
        )
        app.state.db.credit_cards.replace_one({"id": card_id, "uid": user["uid"]}, updated)
        return credit_card_out(app.state.db, updated)

    @app.delete("/api/v1/credit-cards/{card_id}", status_code=204)
    def archive_credit_card(card_id: str, user: dict[str, Any] = Depends(current_user)) -> Response:
        existing = app.state.db.credit_cards.find_one({"id": card_id, "uid": user["uid"]})
        if not existing:
            raise HTTPException(status_code=404, detail=api_error("NOT_FOUND", "credit card not found"))
        current = now()
        app.state.db.credit_cards.update_one(
            {"id": card_id, "uid": user["uid"]},
            {"$set": {"archivedAt": current, "updatedAt": current}},
        )
        return Response(status_code=204)

    @app.post("/api/v1/credit-cards/{card_id}/spend", status_code=201)
    def log_credit_card_spend(card_id: str, body: dict[str, Any], user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
        card = app.state.db.credit_cards.find_one({
            "id": card_id,
            "uid": user["uid"],
            "archivedAt": {"$exists": False},
        })
        if not card:
            raise HTTPException(status_code=404, detail=api_error("NOT_FOUND", "active credit card not found"))
        amount = positive_number(body.get("amount"), "amount")
        card_currency = normalize_currency(card.get("currency"), "NOK")
        expense = build_expense(
            {
                "amount": amount,
                "currency": card_currency,
                "category": str(body.get("category") or "Personal").strip() or "Personal",
                "description": str(body.get("description") or card.get("name") or "Credit card spend").strip(),
                "date": str(body.get("date") or iso(now())),
                "paymentMethod": "card",
                "sourceType": "credit_card_spend",
                "sourceCreditCardId": card_id,
            },
            user["uid"],
        )
        current = now()
        app.state.db.expenses.insert_one(expense)
        app.state.db.credit_cards.update_one(
            {"id": card_id, "uid": user["uid"]},
            {
                "$inc": {"currentBalance": amount},
                "$set": {"balanceAsOf": expense["date"], "updatedAt": current},
            },
        )
        updated_card = app.state.db.credit_cards.find_one({"id": card_id, "uid": user["uid"]}) or card
        return {
            "card": credit_card_out(app.state.db, updated_card),
            "expense": expense_out(expense),
        }

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
        ensure_setup_month_activity_entries(app.state.db, user["uid"])
        filters: dict[str, Any] = {"uid": user["uid"]}
        if category.strip():
            filters["category"] = category.strip()
        add_date_filter(filters, from_, to)
        docs = list(app.state.db.expenses.find(filters).sort("date", -1).skip(max(page - 1, 0) * limit).limit(max(1, min(limit, 1000))))
        return {"expenses": [expense_out(doc) for doc in docs]}

    @app.post("/api/v1/expenses", status_code=201)
    def create_expense(body: dict[str, Any], user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
        expense = build_expense(body, user["uid"])
        if expense.get("sourceType") == "setup_month_entry" and expense.get("sourcePeriod") and expense.get("sourceSetupKey"):
            existing = app.state.db.expenses.find_one({
                "uid": user["uid"],
                "sourceType": "setup_month_entry",
                "sourcePeriod": expense["sourcePeriod"],
                "sourceSetupKey": expense["sourceSetupKey"],
            })
            if existing:
                expense["id"] = existing["id"]
                expense["createdAt"] = existing.get("createdAt") or expense["createdAt"]
                app.state.db.expenses.replace_one({"id": expense["id"], "uid": user["uid"]}, expense)
                return expense_out(expense)
        app.state.db.expenses.insert_one(expense)
        if receipt_items_in_body(body):
            save_receipt_items_for_source(
                app.state.db,
                user=user,
                source_type="personal",
                expense=expense,
                raw_items=body_receipt_items(body),
                bill_job_id=str(body.get("billJobId") or ""),
            )
        return expense_out(expense)

    @app.put("/api/v1/expenses/{expense_id}")
    def update_expense(expense_id: str, body: dict[str, Any], user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
        existing = app.state.db.expenses.find_one({"id": expense_id, "uid": user["uid"]})
        if not existing:
            raise HTTPException(status_code=404, detail=api_error("NOT_FOUND", "expense not found"))
        if is_loan_payment_expense(existing):
            raise HTTPException(status_code=409, detail=api_error("LINKED_RECORD", "loan payment expenses must be updated from Loans"))
        updated = build_expense({**existing, **body}, user["uid"], expense_id=expense_id, created_at=existing["createdAt"])
        reconcile_credit_card_expense_update(app.state.db, user["uid"], existing, updated)
        app.state.db.expenses.replace_one({"id": expense_id, "uid": user["uid"]}, updated)
        if receipt_items_in_body(body):
            save_receipt_items_for_source(
                app.state.db,
                user=user,
                source_type="personal",
                expense=updated,
                raw_items=body_receipt_items(body),
                bill_job_id=str(body.get("billJobId") or ""),
            )
        return expense_out(updated)

    @app.delete("/api/v1/expenses/{expense_id}", status_code=204)
    def delete_expense(expense_id: str, user: dict[str, Any] = Depends(current_user)) -> Response:
        existing = app.state.db.expenses.find_one({"id": expense_id, "uid": user["uid"]})
        if not existing:
            raise HTTPException(status_code=404, detail=api_error("NOT_FOUND", "expense not found"))
        if is_loan_payment_expense(existing):
            raise HTTPException(status_code=409, detail=api_error("LINKED_RECORD", "loan payment expenses must be deleted from Loans"))
        reconcile_credit_card_expense_delete(app.state.db, user["uid"], existing)
        record_expense_tombstone(app.state.db, existing, user["uid"])
        result = app.state.db.expenses.delete_one({"id": expense_id, "uid": user["uid"]})
        if result.deleted_count == 0:
            raise HTTPException(status_code=404, detail=api_error("NOT_FOUND", "expense not found"))
        app.state.db.receipt_items.delete_many({"sourceType": "personal", "expenseId": expense_id, "uid": user["uid"]})
        return Response(status_code=204)

    @app.get("/api/v1/receipt-items")
    def list_receipt_items(
        q: str = "",
        normalizedName: str = "",
        currency: str = "",
        limit: int = Query(default=80, ge=1, le=300),
        user: dict[str, Any] = Depends(current_user),
    ) -> dict[str, Any]:
        filters = visible_receipt_item_filter(app.state.db, user["uid"])
        item_filter = receipt_item_query_filter(q, normalizedName, currency)
        if item_filter:
            filters = {"$and": [filters, item_filter]}
        docs = list(app.state.db.receipt_items.find(filters).sort("date", DESCENDING).limit(limit))
        return {"items": [receipt_item_out(doc) for doc in docs]}

    @app.get("/api/v1/receipt-items/compare")
    def compare_receipt_items(
        q: str = "",
        normalizedName: str = "",
        currency: str = "",
        limit: int = Query(default=80, ge=1, le=300),
        user: dict[str, Any] = Depends(current_user),
    ) -> dict[str, Any]:
        filters = visible_receipt_item_filter(app.state.db, user["uid"])
        item_filter = receipt_item_query_filter(q, normalizedName, currency)
        if item_filter:
            filters = {"$and": [filters, item_filter]}
        docs = [
            doc
            for doc in app.state.db.receipt_items.find(filters).sort("date", DESCENDING).limit(limit * 2)
            if doc.get("unitPriceNormalized") is not None
        ][:limit]
        return receipt_item_comparison_out(q or normalizedName, docs)

    @app.get("/api/v1/loans")
    def list_loans(
        includeArchived: bool = False,
        user: dict[str, Any] = Depends(current_user),
    ) -> dict[str, Any]:
        filters: dict[str, Any] = {"uid": user["uid"]}
        if not includeArchived:
            filters["archivedAt"] = {"$exists": False}
        docs = list(app.state.db.loans.find(filters).sort("updatedAt", DESCENDING))
        return {"loans": [loan_out(app.state.db, doc) for doc in docs]}

    @app.post("/api/v1/loans", status_code=201)
    def create_loan(body: dict[str, Any], user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
        loan = build_loan(body, user["uid"])
        app.state.db.loans.insert_one(loan)
        return loan_out(app.state.db, loan)

    @app.put("/api/v1/loans/{loan_id}")
    def update_loan(loan_id: str, body: dict[str, Any], user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
        existing = app.state.db.loans.find_one({"id": loan_id, "uid": user["uid"]})
        if not existing:
            raise HTTPException(status_code=404, detail=api_error("NOT_FOUND", "loan not found"))
        updated = build_loan(
            {**existing, **body},
            user["uid"],
            loan_id=loan_id,
            created_at=existing.get("createdAt"),
            archived_at=existing.get("archivedAt"),
        )
        if existing.get("lastPaymentAt"):
            updated["lastPaymentAt"] = existing.get("lastPaymentAt")
        app.state.db.loans.replace_one({"id": loan_id, "uid": user["uid"]}, updated)
        return loan_out(app.state.db, updated)

    @app.delete("/api/v1/loans/{loan_id}", status_code=204)
    def archive_loan(loan_id: str, user: dict[str, Any] = Depends(current_user)) -> Response:
        existing = app.state.db.loans.find_one({"id": loan_id, "uid": user["uid"]})
        if not existing:
            raise HTTPException(status_code=404, detail=api_error("NOT_FOUND", "loan not found"))
        current = now()
        app.state.db.loans.update_one(
            {"id": loan_id, "uid": user["uid"]},
            {"$set": {"archivedAt": current, "updatedAt": current}},
        )
        return Response(status_code=204)

    @app.get("/api/v1/loans/{loan_id}/payments")
    def list_loan_payments(loan_id: str, user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
        loan = app.state.db.loans.find_one({"id": loan_id, "uid": user["uid"]})
        if not loan:
            raise HTTPException(status_code=404, detail=api_error("NOT_FOUND", "loan not found"))
        docs = app.state.db.loan_payments.find({"loanId": loan_id, "uid": user["uid"]}).sort("date", DESCENDING)
        return {"payments": [loan_payment_out(doc) for doc in docs]}

    @app.post("/api/v1/loans/{loan_id}/payments", status_code=201)
    def log_loan_payment(loan_id: str, body: dict[str, Any], user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
        loan = app.state.db.loans.find_one({
            "id": loan_id,
            "uid": user["uid"],
            "archivedAt": {"$exists": False},
        })
        if not loan:
            raise HTTPException(status_code=404, detail=api_error("NOT_FOUND", "active loan not found"))
        payment_type = str(body.get("paymentType") or "emi").strip().lower()
        if payment_type not in {"emi", "prepayment"}:
            raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", "paymentType must be emi or prepayment"))
        amount = (
            positive_number(body.get("amount"), "amount")
            if "amount" in body
            else positive_number(loan.get("emiAmount"), "emiAmount")
        )
        payment_date = parse_dt(str(body.get("date") or iso(loan_next_due_date(app.state.db, loan) or now())))
        period = f"{payment_date.year:04d}-{payment_date.month:02d}"
        current = now()
        existing_payment = None
        emi_key = ""
        if payment_type == "emi":
            emi_key = loan_emi_key(user["uid"], loan_id, period)
            existing_payment = app.state.db.loan_payments.find_one({
                "uid": user["uid"],
                "loanId": loan_id,
                "paymentType": "emi",
                "period": period,
            }) or app.state.db.loan_payments.find_one({
                "uid": user["uid"],
                "loanId": loan_id,
                "emiKey": emi_key,
            })
        payment_id = (
            (existing_payment or {}).get("id")
            or (stable_loan_hex(user["uid"], loan_id, period, "emi", "payment") if payment_type == "emi" else uuid.uuid4().hex)
        )
        expense_id = (
            (existing_payment or {}).get("expenseId")
            or (stable_loan_hex(user["uid"], loan_id, period, "emi", "expense") if payment_type == "emi" else uuid.uuid4().hex)
        )
        description_prefix = "Loan EMI" if payment_type == "emi" else "Loan prepayment"
        expense = build_expense(
            {
                "amount": amount,
                "currency": loan.get("currency") or "INR",
                "category": loan.get("category") or "Loans / EMI",
                "description": str(body.get("description") or f"{description_prefix}: {loan.get('name') or 'Loan'}").strip(),
                "date": iso(payment_date),
                "paymentMethod": "loan",
                "sourceType": "loan_payment",
                "sourceLoanId": loan_id,
                "sourceLoanPaymentId": payment_id,
                "sourcePaymentType": payment_type,
                "sourcePeriod": period,
            },
            user["uid"],
            expense_id=expense_id,
            created_at=(existing_payment or {}).get("createdAt"),
        )
        app.state.db.expenses.replace_one({"id": expense["id"], "uid": user["uid"]}, expense, upsert=True)
        payment = {
            "id": payment_id,
            "uid": user["uid"],
            "loanId": loan_id,
            "paymentType": payment_type,
            "period": period,
            **({"emiKey": emi_key} if emi_key else {}),
            "amount": amount,
            "currency": loan.get("currency") or "INR",
            "date": payment_date,
            "expenseId": expense["id"],
            "notes": str(body.get("notes") or "").strip(),
            "createdAt": (existing_payment or {}).get("createdAt") or current,
            "updatedAt": current,
        }
        if payment_type == "emi":
            payment_filter = (
                {"id": existing_payment["id"], "uid": user["uid"]}
                if existing_payment
                else {"uid": user["uid"], "loanId": loan_id, "emiKey": emi_key}
            )
            app.state.db.loan_payments.update_one(
                payment_filter,
                {
                    "$set": {
                        "paymentType": payment_type,
                        "period": period,
                        "emiKey": emi_key,
                        "amount": amount,
                        "currency": loan.get("currency") or "INR",
                        "date": payment_date,
                        "expenseId": expense["id"],
                        "notes": payment["notes"],
                        "updatedAt": current,
                    },
                    "$setOnInsert": {
                        "id": payment_id,
                        "uid": user["uid"],
                        "loanId": loan_id,
                        "createdAt": current,
                    },
                },
                upsert=True,
            )
            payment = app.state.db.loan_payments.find_one(
                {"id": payment_id, "uid": user["uid"]}
            ) or payment
        else:
            app.state.db.loan_payments.replace_one({"id": payment["id"], "uid": user["uid"]}, payment, upsert=True)
        recompute_loan_payment_summary(app.state.db, user["uid"], loan_id, current)
        updated_loan = app.state.db.loans.find_one({"id": loan_id, "uid": user["uid"]}) or loan
        return {
            "loan": loan_out(app.state.db, updated_loan),
            "payment": loan_payment_out(payment),
            "expense": expense_out(expense),
        }

    @app.put("/api/v1/loans/{loan_id}/payments/{payment_id}")
    def update_loan_payment(loan_id: str, payment_id: str, body: dict[str, Any], user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
        loan = app.state.db.loans.find_one({"id": loan_id, "uid": user["uid"]})
        if not loan:
            raise HTTPException(status_code=404, detail=api_error("NOT_FOUND", "loan not found"))
        payment = app.state.db.loan_payments.find_one({"id": payment_id, "uid": user["uid"], "loanId": loan_id})
        if not payment:
            raise HTTPException(status_code=404, detail=api_error("NOT_FOUND", "loan payment not found"))
        payment_date = parse_dt(str(body.get("date") or iso(payment.get("date") or now())))
        period = f"{payment_date.year:04d}-{payment_date.month:02d}"
        payment_type = str(payment.get("paymentType") or "emi")
        updates: dict[str, Any] = {
            "date": payment_date,
            "period": period,
            "updatedAt": now(),
        }
        if "notes" in body:
            updates["notes"] = str(body.get("notes") or "").strip()
        if payment_type == "emi":
            existing_for_period = app.state.db.loan_payments.find_one({
                "uid": user["uid"],
                "loanId": loan_id,
                "paymentType": "emi",
                "period": period,
                "id": {"$ne": payment_id},
            })
            if existing_for_period:
                raise HTTPException(status_code=409, detail=api_error("ALREADY_EXISTS", "another EMI is already logged for this month"))
            updates["emiKey"] = loan_emi_key(user["uid"], loan_id, period)
        app.state.db.loan_payments.update_one(
            {"id": payment_id, "uid": user["uid"], "loanId": loan_id},
            {"$set": updates},
        )
        expense = None
        if payment.get("expenseId"):
            expense_updates = {
                "date": payment_date,
                "sourcePeriod": period,
                "updatedAt": updates["updatedAt"],
            }
            app.state.db.expenses.update_one(
                {"id": payment["expenseId"], "uid": user["uid"]},
                {"$set": expense_updates},
            )
            expense = app.state.db.expenses.find_one({"id": payment["expenseId"], "uid": user["uid"]})
        recompute_loan_payment_summary(app.state.db, user["uid"], loan_id, updates["updatedAt"])
        updated_payment = app.state.db.loan_payments.find_one({"id": payment_id, "uid": user["uid"], "loanId": loan_id}) or {**payment, **updates}
        updated_loan = app.state.db.loans.find_one({"id": loan_id, "uid": user["uid"]}) or loan
        return {
            "loan": loan_out(app.state.db, updated_loan),
            "payment": loan_payment_out(updated_payment),
            "expense": expense_out(expense) if expense else {},
        }

    @app.get("/api/v1/savings/goals")
    def list_savings_goals(
        includeArchived: bool = False,
        user: dict[str, Any] = Depends(current_user),
    ) -> dict[str, Any]:
        filters: dict[str, Any] = {"uid": user["uid"]}
        if not includeArchived:
            filters["archivedAt"] = {"$exists": False}
        docs = list(app.state.db.savings_goals.find(filters).sort("updatedAt", DESCENDING))
        return {"goals": [savings_goal_out(app.state.db, doc) for doc in docs]}

    @app.post("/api/v1/savings/goals", status_code=201)
    def create_savings_goal(body: dict[str, Any], user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
        goal = build_savings_goal(body, user["uid"])
        app.state.db.savings_goals.insert_one(goal)
        return savings_goal_out(app.state.db, goal)

    @app.put("/api/v1/savings/goals/{goal_id}")
    def update_savings_goal(goal_id: str, body: dict[str, Any], user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
        existing = app.state.db.savings_goals.find_one({"id": goal_id, "uid": user["uid"]})
        if not existing:
            raise HTTPException(status_code=404, detail=api_error("NOT_FOUND", "savings goal not found"))
        updated = build_savings_goal(
            {**existing, **body},
            user["uid"],
            goal_id=goal_id,
            created_at=existing.get("createdAt"),
            archived_at=existing.get("archivedAt"),
        )
        app.state.db.savings_goals.replace_one({"id": goal_id, "uid": user["uid"]}, updated)
        return savings_goal_out(app.state.db, updated)

    @app.delete("/api/v1/savings/goals/{goal_id}", status_code=204)
    def archive_savings_goal(goal_id: str, user: dict[str, Any] = Depends(current_user)) -> Response:
        existing = app.state.db.savings_goals.find_one({"id": goal_id, "uid": user["uid"]})
        if not existing:
            raise HTTPException(status_code=404, detail=api_error("NOT_FOUND", "savings goal not found"))
        current = now()
        app.state.db.savings_goals.update_one(
            {"id": goal_id, "uid": user["uid"]},
            {"$set": {"archivedAt": current, "updatedAt": current}},
        )
        return Response(status_code=204)

    @app.get("/api/v1/savings/goals/{goal_id}/contributions")
    def list_savings_contributions(goal_id: str, user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
        goal = app.state.db.savings_goals.find_one({"id": goal_id, "uid": user["uid"]})
        if not goal:
            raise HTTPException(status_code=404, detail=api_error("NOT_FOUND", "savings goal not found"))
        docs = app.state.db.savings_contributions.find({"goalId": goal_id, "uid": user["uid"]}).sort("date", DESCENDING)
        return {"contributions": [savings_contribution_out(doc) for doc in docs]}

    @app.post("/api/v1/savings/goals/{goal_id}/contributions", status_code=201)
    async def create_savings_contribution(goal_id: str, body: dict[str, Any], user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
        goal = app.state.db.savings_goals.find_one({
            "id": goal_id,
            "uid": user["uid"],
            "archivedAt": {"$exists": False},
        })
        if not goal:
            raise HTTPException(status_code=404, detail=api_error("NOT_FOUND", "active savings goal not found"))
        contribution = await build_savings_contribution(app, body, goal, user["uid"])
        app.state.db.savings_contributions.insert_one(contribution)
        app.state.db.savings_goals.update_one(
            {"id": goal_id, "uid": user["uid"]},
            {"$set": {"lastContributionAt": contribution["date"], "updatedAt": now()}},
        )
        updated_goal = app.state.db.savings_goals.find_one({"id": goal_id, "uid": user["uid"]}) or goal
        return {
            "goal": savings_goal_out(app.state.db, updated_goal),
            "contribution": savings_contribution_out(contribution),
        }

    @app.put("/api/v1/savings/goals/{goal_id}/contributions/{contribution_id}")
    def update_savings_contribution(goal_id: str, contribution_id: str, body: dict[str, Any], user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
        goal = app.state.db.savings_goals.find_one({"id": goal_id, "uid": user["uid"]})
        if not goal:
            raise HTTPException(status_code=404, detail=api_error("NOT_FOUND", "savings goal not found"))
        contribution = app.state.db.savings_contributions.find_one({"id": contribution_id, "goalId": goal_id, "uid": user["uid"]})
        if not contribution:
            raise HTTPException(status_code=404, detail=api_error("NOT_FOUND", "savings contribution not found"))
        updates: dict[str, Any] = {
            "date": parse_dt(str(body.get("date") or iso(contribution.get("date") or now()))),
            "updatedAt": now(),
        }
        if "notes" in body:
            updates["notes"] = str(body.get("notes") or "").strip()
        app.state.db.savings_contributions.update_one(
            {"id": contribution_id, "goalId": goal_id, "uid": user["uid"]},
            {"$set": updates},
        )
        recompute_savings_goal_summary(app.state.db, user["uid"], goal_id, updates["updatedAt"])
        updated_goal = app.state.db.savings_goals.find_one({"id": goal_id, "uid": user["uid"]}) or goal
        updated_contribution = app.state.db.savings_contributions.find_one({"id": contribution_id, "goalId": goal_id, "uid": user["uid"]}) or {**contribution, **updates}
        return {
            "goal": savings_goal_out(app.state.db, updated_goal),
            "contribution": savings_contribution_out(updated_contribution),
        }

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
        income: float | None = None
        if any(key in body for key in ("income", "monthlyIncome", "plannedIncome", "totalIncome")):
            try:
                income = max(0.0, float(
                    body.get("income")
                    or body.get("monthlyIncome")
                    or body.get("plannedIncome")
                    or body.get("totalIncome")
                    or 0
                ))
            except (TypeError, ValueError):
                raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", "income must be a number")) from None
        doc = {
            "uid": owner_uid,
            "month": plan_month,
            "scope": "group" if group_id else "personal",
            "groupId": group_id,
            "currency": str(body.get("currency") or "INR").strip().upper() or "INR",
            "budgets": budgets,
            "updatedAt": now(),
        }
        if income is not None:
            doc["income"] = income
        app.state.db.monthly_plans.update_one(
            {"uid": owner_uid, "month": plan_month},
            {"$set": doc, "$setOnInsert": {"createdAt": now()}},
            upsert=True,
        )
        return monthly_plan_out(app.state.db, owner_uid, plan_month, group_id=group_id)

    @app.get("/api/v1/dashboard/snapshot")
    async def dashboard(user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
        ensure_setup_month_activity_entries(app.state.db, user["uid"])
        docs = [expense_out(doc) for doc in app.state.db.expenses.find({"uid": user["uid"]}).sort("date", -1).limit(20)]
        overall_summary = dashboard_overall_summary(app.state.db, user["uid"])
        action_items = dashboard_action_items(app.state.db, user["uid"])
        ai_summary = await generate_ai_dashboard_summary(
            app.state.ai_provider,
            build_ai_financial_context(
                app.state.db,
                user["uid"],
                purpose="home_summary",
                overall_summary=overall_summary,
                action_items=action_items,
                activity_items=docs,
            ),
        )
        return {
            **overall_summary,
            "friendItems": friend_balance_items(app.state.db, user["uid"]),
            "groupItems": group_balance_items(app.state.db, user["uid"]),
            "actionItems": action_items,
            "activityItems": [personal_dashboard_activity_item(doc) for doc in docs],
            "accountName": user.get("displayName") or "User",
            "accountEmail": user.get("email") or "",
            "aiInsights": ai_summary.get("cards", []),
            "aiSummary": ai_summary,
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

    @app.get("/api/v1/friends/settlements")
    def list_friend_settlements(friendUid: str = "", user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
        filters: dict[str, Any] = {"uids": user["uid"]}
        friend_uid = friendUid.strip()
        if friend_uid:
            filters["uids"] = {"$all": [user["uid"], friend_uid]}
        docs = app.state.db.friend_settlements.find(filters).sort("date", DESCENDING)
        return {"settlements": [friend_settlement_out(doc) for doc in docs]}

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
            "date": parse_dt(str(body.get("date") or iso(now()))),
            "createdAt": now(),
            "updatedAt": now(),
        }
        app.state.db.friend_settlements.insert_one(doc)
        return json_ready(friend_settlement_out(doc))

    @app.put("/api/v1/friends/settlements/{settlement_id}")
    def update_friend_settlement(settlement_id: str, body: dict[str, Any], user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
        settlement = app.state.db.friend_settlements.find_one({"id": settlement_id, "uids": user["uid"]})
        if not settlement:
            raise HTTPException(status_code=404, detail=api_error("NOT_FOUND", "settlement not found"))
        updates: dict[str, Any] = {
            "date": parse_dt(str(body.get("date") or iso(settlement.get("date") or settlement.get("createdAt") or now()))),
            "updatedAt": now(),
        }
        if "note" in body:
            updates["note"] = str(body.get("note") or "").strip()
        app.state.db.friend_settlements.update_one(
            {"id": settlement_id, "uids": user["uid"]},
            {"$set": updates},
        )
        updated = app.state.db.friend_settlements.find_one({"id": settlement_id, "uids": user["uid"]}) or {**settlement, **updates}
        return json_ready(friend_settlement_out(updated))

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
        if parts == ["savings", "goals"] and request.method == "GET":
            if group.get("groupType") != "family":
                return {"goals": []}
            member_uids = list(group.get("memberUids") or [])
            docs = list(
                app.state.db.savings_goals.find(
                    {
                        "uid": {"$in": member_uids},
                        "familyVisibility": "family",
                        "archivedAt": {"$exists": False},
                    }
                ).sort("updatedAt", DESCENDING)
            )
            users = {doc["uid"]: doc for doc in app.state.db.users.find({"uid": {"$in": member_uids}})}
            return {
                "goals": [
                    savings_goal_out(app.state.db, doc, owner=users.get(doc.get("uid")))
                    for doc in docs
                ]
            }
        if parts == ["expenses"] and request.method == "GET":
            return {"expenses": [group_expense_out(doc) for doc in app.state.db.group_expenses.find({"groupId": group_id}).sort("date", -1)]}
        if parts == ["expenses"] and request.method == "POST":
            body = await request.json()
            doc = await build_group_expense(app, body, group, app.state.db, user["uid"])
            app.state.db.group_expenses.insert_one(doc)
            if receipt_items_in_body(body):
                save_receipt_items_for_source(
                    app.state.db,
                    user=user,
                    source_type="group",
                    expense=doc,
                    raw_items=body_receipt_items(body),
                    group=group,
                    bill_job_id=str(body.get("billJobId") or ""),
                )
            touch_group(app.state.db, group_id)
            return JSONResponse(status_code=201, content=json_ready(group_expense_out(doc)))
        if parts == ["settlements"] and request.method == "GET":
            docs = app.state.db.group_settlements.find({"groupId": group_id}).sort("date", -1)
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
                "date": parse_dt(str(body.get("date") or iso(now()))),
                "createdAt": now(),
                "updatedAt": now(),
            }
            app.state.db.group_settlements.insert_one(doc)
            touch_group(app.state.db, group_id)
            return JSONResponse(status_code=201, content=json_ready(group_settlement_out(doc)))
        if len(parts) == 2 and parts[0] == "settlements" and request.method == "PUT":
            body = await request.json()
            existing = app.state.db.group_settlements.find_one({"groupId": group_id, "id": parts[1]})
            if not existing:
                raise HTTPException(status_code=404, detail=api_error("NOT_FOUND", "settlement not found"))
            updates = {
                "date": parse_dt(str(body.get("date") or iso(existing.get("date") or existing.get("createdAt") or now()))),
                "updatedAt": now(),
            }
            if "note" in body:
                updates["note"] = str(body.get("note") or "").strip()
            app.state.db.group_settlements.update_one(
                {"groupId": group_id, "id": parts[1]},
                {"$set": updates},
            )
            touch_group(app.state.db, group_id)
            updated = app.state.db.group_settlements.find_one({"groupId": group_id, "id": parts[1]}) or {**existing, **updates}
            return JSONResponse(status_code=200, content=json_ready(group_settlement_out(updated)))
        if len(parts) == 2 and parts[0] == "expenses" and request.method == "PUT":
            body = await request.json()
            existing = app.state.db.group_expenses.find_one({"groupId": group_id, "id": parts[1]})
            if not existing:
                raise HTTPException(status_code=404, detail=api_error("NOT_FOUND", "group or expense not found"))
            updated = await build_group_expense(app, body, group, app.state.db, user["uid"], expense_id=parts[1], created_by=existing["createdBy"], created_at=existing["createdAt"])
            app.state.db.group_expenses.replace_one({"groupId": group_id, "id": parts[1]}, updated)
            if receipt_items_in_body(body):
                save_receipt_items_for_source(
                    app.state.db,
                    user=user,
                    source_type="group",
                    expense=updated,
                    raw_items=body_receipt_items(body),
                    group=group,
                    bill_job_id=str(body.get("billJobId") or ""),
                )
            touch_group(app.state.db, group_id)
            return group_expense_out(updated)
        if len(parts) == 2 and parts[0] == "expenses" and request.method == "DELETE":
            existing = app.state.db.group_expenses.find_one({"groupId": group_id, "id": parts[1]})
            if existing:
                record_group_expense_tombstone(app.state.db, group, existing, user["uid"])
            app.state.db.group_expenses.delete_one({"groupId": group_id, "id": parts[1]})
            app.state.db.receipt_items.delete_many({"sourceType": "group", "groupId": group_id, "expenseId": parts[1]})
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
        if frequency not in recurring_frequency_values():
            raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", "frequency must be daily, weekly, monthly, quarterly or yearly"))
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
            "sourceAccountId": str(body.get("sourceAccountId") or "").strip(),
            "sourceAccountName": str(body.get("sourceAccountName") or body.get("accountName") or "").strip(),
            "startDate": start,
            "nextDueDate": recurring_next_due_date(
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
                "currency": result.get("currency") or "INR",
                "category": result.get("category") or "Personal",
                "description": result.get("merchant") or result.get("notes") or "Bill",
                "date": result.get("date") or iso(now()),
            },
            user["uid"],
        )
        app.state.db.expenses.insert_one(expense)
        save_receipt_items_for_source(
            app.state.db,
            user=user,
            source_type="personal",
            expense=expense,
            raw_items=result.get("lineItems") or [],
            bill_job_id=job_id,
        )
        app.state.db.ai_jobs.update_one({"id": job_id}, {"$set": {"expenseId": expense["id"], "updatedAt": now()}})
        return expense_out(expense)

    @app.post("/api/v1/ai/chat")
    async def ai_chat(body: dict[str, Any], user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
        question = str(body.get("question") or "").strip()
        if not question:
            raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", "question is required"))
        context = build_ai_financial_context(app.state.db, user["uid"], purpose="finance_chat")
        result = await generate_ai_finance_chat(app.state.ai_provider, context, question)
        app.state.db.ai_suggestions.insert_one({
            "id": uuid.uuid4().hex,
            "uid": user["uid"],
            "task": "finance_chat",
            "question": question,
            "result": result,
            "createdAt": now(),
        })
        return json_ready(result)

    @app.post("/api/v1/ai/summaries/{period}")
    async def generate_summary(period: str, user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
        if period not in {"daily", "monthly"}:
            raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", "period must be daily or monthly"))
        docs = list(app.state.db.expenses.find({"uid": user["uid"]}))
        total = sum(float(doc.get("amount") or 0) for doc in docs)
        ai_summary = await generate_ai_dashboard_summary(
            app.state.ai_provider,
            build_ai_financial_context(app.state.db, user["uid"], purpose="home_summary"),
        )
        primary_card = (ai_summary.get("cards") or [{}])[0]
        summary = {
            "id": uuid.uuid4().hex,
            "uid": user["uid"],
            "period": period,
            "task": "dashboard_summary",
            "schemaVersion": LocalGemmaBillExtractor.schema_version,
            "summary": primary_card.get("message") or f"{period.title()} total: INR {total:.2f} across {len(docs)} expenses.",
            "suggestions": [card.get("message") for card in ai_summary.get("cards", []) if card.get("message")] or (["Review uncategorized expenses."] if docs else ["Add your first expense to unlock summaries."]),
            "cards": ai_summary.get("cards", []),
            "warnings": ai_summary.get("warnings", []),
            "createdAt": now(),
        }
        app.state.db.ai_suggestions.insert_one(summary)
        return json_ready(summary)

    @app.get("/uploads/{path:path}")
    def serve_upload(path: str, user: dict[str, Any] = Depends(current_user)) -> FileResponse:
        active_upload_dir = app.state.upload_dir.resolve()
        full = (active_upload_dir / path).resolve()
        if active_upload_dir not in full.parents and full != active_upload_dir:
            raise HTTPException(status_code=403, detail=api_error("FORBIDDEN", "invalid upload path"))
        if not full.exists():
            raise HTTPException(status_code=404, detail=api_error("NOT_FOUND", "upload not found"))
        if not can_access_upload_path(app.state.db, path, user["uid"]):
            raise HTTPException(status_code=403, detail=api_error("FORBIDDEN", "upload not available to this user"))
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
    db.users.create_index("firebaseUid", unique=True, sparse=True)
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
    db.friend_settlements.create_index([("uids", ASCENDING), ("date", ASCENDING)])
    db.friend_settlements.create_index([("uids", ASCENDING), ("updatedAt", ASCENDING)])
    db.groups.create_index("memberUids")
    db.groups.create_index("pendingInvites.emailNormalized")
    db.group_expenses.create_index([("groupId", ASCENDING), ("date", ASCENDING)])
    db.group_expenses.create_index([("groupId", ASCENDING), ("updatedAt", ASCENDING)])
    db.group_settlements.create_index([("groupId", ASCENDING), ("createdAt", ASCENDING)])
    db.group_settlements.create_index([("groupId", ASCENDING), ("date", ASCENDING)])
    db.group_settlements.create_index([("groupId", ASCENDING), ("updatedAt", ASCENDING)])
    db.group_tombstones.create_index([("memberUids", ASCENDING), ("deletedAt", ASCENDING)])
    db.group_expense_tombstones.create_index([("memberUids", ASCENDING), ("deletedAt", ASCENDING)])
    db.ai_jobs.create_index([("uid", ASCENDING), ("createdAt", ASCENDING)])
    db.receipt_items.create_index([("uid", ASCENDING), ("date", DESCENDING)])
    db.receipt_items.create_index([("groupId", ASCENDING), ("date", DESCENDING)])
    db.receipt_items.create_index([("normalizedName", ASCENDING), ("currency", ASCENDING), ("unitPriceNormalized", ASCENDING)])
    db.receipt_items.create_index([("sourceType", ASCENDING), ("expenseId", ASCENDING)])
    db.financial_accounts.create_index([("uid", ASCENDING), ("updatedAt", DESCENDING)])
    db.credit_cards.create_index([("uid", ASCENDING), ("updatedAt", DESCENDING)])
    db.loans.create_index([("uid", ASCENDING), ("updatedAt", ASCENDING)])
    db.loan_payments.create_index([("uid", ASCENDING), ("loanId", ASCENDING), ("date", ASCENDING)])
    db.loan_payments.create_index([("uid", ASCENDING), ("loanId", ASCENDING), ("period", ASCENDING), ("paymentType", ASCENDING)])
    db.loan_payments.create_index([("uid", ASCENDING), ("loanId", ASCENDING), ("emiKey", ASCENDING)], unique=True, sparse=True)
    db.savings_goals.create_index([("uid", ASCENDING), ("updatedAt", ASCENDING)])
    db.savings_contributions.create_index([("uid", ASCENDING), ("goalId", ASCENDING), ("date", ASCENDING)])
    db.savings_contributions.create_index([("uid", ASCENDING), ("updatedAt", ASCENDING)])
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
        "onboardingCompleted": False,
        "passwordHash": password_hash,
        "authProviders": ["password"],
        "createdAt": current,
        "updatedAt": current,
    }


def create_session(db: Any, uid: str) -> str:
    token = secrets.token_urlsafe(32)
    db.sessions.insert_one({"uid": uid, "tokenHash": token_hash(token), "createdAt": now(), "expiresAt": now() + timedelta(days=30)})
    return token


def verify_firebase_claims(app: FastAPI, id_token: str) -> dict[str, Any]:
    token = id_token.strip()
    if not token:
        raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", "idToken is required"))

    verifier = getattr(app.state, "firebase_token_verifier", None)
    if verifier is not None:
        try:
            claims = verifier(token)
        except HTTPException:
            raise
        except ValueError as exc:
            raise HTTPException(status_code=401, detail=api_error("INVALID_FIREBASE_TOKEN", "Firebase token verification failed")) from exc
        except Exception as exc:
            raise HTTPException(status_code=503, detail=api_error("AUTH_UNAVAILABLE", "Firebase token verification is unavailable")) from exc
    else:
        project_id = os.getenv("FIREBASE_PROJECT_ID", "").strip()
        if not project_id:
            raise HTTPException(status_code=503, detail=api_error("AUTH_NOT_CONFIGURED", "Firebase project id is not configured"))
        try:
            from google.auth.transport import requests as google_requests
            from google.oauth2 import id_token as google_id_token
        except ImportError as exc:  # pragma: no cover - protected by dependency tests
            raise HTTPException(status_code=503, detail=api_error("AUTH_NOT_CONFIGURED", "Firebase token verifier is not installed")) from exc
        try:
            claims = google_id_token.verify_firebase_token(
                token,
                google_requests.Request(),
                audience=project_id,
            )
        except ValueError as exc:
            raise HTTPException(status_code=401, detail=api_error("INVALID_FIREBASE_TOKEN", "Firebase token verification failed")) from exc
        except Exception as exc:  # pragma: no cover - network/cert fetch failures
            raise HTTPException(status_code=503, detail=api_error("AUTH_UNAVAILABLE", "Firebase token verification is unavailable")) from exc

    if not isinstance(claims, dict):
        raise HTTPException(status_code=401, detail=api_error("INVALID_FIREBASE_TOKEN", "Firebase token verification failed"))
    email = normalize_email(str(claims.get("email") or ""))
    firebase_uid = str(claims.get("user_id") or claims.get("sub") or "").strip()
    if not firebase_uid:
        raise HTTPException(status_code=401, detail=api_error("INVALID_FIREBASE_TOKEN", "Firebase token is missing a user id"))
    if not email:
        raise HTTPException(status_code=401, detail=api_error("INVALID_FIREBASE_TOKEN", "Firebase token is missing an email"))
    if claims.get("email_verified") is False:
        raise HTTPException(status_code=403, detail=api_error("EMAIL_NOT_VERIFIED", "Google account email is not verified"))
    return claims


def find_or_create_firebase_user(db: Any, claims: dict[str, Any]) -> dict[str, Any]:
    firebase_uid = str(claims.get("user_id") or claims.get("sub") or "").strip()
    email = normalize_email(str(claims.get("email") or ""))
    display_name = str(claims.get("name") or claims.get("display_name") or email.split("@")[0] or "User").strip()
    photo_url = str(claims.get("picture") or "").strip() or None

    user = db.users.find_one({"firebaseUid": firebase_uid})
    if not user:
        user = db.users.find_one({"emailNormalized": email})

    current = now()
    if user:
        updates: dict[str, Any] = {
            "firebaseUid": firebase_uid,
            "updatedAt": current,
        }
        if user.get("emailNormalized") != email:
            existing_email_user = db.users.find_one({"emailNormalized": email})
            if not existing_email_user or existing_email_user.get("uid") == user["uid"]:
                updates["email"] = email
                updates["emailNormalized"] = email
        if display_name and str(user.get("displayName") or "").strip() in {"", "User", str(user.get("email") or "").split("@")[0]}:
            updates["displayName"] = display_name
        if photo_url and not user.get("photoUrl"):
            updates["photoUrl"] = photo_url
        db.users.update_one(
            {"uid": user["uid"]},
            {
                "$set": updates,
                "$addToSet": {"authProviders": "google"},
            },
        )
        return db.users.find_one({"uid": user["uid"]})

    user = create_user_doc(
        uuid.uuid4().hex,
        email,
        display_name,
        ph.hash(secrets.token_urlsafe(32)),
    )
    user["firebaseUid"] = firebase_uid
    user["authProviders"] = ["google"]
    user["photoUrl"] = photo_url
    db.users.insert_one(user)
    return user


FRESHNESS_SECTIONS = {
    "dashboard",
    "groups",
    "friends",
    "loans",
    "credit_cards",
    "savings",
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
        return ["dashboard", "groups", "friends", "loans", "credit_cards", "savings", "recurring", "activity"]
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


def latest_collection_time_any(
    db: Any,
    collection_name: str,
    filters: dict[str, Any],
    fields: list[str],
) -> datetime | None:
    return max_time(
        *[
            latest_collection_time(db, collection_name, filters, field)
            for field in fields
        ]
    )


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
        settlement_latest = latest_collection_time_any(
            db,
            "group_settlements",
            {"groupId": {"$in": group_ids}},
            ["updatedAt", "createdAt"],
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
        latest_collection_time_any(db, "friend_settlements", {"uids": uid}, ["updatedAt", "createdAt"]),
    )


def recurring_freshness(db: Any, uid: str) -> datetime | None:
    return max_time(
        latest_collection_time(db, "recurring_templates", {"uid": uid}, "updatedAt"),
        latest_collection_time(db, "recurring_occurrences", {"uid": uid}, "updatedAt"),
    )


def loan_freshness(db: Any, uid: str) -> datetime | None:
    return max_time(
        latest_collection_time(db, "loans", {"uid": uid}, "updatedAt"),
        latest_collection_time(db, "loan_payments", {"uid": uid}, "updatedAt"),
    )


def credit_card_freshness(db: Any, uid: str) -> datetime | None:
    return max_time(
        latest_collection_time(db, "credit_cards", {"uid": uid}, "updatedAt"),
        latest_collection_time(db, "expenses", {"uid": uid, "sourceType": "credit_card_spend"}, "updatedAt"),
    )


def savings_freshness(db: Any, uid: str) -> datetime | None:
    family_member_uids: set[str] = set()
    for group in db.groups.find({"memberUids": uid, "groupType": "family"}, {"memberUids": 1}):
        family_member_uids.update(str(item) for item in group.get("memberUids") or [])
    return max_time(
        latest_collection_time(db, "savings_goals", {"uid": uid}, "updatedAt"),
        latest_collection_time(db, "savings_contributions", {"uid": uid}, "updatedAt"),
        latest_collection_time(
            db,
            "savings_goals",
            {
                "uid": {"$in": list(family_member_uids)},
                "familyVisibility": "family",
            }
            if family_member_uids
            else {"uid": "__none__"},
            "updatedAt",
        ),
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
        latest_collection_time_any(db, "friend_settlements", {"uids": uid}, ["updatedAt", "createdAt"]),
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
        loan_freshness(db, uid),
        credit_card_freshness(db, uid),
        savings_freshness(db, uid),
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
    if section == "loans":
        return loan_freshness(db, uid)
    if section == "credit_cards":
        return credit_card_freshness(db, uid)
    if section == "savings":
        return savings_freshness(db, uid)
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


def settlement_activity_since_filter(since: datetime | None) -> dict[str, Any]:
    if since is None:
        return {}
    return {
        "$or": [
            {"updatedAt": {"$gt": since}},
            {"createdAt": {"$gt": since}},
        ]
    }


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
            **settlement_activity_since_filter(since),
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
                    "date": settlement.get("date") or settlement.get("createdAt"),
                    "updatedAt": settlement.get("updatedAt") or settlement.get("createdAt"),
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
                **settlement_activity_since_filter(since),
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
                        "date": settlement.get("date") or settlement.get("createdAt"),
                        "updatedAt": settlement.get("updatedAt") or settlement.get("createdAt"),
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


def is_loan_payment_expense(expense: dict[str, Any]) -> bool:
    return (
        expense.get("sourceType") == "loan_payment"
        or bool(expense.get("sourceLoanPaymentId"))
    )


def build_expense(body: dict[str, Any], uid: str, expense_id: str | None = None, created_at: datetime | None = None) -> dict[str, Any]:
    amount = positive_number(body.get("amount"), "amount")
    current = now()
    expense = {
        "id": expense_id or uuid.uuid4().hex,
        "uid": uid,
        "amount": amount,
        "currency": normalize_currency(body.get("currency"), "INR"),
        "category": str(body.get("category") or "Personal").strip() or "Personal",
        "description": str(body.get("description") or "").strip(),
        "paymentMethod": str(body.get("paymentMethod") or "cash").strip() or "cash",
        "date": parse_dt(str(body.get("date") or iso(current))),
        "createdAt": created_at or current,
        "updatedAt": current,
    }
    for key in [
        "sourceType",
        "sourceLoanId",
        "sourceLoanPaymentId",
        "sourceCreditCardId",
        "sourceAccountId",
        "sourceAccountName",
        "sourceDestinationAccountId",
        "sourceDestinationAccountName",
        "sourcePaymentType",
        "sourcePeriod",
        "sourceSetupKey",
    ]:
        value = str(body.get(key) or "").strip()
        if value:
            expense[key] = value
    return expense


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
            "sourceType",
            "sourceLoanId",
            "sourceLoanPaymentId",
            "sourceCreditCardId",
            "sourceAccountId",
            "sourceAccountName",
            "sourceDestinationAccountId",
            "sourceDestinationAccountName",
            "sourcePaymentType",
            "sourcePeriod",
            "sourceSetupKey",
            "createdAt",
            "updatedAt",
        ]
    })


def receipt_items_in_body(body: dict[str, Any]) -> bool:
    return "receiptItems" in body or "lineItems" in body


def body_receipt_items(body: dict[str, Any]) -> Any:
    return body.get("receiptItems") if "receiptItems" in body else body.get("lineItems")


def save_receipt_items_for_source(
    db: Any,
    *,
    user: dict[str, Any],
    source_type: str,
    expense: dict[str, Any],
    raw_items: Any,
    group: dict[str, Any] | None = None,
    bill_job_id: str = "",
) -> None:
    items = normalize_receipt_line_items(raw_items)
    expense_id = str(expense.get("id") or "").strip()
    group_id = str((group or {}).get("id") or expense.get("groupId") or "").strip()
    if not expense_id:
        return
    delete_filter = {
        "sourceType": source_type,
        "expenseId": expense_id,
        **({"groupId": group_id} if source_type == "group" else {"uid": user["uid"]}),
    }
    db.receipt_items.delete_many(delete_filter)
    if not items:
        return
    current = now()
    docs = []
    for index, item in enumerate(items):
        docs.append(
            {
                "id": uuid.uuid4().hex,
                "uid": user["uid"],
                "sourceType": source_type,
                "expenseId": expense_id,
                "groupId": group_id,
                "groupName": str((group or {}).get("name") or "").strip(),
                "billJobId": bill_job_id.strip(),
                "merchant": str(expense.get("description") or "").strip(),
                "date": expense.get("date") or current,
                "currency": normalize_currency(expense.get("currency"), "INR"),
                "rowIndex": index,
                **item,
                "createdAt": current,
                "updatedAt": current,
            }
        )
    db.receipt_items.insert_many(docs)


def visible_receipt_item_filter(db: Any, uid: str) -> dict[str, Any]:
    group_ids = [group["id"] for group in db.groups.find({"memberUids": uid})]
    return {
        "$or": [
            {"sourceType": "personal", "uid": uid},
            {"sourceType": "group", "groupId": {"$in": group_ids}},
        ]
    }


def receipt_item_query_filter(q: str, normalized_name: str, currency: str) -> dict[str, Any]:
    filters: list[dict[str, Any]] = []
    name = canonical_item_name(normalized_name or q)
    if normalized_name.strip() and name:
        filters.append({"normalizedName": name})
    elif q.strip():
        needle = normalized_text(q)
        text_filters = [
            {"itemName": {"$regex": re.escape(q.strip()), "$options": "i"}},
            {"originalText": {"$regex": re.escape(q.strip()), "$options": "i"}},
        ]
        if name:
            text_filters.insert(0, {"normalizedName": name})
        if needle:
            text_filters.append(
                {"normalizedName": {"$regex": re.escape(needle), "$options": "i"}}
            )
        filters.append({"$or": text_filters})
    if currency.strip():
        filters.append({"currency": normalize_currency(currency)})
    if not filters:
        return {}
    return filters[0] if len(filters) == 1 else {"$and": filters}


def receipt_item_out(doc: dict[str, Any]) -> dict[str, Any]:
    return json_ready(
        {
            key: doc.get(key)
            for key in [
                "id",
                "uid",
                "sourceType",
                "expenseId",
                "groupId",
                "groupName",
                "billJobId",
                "merchant",
                "date",
                "currency",
                "originalText",
                "detectedLanguage",
                "itemName",
                "normalizedName",
                "brand",
                "quantity",
                "unit",
                "normalizedQuantity",
                "normalizedUnit",
                "unitPrice",
                "lineTotal",
                "discount",
                "unitPriceNormalized",
                "category",
                "confidence",
                "createdAt",
                "updatedAt",
            ]
        }
    )


def receipt_item_comparison_out(query: str, docs: list[dict[str, Any]]) -> dict[str, Any]:
    items = [receipt_item_out(doc) for doc in sorted(docs, key=lambda item: float(item.get("unitPriceNormalized") or 10**12))]
    buckets: dict[tuple[str, str], list[dict[str, Any]]] = {}
    for doc in docs:
        key = (str(doc.get("currency") or "INR"), str(doc.get("normalizedUnit") or doc.get("unit") or "each"))
        buckets.setdefault(key, []).append(doc)
    summaries = []
    for (currency, unit), bucket in sorted(buckets.items()):
        prices = [float(item.get("unitPriceNormalized") or 0) for item in bucket if item.get("unitPriceNormalized") is not None]
        if not prices:
            continue
        best = min(bucket, key=lambda item: float(item.get("unitPriceNormalized") or 10**12))
        summaries.append(
            {
                "currency": currency,
                "unit": unit,
                "count": len(prices),
                "minUnitPrice": round(min(prices), 4),
                "maxUnitPrice": round(max(prices), 4),
                "averageUnitPrice": round(sum(prices) / len(prices), 4),
                "bestMerchant": best.get("merchant") or "",
                "bestItemName": best.get("itemName") or "",
                "bestUnitPrice": round(float(best.get("unitPriceNormalized") or 0), 4),
                "lastSeen": iso(max(aware(item.get("date") or now()) for item in bucket)),
            }
        )
    normalized_query = canonical_item_name(query)
    return {
        "query": query,
        "normalizedName": normalized_query,
        "summaryByCurrency": summaries,
        "items": items,
    }


def normalize_financial_account_type(value: Any) -> str:
    raw = str(value or "savings").strip().lower().replace("-", "_").replace(" ", "_")
    aliases = {
        "bank": "checking",
        "current": "checking",
        "salary": "checking",
        "saving": "savings",
        "sparekonto": "savings",
        "nre": "savings",
        "nro": "savings",
        "fd": "fixed_deposit",
        "fixed": "fixed_deposit",
        "deposit": "fixed_deposit",
        "sip": "investment",
        "mutual_fund": "investment",
    }
    normalized = aliases.get(raw, raw)
    if normalized not in {"checking", "savings", "cash", "investment", "fixed_deposit", "credit", "other"}:
        return "savings"
    return normalized


def build_financial_account(
    body: dict[str, Any],
    uid: str,
    account_id: str | None = None,
    created_at: datetime | None = None,
    archived_at: datetime | None = None,
) -> dict[str, Any]:
    name = str(body.get("name") or "").strip()
    if not name:
        raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", "name is required"))
    current = now()
    raw_balance_as_of = body.get("balanceAsOf")
    return {
        "id": account_id or uuid.uuid4().hex,
        "uid": uid,
        "name": name,
        "institution": str(body.get("institution") or "").strip(),
        "accountType": normalize_financial_account_type(body.get("accountType") or body.get("type")),
        "currency": normalize_currency(body.get("currency"), "NOK"),
        "openingBalance": finite_number(body_first(body, ("openingBalance", "balance"), 0), "openingBalance"),
        "balanceAsOf": parse_dt(str(raw_balance_as_of)) if raw_balance_as_of else current,
        "familyVisibility": normalize_family_visibility(body.get("familyVisibility") or body.get("visibility")),
        "notes": str(body.get("notes") or "").strip(),
        "createdAt": created_at or current,
        "updatedAt": current,
        **({"archivedAt": archived_at} if archived_at else {}),
    }


def financial_account_out(doc: dict[str, Any]) -> dict[str, Any]:
    return json_ready({
        "id": doc.get("id") or "",
        "name": doc.get("name") or "",
        "institution": doc.get("institution") or "",
        "accountType": normalize_financial_account_type(doc.get("accountType")),
        "currency": normalize_currency(doc.get("currency"), "NOK"),
        "openingBalance": float(doc.get("openingBalance") or 0),
        "balanceAsOf": doc.get("balanceAsOf"),
        "familyVisibility": normalize_family_visibility(doc.get("familyVisibility")),
        "notes": doc.get("notes") or "",
        "archived": bool(doc.get("archivedAt")),
        "archivedAt": doc.get("archivedAt"),
        "createdAt": doc.get("createdAt"),
        "updatedAt": doc.get("updatedAt"),
    })


def build_credit_card(
    body: dict[str, Any],
    uid: str,
    card_id: str | None = None,
    created_at: datetime | None = None,
    archived_at: datetime | None = None,
) -> dict[str, Any]:
    name = str(body.get("name") or "").strip()
    if not name:
        raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", "name is required"))
    current = now()
    raw_balance_as_of = body.get("balanceAsOf")
    statement_day = bounded_int(body_first(body, ("statementDay", "statementCloseDay"), 1), "statementDay", 1, 31)
    due_day = bounded_int(body_first(body, ("dueDay", "paymentDueDay"), statement_day), "dueDay", 1, 31)
    doc = {
        "id": card_id or uuid.uuid4().hex,
        "uid": uid,
        "name": name,
        "issuer": str(body.get("issuer") or "").strip(),
        "network": str(body.get("network") or "").strip(),
        "last4": str(body.get("last4") or "").strip()[-4:],
        "currency": normalize_currency(body.get("currency"), "NOK"),
        "creditLimit": non_negative_number(body_first(body, ("creditLimit", "limit"), 0), "creditLimit"),
        "currentBalance": non_negative_number(body_first(body, ("currentBalance", "balance"), 0), "currentBalance"),
        "balanceAsOf": parse_dt(str(raw_balance_as_of)) if raw_balance_as_of else current,
        "statementDay": statement_day,
        "dueDay": due_day,
        "familyVisibility": normalize_family_visibility(body.get("familyVisibility") or body.get("visibility")),
        "notes": str(body.get("notes") or "").strip(),
        "createdAt": created_at or current,
        "updatedAt": current,
    }
    if archived_at:
        doc["archivedAt"] = archived_at
    return doc


def month_day_date(year: int, month_number: int, day: int) -> datetime:
    clamped = min(max(day, 1), calendar.monthrange(year, month_number)[1])
    return datetime(year, month_number, clamped, tzinfo=UTC)


def shift_year_month(year: int, month_number: int, delta: int) -> tuple[int, int]:
    zero_based = year * 12 + (month_number - 1) + delta
    shifted_year, shifted_month_zero = divmod(zero_based, 12)
    return shifted_year, shifted_month_zero + 1


def credit_card_cycle_bounds(
    statement_day: int,
    as_of: datetime | None = None,
) -> tuple[datetime, datetime, datetime]:
    current = aware(as_of or now())
    current_statement = month_day_date(current.year, current.month, statement_day)
    if current < current_statement + timedelta(days=1):
        previous_year, previous_month = shift_year_month(current.year, current.month, -1)
        previous_statement = month_day_date(previous_year, previous_month, statement_day)
        cycle_start = previous_statement + timedelta(days=1)
        statement_date = current_statement
    else:
        next_year, next_month = shift_year_month(current.year, current.month, 1)
        cycle_start = current_statement + timedelta(days=1)
        statement_date = month_day_date(next_year, next_month, statement_day)
    cycle_start = datetime(cycle_start.year, cycle_start.month, cycle_start.day, tzinfo=UTC)
    statement_date = datetime(statement_date.year, statement_date.month, statement_date.day, tzinfo=UTC)
    return cycle_start, statement_date, statement_date + timedelta(days=1)


def credit_card_due_date(statement_date: datetime, due_day: int) -> datetime:
    due = month_day_date(statement_date.year, statement_date.month, due_day)
    if due <= statement_date:
        next_year, next_month = shift_year_month(statement_date.year, statement_date.month, 1)
        due = month_day_date(next_year, next_month, due_day)
    return due


def credit_card_cycle_spend(db: Any, uid: str, card_id: str, start: datetime, end_exclusive: datetime) -> float:
    docs = db.expenses.find(
        {
            "uid": uid,
            "sourceCreditCardId": card_id,
            "date": {"$gte": start, "$lt": end_exclusive},
        }
    )
    return round(sum(float(doc.get("amount") or 0) for doc in docs), 2)


def credit_card_out(db: Any, doc: dict[str, Any]) -> dict[str, Any]:
    statement_day = int(doc.get("statementDay") or 1)
    due_day = int(doc.get("dueDay") or statement_day)
    cycle_start, statement_date, cycle_end_exclusive = credit_card_cycle_bounds(statement_day)
    current_balance = float(doc.get("currentBalance") or 0)
    credit_limit = float(doc.get("creditLimit") or 0)
    return json_ready({
        "id": doc.get("id") or "",
        "name": doc.get("name") or "",
        "issuer": doc.get("issuer") or "",
        "network": doc.get("network") or "",
        "last4": doc.get("last4") or "",
        "currency": normalize_currency(doc.get("currency"), "NOK"),
        "creditLimit": credit_limit,
        "currentBalance": current_balance,
        "availableCredit": round(credit_limit - current_balance, 2),
        "balanceAsOf": doc.get("balanceAsOf"),
        "statementDay": statement_day,
        "dueDay": due_day,
        "cycleStart": cycle_start,
        "statementDate": statement_date,
        "cycleEnd": statement_date,
        "paymentDueDate": credit_card_due_date(statement_date, due_day),
        "currentCycleSpend": credit_card_cycle_spend(
            db,
            str(doc.get("uid") or ""),
            str(doc.get("id") or ""),
            cycle_start,
            cycle_end_exclusive,
        ),
        "familyVisibility": normalize_family_visibility(doc.get("familyVisibility")),
        "notes": doc.get("notes") or "",
        "archived": bool(doc.get("archivedAt")),
        "archivedAt": doc.get("archivedAt"),
        "createdAt": doc.get("createdAt"),
        "updatedAt": doc.get("updatedAt"),
    })


def reconcile_credit_card_expense_update(
    db: Any,
    uid: str,
    existing: dict[str, Any],
    updated: dict[str, Any],
) -> None:
    card_id = str(existing.get("sourceCreditCardId") or updated.get("sourceCreditCardId") or "").strip()
    if not card_id:
        return
    card = db.credit_cards.find_one({"id": card_id, "uid": uid})
    if not card:
        return
    card_currency = normalize_currency(card.get("currency"), "NOK")
    updated_currency = normalize_currency(updated.get("currency"), card_currency)
    if updated_currency != card_currency:
        raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", "card expenses must stay in the card currency"))
    updated["sourceType"] = "credit_card_spend"
    updated["sourceCreditCardId"] = card_id
    old_amount = float(existing.get("amount") or 0)
    new_amount = float(updated.get("amount") or 0)
    delta = round(new_amount - old_amount, 2)
    if abs(delta) > 0.005:
        db.credit_cards.update_one(
            {"id": card_id, "uid": uid},
            {
                "$inc": {"currentBalance": delta},
                "$set": {"balanceAsOf": updated.get("date") or now(), "updatedAt": now()},
            },
        )


def reconcile_credit_card_expense_delete(db: Any, uid: str, expense: dict[str, Any]) -> None:
    card_id = str(expense.get("sourceCreditCardId") or "").strip()
    if not card_id:
        return
    amount = float(expense.get("amount") or 0)
    db.credit_cards.update_one(
        {"id": card_id, "uid": uid},
        {
            "$inc": {"currentBalance": -amount},
            "$set": {"balanceAsOf": expense.get("date") or now(), "updatedAt": now()},
        },
    )


def build_loan(
    body: dict[str, Any],
    uid: str,
    loan_id: str | None = None,
    created_at: datetime | None = None,
    archived_at: datetime | None = None,
) -> dict[str, Any]:
    name = str(body.get("name") or "").strip()
    if not name:
        raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", "name is required"))
    principal = positive_number(
        body_first(body, ("currentPrincipalAmount", "openingPrincipalAmount", "principalAmount", "principal"), 0),
        "principalAmount",
    )
    original_principal = non_negative_number(body_first(body, ("originalPrincipalAmount",), 0), "originalPrincipalAmount")
    emi_amount = positive_number(body_first(body, ("emiAmount",), 0), "emiAmount")
    total_emis = non_negative_int(body_first(body, ("remainingEmis", "totalEmis"), 0), "totalEmis")
    due_day = bounded_int(body_first(body, ("dueDay", "dayOfMonth"), 1), "dueDay", 1, 31)
    current = now()
    tracking_started_at = parse_dt(str(body.get("trackingStartedAt") or body.get("startDate") or iso(current)))
    rate_type = str(body.get("rateType") or "fixed").strip().lower()
    if rate_type not in {"fixed", "floating", "unknown"}:
        rate_type = "fixed"
    doc = {
        "id": loan_id or uuid.uuid4().hex,
        "uid": uid,
        "name": name,
        "lender": str(body.get("lender") or "").strip(),
        "loanType": str(body.get("loanType") or "Personal").strip() or "Personal",
        "principalAmount": principal,
        "openingPrincipalAmount": principal,
        "originalPrincipalAmount": original_principal,
        "emiAmount": emi_amount,
        "currency": normalize_currency(body.get("currency"), "INR"),
        "interestRate": non_negative_number(body_first(body, ("interestRate",), 0), "interestRate"),
        "rateType": rate_type,
        "totalEmis": total_emis,
        "dueDay": due_day,
        "startDate": tracking_started_at,
        "trackingStartedAt": tracking_started_at,
        "category": str(body.get("category") or "Loans / EMI").strip() or "Loans / EMI",
        "notes": str(body.get("notes") or "").strip(),
        "createdAt": created_at or current,
        "updatedAt": current,
    }
    if archived_at:
        doc["archivedAt"] = archived_at
    return doc


def loan_month_for_date(value: datetime) -> str:
    value = aware(value)
    return f"{value.year:04d}-{value.month:02d}"


def stable_loan_hex(*parts: str) -> str:
    return hashlib.sha256("|".join(parts).encode("utf-8")).hexdigest()


def loan_emi_key(uid: str, loan_id: str, period: str) -> str:
    return stable_loan_hex(uid, loan_id, period, "emi")


def recompute_loan_payment_summary(db: Any, uid: str, loan_id: str, updated_at: datetime | None = None) -> None:
    latest = db.loan_payments.find_one(
        {"uid": uid, "loanId": loan_id},
        sort=[("date", DESCENDING)],
    )
    db.loans.update_one(
        {"id": loan_id, "uid": uid},
        {
            "$set": {
                "lastPaymentAt": latest.get("date") if latest else None,
                "updatedAt": updated_at or now(),
            }
        },
    )


def loan_due_date_for_month(month: str, due_day: int) -> datetime:
    year, month_number = [int(part) for part in normalize_month(month).split("-")]
    day = min(max(due_day, 1), calendar.monthrange(year, month_number)[1])
    return datetime(year, month_number, day, tzinfo=UTC)


def loan_next_due_date(db: Any, loan: dict[str, Any]) -> datetime | None:
    payments = list(db.loan_payments.find({
        "uid": loan.get("uid"),
        "loanId": loan.get("id"),
        "paymentType": "emi",
    }))
    paid_emi_count = len(payments)
    total_emis = int(loan.get("totalEmis") or 0)
    if total_emis > 0 and paid_emi_count >= total_emis:
        return None
    due_day = int(loan.get("dueDay") or 1)
    start = aware(loan.get("startDate") or now())
    candidate_month = loan_month_for_date(start)
    candidate = loan_due_date_for_month(candidate_month, due_day)
    if candidate < start:
        candidate_month = add_months(candidate_month, 1)
        candidate = loan_due_date_for_month(candidate_month, due_day)
    paid_periods = {str(payment.get("period") or "") for payment in payments}
    checked_periods = 0
    while candidate_month in paid_periods:
        checked_periods += 1
        if total_emis > 0 and checked_periods >= total_emis:
            return None
        candidate_month = add_months(candidate_month, 1)
        candidate = loan_due_date_for_month(candidate_month, due_day)
    return candidate


def loan_out(db: Any, doc: dict[str, Any]) -> dict[str, Any]:
    payments = list(db.loan_payments.find({"uid": doc.get("uid"), "loanId": doc.get("id")}))
    emi_payments = [payment for payment in payments if payment.get("paymentType") == "emi"]
    prepayments = [payment for payment in payments if payment.get("paymentType") == "prepayment"]
    total_paid = round(sum(float(payment.get("amount") or 0) for payment in payments), 2)
    prepayment_total = round(sum(float(payment.get("amount") or 0) for payment in prepayments), 2)
    total_emis = int(doc.get("totalEmis") or 0)
    paid_emi_count = len(emi_payments)
    remaining_emis = max(total_emis - paid_emi_count, 0) if total_emis > 0 else None
    principal = float(doc.get("principalAmount") or 0)
    next_due_date = loan_next_due_date(db, doc)
    return json_ready({
        "id": doc.get("id"),
        "name": doc.get("name") or "",
        "lender": doc.get("lender") or "",
        "loanType": doc.get("loanType") or "Personal",
        "principalAmount": principal,
        "openingPrincipalAmount": float(doc.get("openingPrincipalAmount") or principal),
        "originalPrincipalAmount": float(doc.get("originalPrincipalAmount") or 0),
        "emiAmount": float(doc.get("emiAmount") or 0),
        "currency": doc.get("currency") or "INR",
        "interestRate": float(doc.get("interestRate") or 0),
        "rateType": doc.get("rateType") or "fixed",
        "totalEmis": total_emis,
        "paidEmiCount": paid_emi_count,
        "remainingEmis": remaining_emis,
        "totalPaidAmount": total_paid,
        "prepaymentAmount": prepayment_total,
        "estimatedOutstanding": round(max(principal - total_paid, 0), 2),
        "dueDay": int(doc.get("dueDay") or 1),
        "startDate": doc.get("startDate"),
        "trackingStartedAt": doc.get("trackingStartedAt") or doc.get("startDate"),
        "nextDueDate": next_due_date,
        "lastPaymentAt": doc.get("lastPaymentAt"),
        "category": doc.get("category") or "Loans / EMI",
        "notes": doc.get("notes") or "",
        "archived": bool(doc.get("archivedAt")),
        "archivedAt": doc.get("archivedAt"),
        "createdAt": doc.get("createdAt"),
        "updatedAt": doc.get("updatedAt"),
    })


def loan_payment_out(doc: dict[str, Any]) -> dict[str, Any]:
    return json_ready({
        "id": doc.get("id"),
        "loanId": doc.get("loanId"),
        "paymentType": doc.get("paymentType") or "emi",
        "period": doc.get("period") or "",
        "amount": float(doc.get("amount") or 0),
        "currency": doc.get("currency") or "INR",
        "date": doc.get("date"),
        "expenseId": doc.get("expenseId"),
        "notes": doc.get("notes") or "",
        "createdAt": doc.get("createdAt"),
        "updatedAt": doc.get("updatedAt"),
    })


def build_savings_goal(
    body: dict[str, Any],
    uid: str,
    goal_id: str | None = None,
    created_at: datetime | None = None,
    archived_at: datetime | None = None,
) -> dict[str, Any]:
    name = str(body.get("name") or "").strip()
    if not name:
        raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", "name is required"))
    target_amount = positive_number(body_first(body, ("targetAmount",), 0), "targetAmount")
    monthly_target = non_negative_number(body_first(body, ("monthlyTargetAmount",), 0), "monthlyTargetAmount")
    current = now()
    start_month = normalize_month(str(body.get("startMonth") or current_month()))
    raw_target_date = body.get("targetDate")
    raw_maturity_date = body.get("maturityDate")
    doc = {
        "id": goal_id or uuid.uuid4().hex,
        "uid": uid,
        "name": name,
        "goalType": normalize_savings_goal_type(body.get("goalType") or body.get("type")),
        "familyVisibility": normalize_family_visibility(body.get("familyVisibility") or body.get("visibility")),
        "targetAmount": target_amount,
        "targetCurrency": normalize_currency(body.get("targetCurrency"), "INR"),
        "sourceCurrency": normalize_currency(body.get("sourceCurrency"), "NOK"),
        "monthlyTargetAmount": monthly_target,
        "startMonth": start_month,
        "targetDate": parse_dt(str(raw_target_date)) if raw_target_date else None,
        "maturityDate": parse_dt(str(raw_maturity_date)) if raw_maturity_date else None,
        "provider": str(body.get("provider") or "").strip(),
        "accountName": str(body.get("accountName") or "").strip(),
        "expectedReturnRate": non_negative_number(body_first(body, ("expectedReturnRate",), 0), "expectedReturnRate"),
        "notes": str(body.get("notes") or "").strip(),
        "createdAt": created_at or current,
        "updatedAt": current,
    }
    if archived_at:
        doc["archivedAt"] = archived_at
    return doc


def normalize_savings_goal_type(value: Any) -> str:
    raw = str(value or "savings_goal").strip().lower().replace("-", "_").replace(" ", "_")
    aliases = {
        "goal": "savings_goal",
        "savings": "savings_goal",
        "saving": "savings_goal",
        "mutual_fund_sip": "sip",
        "systematic_investment_plan": "sip",
        "fd": "fixed_deposit",
        "fixed": "fixed_deposit",
        "fixed_investment": "fixed_deposit",
        "deposit": "fixed_deposit",
        "emergency": "emergency_fund",
    }
    normalized = aliases.get(raw, raw)
    if normalized not in {"savings_goal", "sip", "fixed_deposit", "emergency_fund", "other"}:
        return "savings_goal"
    return normalized


def normalize_family_visibility(value: Any) -> str:
    raw = str(value or "private").strip().lower().replace("-", "_").replace(" ", "_")
    if raw in {"family", "household", "shared", "visible", "show"}:
        return "family"
    return "private"


async def build_savings_contribution(
    app: FastAPI,
    body: dict[str, Any],
    goal: dict[str, Any],
    uid: str,
) -> dict[str, Any]:
    source_currency = normalize_currency(body.get("sourceCurrency"), goal.get("sourceCurrency") or "NOK")
    target_currency = normalize_currency(goal.get("targetCurrency"), "INR")
    source_amount = positive_number(body.get("sourceAmount"), "sourceAmount")
    fee_amount = non_negative_number(body_first(body, ("feeAmount",), 0), "feeAmount")
    fee_currency = normalize_currency(body.get("feeCurrency"), source_currency)
    contribution_date = parse_dt(str(body.get("date") or iso(now())))
    snapshot = await conversion_snapshot(app, source_amount, source_currency, [target_currency])
    market_target_amount = float(snapshot["convertedAmounts"].get(target_currency) or source_amount)
    if "targetAmount" in body:
        target_amount = positive_number(body.get("targetAmount"), "targetAmount")
    else:
        target_amount = market_target_amount
    effective_rate = round(target_amount / source_amount, 8)
    market_rate = float(snapshot["exchangeRates"].get(target_currency) or effective_rate)
    current = now()
    return {
        "id": uuid.uuid4().hex,
        "uid": uid,
        "goalId": goal["id"],
        "sourceAmount": source_amount,
        "sourceCurrency": source_currency,
        "targetAmount": round(target_amount, 4),
        "targetCurrency": target_currency,
        "feeAmount": fee_amount,
        "feeCurrency": fee_currency,
        "exchangeRate": effective_rate,
        "marketRate": market_rate,
        "marketTargetAmount": round(market_target_amount, 4),
        **snapshot,
        "date": contribution_date,
        "notes": str(body.get("notes") or "").strip(),
        "createdAt": current,
        "updatedAt": current,
    }


def savings_goal_out(db: Any, doc: dict[str, Any], owner: dict[str, Any] | None = None) -> dict[str, Any]:
    contributions = list(db.savings_contributions.find({"uid": doc.get("uid"), "goalId": doc.get("id")}))
    target_currency = normalize_currency(doc.get("targetCurrency"), "INR")
    source_currency = normalize_currency(doc.get("sourceCurrency"), "NOK")
    target_amount = float(doc.get("targetAmount") or 0)
    total_saved = round(sum(float(item.get("targetAmount") or 0) for item in contributions), 2)
    total_source = round(sum(float(item.get("sourceAmount") or 0) for item in contributions), 2)
    current_start, current_end = month_range(current_month())
    current_month_saved = round(
        sum(
            float(item.get("targetAmount") or 0)
            for item in contributions
            if current_start <= aware(item.get("date") or now()) < current_end
        ),
        2,
    )
    latest = None
    for item in contributions:
        value = item.get("date")
        if isinstance(value, datetime) and (latest is None or aware(value) > latest):
            latest = aware(value)
    return json_ready({
        "id": doc.get("id"),
        "ownerUid": doc.get("uid") or "",
        "ownerLabel": (user_public(owner)["displayName"] if owner else ""),
        "name": doc.get("name") or "",
        "goalType": normalize_savings_goal_type(doc.get("goalType")),
        "familyVisibility": normalize_family_visibility(doc.get("familyVisibility")),
        "targetAmount": target_amount,
        "targetCurrency": target_currency,
        "sourceCurrency": source_currency,
        "monthlyTargetAmount": float(doc.get("monthlyTargetAmount") or 0),
        "startMonth": doc.get("startMonth") or current_month(),
        "targetDate": doc.get("targetDate"),
        "maturityDate": doc.get("maturityDate"),
        "provider": doc.get("provider") or "",
        "accountName": doc.get("accountName") or "",
        "expectedReturnRate": float(doc.get("expectedReturnRate") or 0),
        "totalSavedAmount": total_saved,
        "totalSourceAmount": total_source,
        "remainingAmount": round(max(target_amount - total_saved, 0), 2),
        "progress": 0 if target_amount <= 0 else min(total_saved / target_amount, 1.5),
        "currentMonthSavedAmount": current_month_saved,
        "contributionCount": len(contributions),
        "lastContributionAt": doc.get("lastContributionAt") or latest,
        "notes": doc.get("notes") or "",
        "archived": bool(doc.get("archivedAt")),
        "archivedAt": doc.get("archivedAt"),
        "createdAt": doc.get("createdAt"),
        "updatedAt": doc.get("updatedAt"),
    })


def recompute_savings_goal_summary(db: Any, uid: str, goal_id: str, updated_at: datetime | None = None) -> None:
    latest = db.savings_contributions.find_one(
        {"uid": uid, "goalId": goal_id},
        sort=[("date", DESCENDING)],
    )
    db.savings_goals.update_one(
        {"id": goal_id, "uid": uid},
        {
            "$set": {
                "lastContributionAt": latest.get("date") if latest else None,
                "updatedAt": updated_at or now(),
            }
        },
    )


def savings_contribution_out(doc: dict[str, Any]) -> dict[str, Any]:
    return json_ready({
        key: doc.get(key)
        for key in [
            "id",
            "goalId",
            "sourceAmount",
            "sourceCurrency",
            "targetAmount",
            "targetCurrency",
            "feeAmount",
            "feeCurrency",
            "exchangeRate",
            "marketRate",
            "marketTargetAmount",
            "exchangeRateProvider",
            "exchangeRateFetchedAt",
            "exchangeRateAsOf",
            "date",
            "notes",
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
    if "sourceAccountId" in body:
        updates["sourceAccountId"] = str(body.get("sourceAccountId") or "").strip()
    if "sourceAccountName" in body or "accountName" in body:
        updates["sourceAccountName"] = str(body.get("sourceAccountName") or body.get("accountName") or "").strip()
    if "frequency" in body:
        frequency = str(body.get("frequency") or "monthly").strip().lower()
        if frequency not in recurring_frequency_values():
            raise HTTPException(status_code=400, detail=api_error("INVALID_ARGUMENT", "frequency must be daily, weekly, monthly, quarterly or yearly"))
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
        updates["nextDueDate"] = recurring_next_due_date(
            merged,
            max(current_month(), f"{start.year:04d}-{start.month:02d}"),
        )
    updates["updatedAt"] = now()
    return updates


def recurring_frequency_values() -> set[str]:
    return {"daily", "weekly", "monthly", "quarterly", "yearly"}


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

    if frequency in {"quarterly", "yearly"}:
        year, month_number = [int(part) for part in month.split("-")]
        month_delta = (
            (year * 12 + (month_number - 1))
            - (template_start.year * 12 + (template_start.month - 1))
        )
        interval_months = 3 if frequency == "quarterly" else 12
        if month_delta < 0 or month_delta % interval_months != 0:
            return []
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


def recurring_next_due_date(template: dict[str, Any], from_month: str) -> datetime:
    period = normalize_month(from_month)
    for offset in range(0, 25):
        candidate_month = add_months(period, offset)
        dates = recurring_due_dates_for_month(template, candidate_month)
        if dates:
            return dates[0]
    start = aware(template.get("startDate") or now())
    return next_due(start, str(template.get("frequency") or "monthly").lower())


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


def original_expense_amount_by_currency(expense: dict[str, Any]) -> tuple[str, float] | None:
    currency = safe_currency(expense.get("currency"), "INR") or "INR"
    try:
        amount = float(expense.get("amount") or 0)
    except (TypeError, ValueError):
        return None
    return currency, amount


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
    is_income = str(doc.get("sourcePaymentType") or "").strip().lower() == "income"
    return {
        "title": doc.get("description") or doc.get("category") or "Expense",
        "subtitle": doc.get("date"),
        "amountText": (
            f"You received {format_currency_amount(currency, amount)}"
            if is_income
            else f"You spent {format_currency_amount(currency, amount)}"
        ),
        "positive": is_income,
    }


AI_CONTEXT_SCHEMA_VERSION = "finance-context-v1"
AI_CONTEXT_PURPOSE_LIMITS: dict[str, dict[str, int]] = {
    "home_summary": {
        "maxCategories": 6,
        "maxRecentExpenses": 0,
        "maxActionItems": 4,
        "maxMerchants": 4,
        "maxBytes": 6000,
    },
    "finance_chat": {
        "maxCategories": 8,
        "maxRecentExpenses": 8,
        "maxActionItems": 5,
        "maxMerchants": 5,
        "maxBytes": 10000,
    },
    "receipt_autofill": {
        "maxCategories": 8,
        "maxRecentExpenses": 3,
        "maxActionItems": 3,
        "maxMerchants": 5,
        "maxBytes": 8000,
    },
}


def ai_context_limits(purpose: str) -> dict[str, int]:
    return AI_CONTEXT_PURPOSE_LIMITS.get(purpose, AI_CONTEXT_PURPOSE_LIMITS["finance_chat"])


def ai_context_text(value: Any, max_length: int = 80) -> str:
    text = re.sub(r"\s+", " ", str(value or "")).strip()
    return text[:max_length]


def ai_context_money(value: Any) -> float:
    try:
        return round(float(value or 0), 2)
    except (TypeError, ValueError):
        return 0.0


def ai_context_month_actual(db: Any, uid: str, month: str, currency: str) -> float:
    start, end = month_range(month)
    total = 0.0

    def add_expense(expense: dict[str, Any]) -> None:
        nonlocal total
        amount = expense_amount_for_currency(expense, currency)
        if amount is not None:
            total += float(amount or 0)

    for expense in db.expenses.find({"uid": uid, "date": {"$gte": start, "$lt": end}}):
        add_expense(expense)
    family_groups = list(db.groups.find({"memberUids": uid, "groupType": "family"}, {"id": 1}))
    family_group_ids = [group.get("id") for group in family_groups if group.get("id")]
    if family_group_ids:
        for expense in db.group_expenses.find({"groupId": {"$in": family_group_ids}, "date": {"$gte": start, "$lt": end}}):
            add_expense(expense)
    return round(total, 2)


def ai_context_recent_expenses(db: Any, uid: str, month: str, currency: str, limit: int) -> tuple[list[dict[str, Any]], bool]:
    if limit <= 0:
        return [], db.expenses.count_documents({"uid": uid, "date": {"$gte": month_range(month)[0], "$lt": month_range(month)[1]}}) > 0
    start, end = month_range(month)
    docs = list(db.expenses.find({"uid": uid, "date": {"$gte": start, "$lt": end}}).sort("date", DESCENDING).limit(limit + 1))
    expenses = []
    for doc in docs[:limit]:
        amount = expense_amount_for_currency(doc, currency)
        expenses.append({
            "date": iso(aware(doc.get("date"))) if doc.get("date") else None,
            "description": ai_context_text(doc.get("description") or doc.get("category") or "Expense", 72),
            "category": ai_context_text(doc.get("category") or "Personal", 48),
            "amount": ai_context_money(amount if amount is not None else doc.get("amount")),
            "currency": currency if amount is not None else safe_currency(doc.get("currency"), currency),
            "paymentMethod": ai_context_text(doc.get("paymentMethod"), 32),
        })
    return expenses, len(docs) > limit


def ai_context_top_merchants(db: Any, uid: str, month: str, currency: str, limit: int) -> tuple[list[dict[str, Any]], bool]:
    start, end = month_range(month)
    totals: dict[str, dict[str, Any]] = {}
    for doc in db.expenses.find({"uid": uid, "date": {"$gte": start, "$lt": end}}):
        merchant = ai_context_text(doc.get("description") or doc.get("category") or "Expense", 64)
        if not merchant:
            continue
        amount = expense_amount_for_currency(doc, currency)
        if amount is None:
            continue
        entry = totals.setdefault(merchant, {"merchant": merchant, "amount": 0.0, "count": 0})
        entry["amount"] = ai_context_money(float(entry["amount"]) + float(amount or 0))
        entry["count"] = int(entry["count"]) + 1
    ranked = sorted(totals.values(), key=lambda item: float(item.get("amount") or 0), reverse=True)
    return ranked[:limit], len(ranked) > limit


def build_ai_financial_context(
    db: Any,
    uid: str,
    *,
    purpose: str = "finance_chat",
    month: str = "",
    overall_summary: dict[str, Any] | None = None,
    action_items: list[dict[str, Any]] | None = None,
    activity_items: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    purpose = purpose if purpose in AI_CONTEXT_PURPOSE_LIMITS else "finance_chat"
    limits = ai_context_limits(purpose)
    period = normalize_month(month or current_month())
    plan = monthly_plan_out(db, uid, period)
    raw_plan = db.monthly_plans.find_one({"uid": uid, "month": period}) or {}
    currency = str(plan.get("currency") or "INR")
    raw_categories = plan.get("categories") if isinstance(plan.get("categories"), list) else []
    categories = [
        {
            "category": ai_context_text(item.get("category") or "Personal", 48),
            "budget": ai_context_money(item.get("budget")),
            "actual": ai_context_money(item.get("actual")),
            "remaining": ai_context_money(item.get("remaining")),
            "overBudget": bool(item.get("overBudget")),
        }
        for item in raw_categories
        if isinstance(item, dict)
    ]
    categories.sort(key=lambda item: abs(float(item.get("budget") or item.get("actual") or 0)), reverse=True)
    category_limit = limits["maxCategories"]
    action_limit = limits["maxActionItems"]
    merchant_limit = limits["maxMerchants"]
    recent_limit = limits["maxRecentExpenses"]
    limited_categories = categories[:category_limit]
    resolved_actions = action_items if action_items is not None else dashboard_action_items(db, uid)
    limited_actions = [
        {
            "title": ai_context_text(item.get("title"), 80),
            "subtitle": ai_context_text(item.get("subtitle"), 120),
            "severity": ai_context_text(item.get("severity"), 24),
            "destination": ai_context_text(item.get("destination"), 32),
            "actionType": ai_context_text(item.get("actionType"), 48),
            "category": ai_context_text(item.get("category"), 48),
        }
        for item in resolved_actions[:action_limit]
    ]
    recent_expenses, recent_truncated = ai_context_recent_expenses(db, uid, period, currency, recent_limit)
    top_merchants, merchants_truncated = ai_context_top_merchants(db, uid, period, currency, merchant_limit)
    previous_month = add_months(period, -1)
    current_actual = ai_context_money(plan.get("totalActual"))
    previous_actual = ai_context_month_actual(db, uid, previous_month, currency)
    total_budget = ai_context_money(plan.get("totalBudget"))
    total_remaining = ai_context_money(plan.get("totalRemaining"))
    income = raw_plan.get("income")
    surplus = ai_context_money(income) - total_budget if income is not None else None
    today = now()
    days_in_month = calendar.monthrange(today.year, today.month)[1] if period == current_month() else calendar.monthrange(int(period[:4]), int(period[5:7]))[1]
    day_of_month = min(today.day, days_in_month) if period == current_month() else days_in_month
    projected_spend = ai_context_money((current_actual / max(day_of_month, 1)) * days_in_month) if current_actual > 0 else 0.0
    budget_usage = round(current_actual / total_budget, 4) if total_budget > 0 else 0.0
    month_delta = ai_context_money(current_actual - previous_actual)
    month_delta_percent = round(month_delta / previous_actual, 4) if previous_actual > 0 else None
    largest_category = limited_categories[0] if limited_categories else None
    context = {
        "schemaVersion": AI_CONTEXT_SCHEMA_VERSION,
        "purpose": purpose,
        "generatedAt": iso(today),
        "currentDate": iso(today),
        "month": period,
        "currency": currency,
        "limits": limits,
        "summary": {
            "currency": currency,
            "income": ai_context_money(income) if income is not None else None,
            "plannedCosts": total_budget,
            "actualSpend": current_actual,
            "remainingBudget": total_remaining,
            "surplus": ai_context_money(surplus) if surplus is not None else None,
            "categoryCount": len(categories),
            "actionItemCount": len(resolved_actions),
            "recentExpenseCount": db.expenses.count_documents({"uid": uid, "date": {"$gte": month_range(period)[0], "$lt": month_range(period)[1]}}),
        },
        "trends": {
            "previousMonth": previous_month,
            "previousMonthActualSpend": previous_actual,
            "monthToDateSpend": current_actual,
            "monthOverMonthDelta": month_delta,
            "monthOverMonthDeltaPercent": month_delta_percent,
            "projectedMonthEndSpend": projected_spend,
            "budgetUsagePercent": budget_usage,
            "largestCategory": largest_category,
            "overBudgetCategories": [item for item in categories if item.get("overBudget")][:3],
        },
        "overall": overall_summary or dashboard_overall_summary(db, uid),
        "monthlyPlan": {
            "month": plan.get("month"),
            "currency": currency,
            "totalBudget": total_budget,
            "totalActual": current_actual,
            "totalRemaining": total_remaining,
            "income": ai_context_money(income) if income is not None else None,
            "surplus": ai_context_money(surplus) if surplus is not None else None,
            "categories": limited_categories,
        },
        "topMerchants": top_merchants,
        "recentExpenses": recent_expenses,
        "actionItems": limited_actions,
        "friendItems": friend_balance_items(db, uid)[:4],
        "groupItems": group_balance_items(db, uid)[:4],
        "truncated": False,
        "truncation": {
            "categories": len(categories) > category_limit,
            "actionItems": len(resolved_actions) > action_limit,
            "recentExpenses": recent_truncated,
            "topMerchants": merchants_truncated,
        },
    }
    context["truncated"] = any(bool(value) for value in context["truncation"].values())
    context["estimatedBytes"] = len(json.dumps(json_ready(context), default=str, separators=(",", ":")))
    return context


def dashboard_ai_context(
    db: Any,
    uid: str,
    *,
    overall_summary: dict[str, Any] | None = None,
    action_items: list[dict[str, Any]] | None = None,
    activity_items: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    return build_ai_financial_context(
        db,
        uid,
        purpose="finance_chat",
        overall_summary=overall_summary,
        action_items=action_items,
        activity_items=activity_items,
    )


async def generate_ai_dashboard_summary(provider: Any, context: dict[str, Any]) -> dict[str, Any]:
    if hasattr(provider, "dashboard_summary"):
        return await provider.dashboard_summary(context)
    return fallback_ai_dashboard_summary(context)


async def generate_ai_finance_chat(provider: Any, context: dict[str, Any], question: str) -> dict[str, Any]:
    if hasattr(provider, "finance_chat"):
        return await provider.finance_chat(context, question)
    return fallback_ai_finance_chat(context, question)


def format_currency_amounts(amounts: dict[str, float]) -> str:
    non_zero = [(currency, amount) for currency, amount in amounts.items() if abs(amount) > 0.005]
    if not non_zero:
        return "INR 0.00"
    return ", ".join(format_currency_amount(currency, abs(amount)) for currency, amount in sorted(non_zero))


def merge_currency_amounts(target: dict[str, float], amounts: dict[str, float]) -> None:
    for currency, raw_amount in amounts.items():
        normalized_currency = safe_currency(currency, "INR") or "INR"
        amount = float(raw_amount or 0)
        if abs(amount) <= 0.005:
            continue
        target[normalized_currency] = target.get(normalized_currency, 0.0) + amount


def monthly_plan_group_owner(group_id: str) -> str:
    return f"group:{group_id}"


def monthly_plan_scope(db: Any, uid: str, raw_group_id: Any = "") -> tuple[str, str | None]:
    group_id = str(raw_group_id or "").strip()
    if not group_id:
        return uid, None
    require_group_member(db, group_id, uid)
    return monthly_plan_group_owner(group_id), group_id


def is_income_activity_entry(expense: dict[str, Any]) -> bool:
    return str(expense.get("sourcePaymentType") or "").strip().lower() == "income"


def income_amount_for_currency(doc: dict[str, Any], currency: str) -> float:
    amount = expense_amount_for_currency(doc, currency)
    if amount is None:
        return 0.0
    return max(0.0, amount)


def monthly_activity_income(db: Any, uid: str, month: str, currency: str) -> float:
    start, end = month_range(month)
    docs = db.expenses.find({
        "uid": uid,
        "sourcePaymentType": "income",
        "date": {"$gte": start, "$lt": end},
    })
    return sum(income_amount_for_currency(doc, currency) for doc in docs)


def monthly_recurring_income(db: Any, uid: str, month: str, currency: str) -> float:
    total = 0.0
    start, end = month_range(month)
    templates = db.recurring_templates.find({
        "uid": uid,
        "kind": "income",
        "deletedAt": {"$exists": False},
    })
    for template in templates:
        if not template.get("active", True):
            continue
        starts_this_month = start <= aware(template.get("startDate") or start) < end
        if not recurring_due_dates_for_month(template, month) and not starts_this_month:
            continue
        total += income_amount_for_currency(template, currency)
    return total


def effective_monthly_income(
    db: Any,
    uid: str,
    month: str,
    currency: str,
    raw_income: Any,
    *,
    group_id: str | None = None,
) -> float | None:
    stored_income: float | None = None
    if raw_income is not None:
        try:
            stored_income = max(0.0, float(raw_income))
        except (TypeError, ValueError):
            stored_income = None
    if stored_income is not None and stored_income > 0.005:
        return stored_income
    if group_id:
        return stored_income
    activity_income = monthly_activity_income(db, uid, month, currency)
    if activity_income > 0.005:
        return activity_income
    recurring_income = monthly_recurring_income(db, uid, month, currency)
    if recurring_income > 0.005:
        return recurring_income
    return stored_income


def setup_month_entry_date(month: str, day: Any | None = None, fallback: datetime | None = None) -> datetime:
    year, month_number = [int(part) for part in month.split("-")]
    if day is not None:
        try:
            return month_day_date(year, month_number, int(day))
        except (TypeError, ValueError):
            pass
    fallback_date = aware(fallback or now())
    start, end = month_range(month)
    if start <= fallback_date < end:
        return fallback_date
    return start


def account_reference_for_name(db: Any, uid: str, account_name: Any, currency: str = "") -> dict[str, str]:
    name = str(account_name or "").strip()
    if not name:
        return {}
    filters: dict[str, Any] = {
        "uid": uid,
        "archivedAt": {"$exists": False},
    }
    normalized_currency = safe_currency(currency, "")
    if normalized_currency:
        filters["currency"] = normalized_currency
    candidates = list(db.financial_accounts.find(filters))
    normalized_name = name.lower()
    for account in candidates:
        label = str(account.get("name") or "").strip()
        institution = str(account.get("institution") or "").strip()
        display = f"{label} - {institution}" if institution else label
        if normalized_name in {label.lower(), display.lower()}:
            return {
                "id": str(account.get("id") or ""),
                "name": display or label or name,
            }
    return {"name": name}


def salary_account_reference(db: Any, uid: str, currency: str = "") -> dict[str, str]:
    template = db.recurring_templates.find_one(
        {
            "uid": uid,
            "kind": "income",
            "category": "Salary",
            "deletedAt": {"$exists": False},
        },
        sort=[("updatedAt", DESCENDING)],
    )
    if not template:
        return {}
    account_id = str(template.get("sourceAccountId") or "").strip()
    account_name = str(template.get("sourceAccountName") or template.get("accountName") or "").strip()
    if account_id:
        account = db.financial_accounts.find_one({
            "uid": uid,
            "id": account_id,
            "archivedAt": {"$exists": False},
        })
        if account:
            return {"id": account_id, "name": financial_account_label(account)}
        return {"id": account_id, "name": account_name}
    return account_reference_for_name(db, uid, account_name, currency or template.get("currency") or "")


def insert_setup_month_entry_if_missing(
    db: Any,
    uid: str,
    *,
    month: str,
    setup_key: str,
    title: str,
    category: str,
    amount: float,
    currency: str,
    date: datetime,
    entry_type: str,
    payment_method: str | None = None,
    source_account_id: str = "",
    source_account_name: str = "",
    source_destination_account_id: str = "",
    source_destination_account_name: str = "",
) -> bool:
    if amount <= 0:
        return False
    existing = db.expenses.find_one({
        "uid": uid,
        "sourceType": "setup_month_entry",
        "sourcePeriod": month,
        "sourceSetupKey": setup_key,
    })
    if existing:
        updates: dict[str, Any] = {}
        if source_account_id and not existing.get("sourceAccountId"):
            updates["sourceAccountId"] = source_account_id
        if source_account_name and not existing.get("sourceAccountName"):
            updates["sourceAccountName"] = source_account_name
        if source_destination_account_id and not existing.get("sourceDestinationAccountId"):
            updates["sourceDestinationAccountId"] = source_destination_account_id
        if source_destination_account_name and not existing.get("sourceDestinationAccountName"):
            updates["sourceDestinationAccountName"] = source_destination_account_name
        if (
            payment_method
            and not existing.get("sourceAccountId")
            and str(existing.get("paymentMethod") or "").strip().lower() in {"", "cash", "paid_previously"}
        ):
            updates["paymentMethod"] = payment_method
        if updates:
            updates["updatedAt"] = now()
            db.expenses.update_one({"id": existing["id"], "uid": uid}, {"$set": updates})
        return False
    expense = build_expense(
        {
            "amount": amount,
            "currency": currency,
            "category": category,
            "description": title,
            "paymentMethod": payment_method or ("income" if entry_type == "income" else "paid_previously"),
            "date": iso(date),
            "sourceType": "setup_month_entry",
            "sourcePaymentType": entry_type,
            "sourcePeriod": month,
            "sourceSetupKey": setup_key,
            "sourceAccountId": source_account_id,
            "sourceAccountName": source_account_name,
            "sourceDestinationAccountId": source_destination_account_id,
            "sourceDestinationAccountName": source_destination_account_name,
        },
        uid,
    )
    db.expenses.insert_one(expense)
    return True


def ensure_setup_month_activity_entries(db: Any, uid: str, month: str | None = None) -> int:
    period = normalize_month(month or current_month())
    created = 0
    start, end = month_range(period)

    recurring_templates = db.recurring_templates.find({
        "uid": uid,
        "deletedAt": {"$exists": False},
    })
    for template in recurring_templates:
        if not template.get("active", True):
            continue
        template_id = str(template.get("id") or "")
        if template_id and db.recurring_occurrences.find_one({
            "uid": uid,
            "templateId": template_id,
            "status": "confirmed",
        }):
            continue
        due_dates = recurring_due_dates_for_month(template, period)
        starts_this_month = start <= aware(template.get("startDate") or start) < end
        if not due_dates and not starts_this_month:
            continue
        entry_type = "income" if str(template.get("kind") or "expense").strip().lower() == "income" else "expense"
        template_account_id = str(template.get("sourceAccountId") or "").strip()
        template_account_name = str(template.get("sourceAccountName") or template.get("accountName") or "").strip()
        payment_method = None
        if template_account_id:
            payment_method = f"account:{template_account_id}"
        date = due_dates[0] if due_dates else setup_month_entry_date(period, template.get("dayOfMonth"), template.get("startDate"))
        created += int(insert_setup_month_entry_if_missing(
            db,
            uid,
            month=period,
            setup_key=f"recurring:{template.get('id')}",
            title=str(template.get("title") or template.get("category") or "Recurring item"),
            category=str(template.get("category") or ("Income" if entry_type == "income" else "Personal")),
            amount=float(template.get("expectedAmount") or template.get("amount") or 0),
            currency=safe_currency(template.get("currency"), "INR") or "INR",
            date=date,
            entry_type=entry_type,
            payment_method=payment_method,
            source_account_id=template_account_id,
            source_account_name=template_account_name,
        ))

    loans = db.loans.find({"uid": uid, "archivedAt": {"$exists": False}})
    for loan in loans:
        loan_id = str(loan.get("id") or "")
        if loan_id and (
            db.loan_payments.find_one({"uid": uid, "loanId": loan_id})
            or db.expenses.find_one({"uid": uid, "sourceLoanId": loan_id})
        ):
            continue
        loan_start = aware(loan.get("startDate") or loan.get("trackingStartedAt") or start)
        if loan_start >= end:
            continue
        created += int(insert_setup_month_entry_if_missing(
            db,
            uid,
            month=period,
            setup_key=f"loan:{loan_id}",
            title=str(loan.get("name") or "Loan EMI"),
            category=str(loan.get("category") or "Loans / EMI"),
            amount=float(loan.get("emiAmount") or 0),
            currency=safe_currency(loan.get("currency"), "INR") or "INR",
            date=setup_month_entry_date(period, loan.get("dueDay"), loan_start),
            entry_type="expense",
        ))

    savings_goals = db.savings_goals.find({"uid": uid, "archivedAt": {"$exists": False}})
    salary_account = salary_account_reference(db, uid)
    for goal in savings_goals:
        goal_id = str(goal.get("id") or "")
        if goal_id and db.savings_contributions.find_one({"uid": uid, "goalId": goal_id}):
            continue
        start_month = normalize_month(str(goal.get("startMonth") or period))
        if start_month > period:
            continue
        name = str(goal.get("name") or "Savings")
        destination_ref = account_reference_for_name(db, uid, goal.get("accountName"), goal.get("sourceCurrency"))
        created += int(insert_setup_month_entry_if_missing(
            db,
            uid,
            month=period,
            setup_key=f"savings:{goal_id}",
            title=name,
            category=f"Savings - {name}" if name.lower() != "savings" else "Savings",
            amount=float(goal.get("monthlyTargetAmount") or 0),
            currency=safe_currency(goal.get("sourceCurrency"), "INR") or "INR",
            date=setup_month_entry_date(period, fallback=goal.get("createdAt")),
            entry_type="expense",
            source_account_id=salary_account.get("id", ""),
            source_account_name=salary_account.get("name", ""),
            source_destination_account_id=destination_ref.get("id", ""),
            source_destination_account_name=destination_ref.get("name", ""),
        ))

    return created


def monthly_plan_out(db: Any, uid: str, month: str, group_id: str | None = None) -> dict[str, Any]:
    plan = db.monthly_plans.find_one({"uid": uid, "month": month}) or {}
    plan_currency = safe_currency(plan.get("currency"), "INR") or "INR"
    raw_budgets = plan.get("budgets") if isinstance(plan.get("budgets"), dict) else {}
    budgets = {str(key): float(value or 0) for key, value in raw_budgets.items()}
    start, end = month_range(month)
    actuals: dict[str, float] = {}
    converted_counts: dict[str, int] = {}
    excluded_counts: dict[str, int] = {}
    excluded_actuals: dict[str, dict[str, float]] = {}

    def add_expense(expense: dict[str, Any]) -> None:
        if is_income_activity_entry(expense):
            return
        category = str(expense.get("category") or "Personal").strip() or "Personal"
        amount = expense_amount_for_currency(expense, plan_currency)
        if amount is not None:
            actuals[category] = actuals.get(category, 0.0) + amount
            original = original_expense_amount_by_currency(expense)
            if original and original[0] != plan_currency:
                converted_counts[category] = converted_counts.get(category, 0) + 1
            return

        original = original_expense_amount_by_currency(expense)
        if original is None:
            return
        currency, original_amount = original
        if currency == plan_currency or abs(original_amount) <= 0.005:
            return
        excluded_counts[category] = excluded_counts.get(category, 0) + 1
        category_excluded = excluded_actuals.setdefault(category, {})
        category_excluded[currency] = category_excluded.get(currency, 0.0) + original_amount

    if group_id:
        family_expenses = db.group_expenses.find({
            "groupId": group_id,
            "date": {"$gte": start, "$lt": end},
        })
        for expense in family_expenses:
            add_expense(expense)
    else:
        expenses = db.expenses.find({"uid": uid, "date": {"$gte": start, "$lt": end}})
        for expense in expenses:
            add_expense(expense)
        family_groups = list(db.groups.find({"memberUids": uid, "groupType": "family"}))
        family_group_ids = [group.get("id") for group in family_groups if group.get("id")]
        if family_group_ids:
            family_expenses = db.group_expenses.find({
                "groupId": {"$in": family_group_ids},
                "date": {"$gte": start, "$lt": end},
            })
            for expense in family_expenses:
                add_expense(expense)
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
            "convertedExpenseCount": converted_counts.get(category, 0),
            "excludedExpenseCount": excluded_counts.get(category, 0),
            "skippedActualExpenseCount": excluded_counts.get(category, 0),
            "excludedActualsByCurrency": excluded_actuals.get(category, {}),
        })
    total_budget = sum(budgets.values())
    total_actual = sum(actuals.values())
    planned_income = effective_monthly_income(
        db,
        uid,
        month,
        plan_currency,
        plan.get("income"),
        group_id=group_id,
    )
    projected_surplus = (
        planned_income - total_budget
        if planned_income is not None
        else None
    )
    total_excluded: dict[str, float] = {}
    for amounts in excluded_actuals.values():
        for currency, amount in amounts.items():
            total_excluded[currency] = total_excluded.get(currency, 0.0) + amount
    return json_ready({
        "month": month,
        "groupId": group_id,
        "currency": plan_currency,
        "totalBudget": total_budget,
        "totalActual": total_actual,
        "totalRemaining": total_budget - total_actual,
        "income": planned_income,
        "monthlyIncome": planned_income,
        "totalIncome": planned_income,
        "surplus": projected_surplus,
        "netSurplus": projected_surplus,
        "projectedSurplus": projected_surplus,
        "convertedExpenseCount": sum(converted_counts.values()),
        "excludedExpenseCount": sum(excluded_counts.values()),
        "skippedActualExpenseCount": sum(excluded_counts.values()),
        "excludedActualsByCurrency": total_excluded,
        "actualsMetadata": {
            "convertedExpenseCount": sum(converted_counts.values()),
            "uncountedExpenseCount": sum(excluded_counts.values()),
            "uncountedSpendByCurrency": total_excluded,
            "uncountedSpendByCategoryByCurrency": excluded_actuals,
        },
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
    return json_ready(
        {
            "id": doc.get("id"),
            "uids": doc.get("uids"),
            "payerUid": doc.get("payerUid"),
            "receiverUid": doc.get("receiverUid"),
            "amount": doc.get("amount"),
            "currency": doc.get("currency"),
            "note": doc.get("note"),
            "createdBy": doc.get("createdBy"),
            "date": doc.get("date") or doc.get("createdAt"),
            "createdAt": doc.get("createdAt"),
            "updatedAt": doc.get("updatedAt") or doc.get("createdAt"),
        }
    )


def group_settlement_out(doc: dict[str, Any]) -> dict[str, Any]:
    return json_ready(
        {
            "id": doc.get("id"),
            "groupId": doc.get("groupId"),
            "payerUid": doc.get("payerUid"),
            "receiverUid": doc.get("receiverUid"),
            "amount": doc.get("amount"),
            "currency": doc.get("currency"),
            "note": doc.get("note"),
            "createdBy": doc.get("createdBy"),
            "date": doc.get("date") or doc.get("createdAt"),
            "createdAt": doc.get("createdAt"),
            "updatedAt": doc.get("updatedAt") or doc.get("createdAt"),
        }
    )


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


def split_group_balance_totals_by_currency(db: Any, uid: str) -> dict[str, float]:
    totals: dict[str, float] = {}
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
        merge_currency_amounts(totals, net_by_currency)
    return totals


def dashboard_overall_summary(db: Any, uid: str) -> dict[str, Any]:
    totals: dict[str, float] = {}
    for friend_amounts in friend_balance_map_by_currency(db, uid).values():
        merge_currency_amounts(totals, friend_amounts)
    merge_currency_amounts(totals, split_group_balance_totals_by_currency(db, uid))

    if not totals:
        return {
            "overallLabel": "Shared balances",
            "overallAmountText": "All settled",
            "overallPositive": True,
        }

    if all(amount > 0 for amount in totals.values()):
        return {
            "overallLabel": "Shared balances",
            "overallAmountText": f"You are owed {format_currency_amounts(totals)}",
            "overallPositive": True,
        }
    if all(amount < 0 for amount in totals.values()):
        return {
            "overallLabel": "Shared balances",
            "overallAmountText": f"You owe {format_currency_amounts(totals)}",
            "overallPositive": False,
        }
    return {
        "overallLabel": "Shared balances",
        "overallAmountText": f"Mixed balances · {format_currency_amounts(totals)}",
        "overallPositive": True,
    }


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
    month_increment = 12 if frequency == "yearly" else 3 if frequency == "quarterly" else 1
    month = start.month + month_increment
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
    if app.state.upload_dir.resolve() not in full.parents and full != app.state.upload_dir.resolve():
        raise HTTPException(status_code=403, detail=api_error("FORBIDDEN", "invalid upload path"))
    if not full.exists():
        raise HTTPException(status_code=404, detail=api_error("NOT_FOUND", "attachment not found"))
    return full


def can_access_upload_path(db: Any, path: str, uid: str) -> bool:
    parts = [part for part in Path(path).parts if part not in {"", "."}]
    if len(parts) < 2:
        return False
    if parts[0] in {"users", "bills"}:
        return parts[1] == uid
    if parts[0] == "groups" and len(parts) >= 3:
        return bool(db.groups.find_one({"id": parts[1], "memberUids": uid}))
    return False


async def run_bill_extraction(app: FastAPI, job_id: str) -> None:
    job = app.state.db.ai_jobs.find_one({"id": job_id})
    if not job:
        return
    app.state.db.ai_jobs.update_one({"id": job_id}, {"$set": {"status": "processing", "updatedAt": now()}})
    started = time.perf_counter()
    ai_terminal_log(
        "bill_job.processing",
        jobId=job_id,
        fileUrl=job.get("fileUrl"),
        fileName=job.get("fileName"),
    )
    try:
        file_path = upload_path_from_url(app, job["fileUrl"])
        result = await app.state.ai_provider.extract(file_path, job.get("fileName") or "bill")
        if isinstance(result, dict) and result.get("task") != "receipt_extraction":
            result = LocalGemmaBillExtractor(None, "")._normalize(result, job.get("fileName") or "bill", [])
        app.state.db.ai_jobs.update_one({"id": job_id}, {"$set": {"status": "completed", "result": result, "updatedAt": now()}})
        ai_terminal_log(
            "bill_job.completed",
            jobId=job_id,
            elapsedMs=round((time.perf_counter() - started) * 1000),
            result=result,
        )
    except Exception as exc:
        app.state.db.ai_jobs.update_one({"id": job_id}, {"$set": {"status": "failed", "error": str(exc), "updatedAt": now()}})
        ai_terminal_log(
            "bill_job.failed",
            jobId=job_id,
            elapsedMs=round((time.perf_counter() - started) * 1000),
            error=repr(exc),
        )


app = create_app()
