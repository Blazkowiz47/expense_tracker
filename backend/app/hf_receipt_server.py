from __future__ import annotations

import json
import os
import re
import time
from pathlib import Path
from typing import Any

from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel

from app.ai_prompts import load_prompt


DEFAULT_MODEL = "google/gemma-4-E4B-it"
SYSTEM_PROMPT = load_prompt("receipt_extraction_system.md")
USER_PROMPT = load_prompt("receipt_extraction_user.md")


def hf_terminal_log(event: str, **fields: Any) -> None:
    if os.getenv("AI_LOG_INTERACTIONS", "1").strip().lower() in {"0", "false", "no", "off"}:
        return
    payload = {"event": event, **fields}
    print("[hf-ai] " + json.dumps(payload, default=str, ensure_ascii=False), flush=True)


class ExtractBillRequest(BaseModel):
    path: str
    fileName: str = ""
    model: str | None = None


def api_error(code: str, message: str) -> dict[str, Any]:
    return {"error": {"code": code, "message": message}}


def sanitized_receipt_payload(raw: dict[str, Any]) -> dict[str, Any]:
    return {
        "merchant": str(raw.get("merchant") or "").strip(),
        "date": str(raw.get("date") or "").strip(),
        "amount": raw.get("amount", 0),
        "currency": str(raw.get("currency") or "INR").strip() or "INR",
        "category": str(raw.get("category") or "Personal").strip() or "Personal",
        "notes": str(raw.get("notes") or "").strip(),
        "lineItems": raw.get("lineItems") if isinstance(raw.get("lineItems"), list) else [],
        "confidence": raw.get("confidence", 0),
        "warnings": raw.get("warnings") if isinstance(raw.get("warnings"), list) else [],
    }


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


class HuggingFaceGemmaReceiptExtractor:
    def __init__(self) -> None:
        self._processor: Any | None = None
        self._model: Any | None = None
        self._loaded_model_id = ""

    async def extract_receipt(self, file_path: Path, file_name: str, model_id: str) -> dict[str, Any]:
        started = time.perf_counter()
        hf_terminal_log(
            "receipt.extract.start",
            model=model_id,
            filePath=str(file_path),
            fileName=file_name,
            fileSizeBytes=file_path.stat().st_size if file_path.exists() else None,
            systemPrompt=SYSTEM_PROMPT,
            userPrompt=USER_PROMPT,
        )
        processor, model = self._load(model_id)
        image = self._load_image(file_path)
        hf_terminal_log(
            "receipt.extract.image_loaded",
            model=model_id,
            elapsedMs=round((time.perf_counter() - started) * 1000),
            size=getattr(image, "size", None),
            mode=getattr(image, "mode", None),
        )
        messages = [
            {"role": "system", "content": SYSTEM_PROMPT},
            {
                "role": "user",
                "content": [
                    {"type": "image", "image": image},
                    {"type": "text", "text": USER_PROMPT},
                ],
            },
        ]
        hf_terminal_log(
            "receipt.extract.messages",
            model=model_id,
            messages=[
                {"role": "system", "content": SYSTEM_PROMPT},
                {
                    "role": "user",
                    "content": [
                        {"type": "image", "image": f"[PIL image {getattr(image, 'size', None)}]"},
                        {"type": "text", "text": USER_PROMPT},
                    ],
                },
            ],
        )
        inputs = processor.apply_chat_template(
            messages,
            tokenize=True,
            return_dict=True,
            return_tensors="pt",
            add_generation_prompt=True,
            enable_thinking=False,
        )
        model_device = getattr(model, "device", None)
        if model_device is not None and hasattr(inputs, "to"):
            inputs = inputs.to(model_device)

        torch = self._import_torch()
        max_new_tokens = int(os.getenv("HF_RECEIPT_MAX_NEW_TOKENS", "768"))
        hf_terminal_log(
            "receipt.extract.generate_start",
            model=model_id,
            maxNewTokens=max_new_tokens,
            elapsedMs=round((time.perf_counter() - started) * 1000),
        )
        with torch.inference_mode():
            outputs = model.generate(**inputs, max_new_tokens=max_new_tokens)

        input_len = inputs["input_ids"].shape[-1]
        decoded = processor.decode(outputs[0][input_len:], skip_special_tokens=False)
        hf_terminal_log(
            "receipt.extract.raw_model_text",
            model=model_id,
            elapsedMs=round((time.perf_counter() - started) * 1000),
            content=decoded,
        )
        parsed = self._parse_response(processor, decoded)
        hf_terminal_log(
            "receipt.extract.parsed_json",
            model=model_id,
            elapsedMs=round((time.perf_counter() - started) * 1000),
            parsed=parsed,
        )
        payload = sanitized_receipt_payload(parsed)
        if not payload["merchant"]:
            payload["merchant"] = Path(file_name or file_path.name).stem.replace("_", " ").title()
        hf_terminal_log(
            "receipt.extract.done",
            model=model_id,
            elapsedMs=round((time.perf_counter() - started) * 1000),
            payload=payload,
        )
        return payload

    def _load(self, model_id: str) -> tuple[Any, Any]:
        model_id = model_id.strip() or DEFAULT_MODEL
        if self._processor is not None and self._model is not None and self._loaded_model_id == model_id:
            hf_terminal_log("model.cache_hit", model=model_id)
            return self._processor, self._model

        try:
            from transformers import AutoModelForMultimodalLM, AutoProcessor
        except ImportError as exc:  # pragma: no cover - covered by install docs
            raise RuntimeError(
                "Hugging Face Gemma dependencies are missing. "
                "Install them with: pip install -r backend/requirements-ai.txt"
            ) from exc

        device = os.getenv("HF_DEVICE", "").strip()
        kwargs: dict[str, Any] = {}
        if not device:
            kwargs["device_map"] = os.getenv("HF_DEVICE_MAP", "auto")
        dtype = os.getenv("HF_TORCH_DTYPE", "auto").strip()
        if dtype:
            kwargs["dtype"] = self._torch_dtype(dtype)

        started = time.perf_counter()
        hf_terminal_log("model.load_start", model=model_id, kwargs=kwargs)
        self._processor = AutoProcessor.from_pretrained(model_id)
        self._model = AutoModelForMultimodalLM.from_pretrained(model_id, **kwargs)
        if device and hasattr(self._model, "to"):
            self._model = self._model.to(device)
        self._loaded_model_id = model_id
        hf_terminal_log(
            "model.load_done",
            model=model_id,
            elapsedMs=round((time.perf_counter() - started) * 1000),
        )
        return self._processor, self._model

    def _torch_dtype(self, dtype: str) -> Any:
        if dtype == "auto":
            return "auto"
        torch = self._import_torch()
        return {
            "bfloat16": torch.bfloat16,
            "bf16": torch.bfloat16,
            "float16": torch.float16,
            "fp16": torch.float16,
            "float32": torch.float32,
            "fp32": torch.float32,
        }.get(dtype, dtype)

    def _load_image(self, file_path: Path) -> Any:
        try:
            from PIL import Image
        except ImportError as exc:  # pragma: no cover - covered by install docs
            raise RuntimeError(
                "Pillow is missing. Install AI dependencies with: "
                "pip install -r backend/requirements-ai.txt"
            ) from exc
        with Image.open(file_path) as image:
            return image.convert("RGB")

    def _import_torch(self) -> Any:
        try:
            import torch
        except ImportError as exc:  # pragma: no cover - covered by install docs
            raise RuntimeError(
                "PyTorch is missing. Install AI dependencies with: "
                "pip install -r backend/requirements-ai.txt"
            ) from exc
        return torch

    def _parse_response(self, processor: Any, decoded: str) -> dict[str, Any]:
        if hasattr(processor, "parse_response"):
            try:
                parsed = processor.parse_response(decoded)
                if isinstance(parsed, dict):
                    if "content" in parsed and "merchant" not in parsed:
                        return parse_model_json(parsed.get("content"))
                    return parsed
                if isinstance(parsed, str):
                    return parse_model_json(parsed)
            except Exception:
                pass
        return parse_model_json(decoded)


def create_hf_receipt_app(
    extractor: HuggingFaceGemmaReceiptExtractor | Any | None = None,
) -> FastAPI:
    app = FastAPI(title="Expense Tracker Hugging Face Receipt AI")
    app.state.extractor = extractor or HuggingFaceGemmaReceiptExtractor()
    app.state.default_model = os.getenv("HF_RECEIPT_MODEL", DEFAULT_MODEL)

    @app.exception_handler(HTTPException)
    async def http_exception_handler(_request: Any, exc: HTTPException) -> JSONResponse:
        if isinstance(exc.detail, dict) and "error" in exc.detail:
            return JSONResponse(status_code=exc.status_code, content=exc.detail)
        return JSONResponse(
            status_code=exc.status_code,
            content=api_error("HTTP_ERROR", str(exc.detail)),
        )

    @app.get("/health")
    def health() -> dict[str, str]:
        return {"status": "ok", "model": app.state.default_model}

    @app.on_event("startup")
    def preload_model() -> None:
        if os.getenv("HF_PRELOAD_MODEL", "1").strip().lower() in {"0", "false", "no", "off"}:
            hf_terminal_log("model.preload_skipped", model=app.state.default_model)
            return
        if not hasattr(app.state.extractor, "_load"):
            hf_terminal_log("model.preload_unavailable", model=app.state.default_model)
            return
        started = time.perf_counter()
        try:
            hf_terminal_log("model.preload_start", model=app.state.default_model)
            app.state.extractor._load(app.state.default_model)
            hf_terminal_log(
                "model.preload_done",
                model=app.state.default_model,
                elapsedMs=round((time.perf_counter() - started) * 1000),
            )
        except Exception as exc:
            hf_terminal_log(
                "model.preload_failed",
                model=app.state.default_model,
                elapsedMs=round((time.perf_counter() - started) * 1000),
                error=repr(exc),
            )

    @app.post("/api/v1/extract-bill")
    async def extract_bill(body: ExtractBillRequest) -> dict[str, Any]:
        started = time.perf_counter()
        file_path = Path(body.path).expanduser().resolve()
        if not file_path.exists() or not file_path.is_file():
            raise HTTPException(
                status_code=400,
                detail=api_error("INVALID_FILE", "receipt file does not exist"),
            )
        model_id = (body.model or app.state.default_model).strip() or app.state.default_model
        hf_terminal_log(
            "request.extract_bill",
            path=str(file_path),
            fileName=body.fileName or file_path.name,
            model=model_id,
        )
        try:
            raw = await app.state.extractor.extract_receipt(
                file_path,
                body.fileName or file_path.name,
                model_id,
            )
        except RuntimeError as exc:
            hf_terminal_log(
                "request.extract_bill.error",
                elapsedMs=round((time.perf_counter() - started) * 1000),
                error=repr(exc),
            )
            raise HTTPException(
                status_code=503,
                detail=api_error("MODEL_UNAVAILABLE", str(exc)),
            ) from exc
        except Exception as exc:
            hf_terminal_log(
                "request.extract_bill.error",
                elapsedMs=round((time.perf_counter() - started) * 1000),
                error=repr(exc),
            )
            raise HTTPException(
                status_code=500,
                detail=api_error("EXTRACTION_FAILED", str(exc)),
            ) from exc
        payload = sanitized_receipt_payload(raw)
        hf_terminal_log(
            "request.extract_bill.done",
            elapsedMs=round((time.perf_counter() - started) * 1000),
            payload=payload,
        )
        return payload

    return app


app = create_hf_receipt_app()
