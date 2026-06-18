from pathlib import Path

from fastapi.testclient import TestClient

from app.hf_receipt_server import (
    HuggingFaceGemmaReceiptExtractor,
    create_hf_receipt_app,
    parse_model_json,
)


class FakeReceiptExtractor:
    def __init__(self):
        self.calls = []

    async def extract_receipt(self, file_path: Path, file_name: str, model_id: str):
        self.calls.append((file_path, file_name, model_id))
        return {
            "merchant": "Rema 1000",
            "date": "2026-06-15T12:00:00Z",
            "amount": 123.45,
            "currency": "NOK",
            "category": "Groceries",
            "notes": "Auto extracted",
            "lineItems": [
                {
                    "originalText": "TINE Lettmelk 1L",
                    "detectedLanguage": "nb",
                    "itemName": "TINE Lettmelk 1L",
                    "normalizedName": "milk",
                    "quantity": 1,
                    "unit": "l",
                    "lineTotal": 22.5,
                    "confidence": 0.91,
                }
            ],
            "confidence": 0.88,
            "warnings": ["review discounts"],
        }


def test_hf_receipt_sidecar_health_uses_default_model(monkeypatch):
    monkeypatch.setenv("HF_RECEIPT_MODEL", "google/gemma-4-E4B-it")
    client = TestClient(create_hf_receipt_app(extractor=FakeReceiptExtractor()))

    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {
        "status": "ok",
        "model": "google/gemma-4-E4B-it",
    }


def test_hf_receipt_sidecar_extracts_with_requested_model(tmp_path):
    extractor = FakeReceiptExtractor()
    client = TestClient(create_hf_receipt_app(extractor=extractor))
    receipt = tmp_path / "receipt.jpg"
    receipt.write_bytes(b"not-a-real-image-but-fake-extractor-does-not-read-it")

    response = client.post(
        "/api/v1/extract-bill",
        json={
            "path": str(receipt),
            "fileName": "receipt.jpg",
            "model": "google/gemma-4-E4B-it",
        },
    )

    assert response.status_code == 200, response.text
    payload = response.json()
    assert payload["merchant"] == "Rema 1000"
    assert payload["currency"] == "NOK"
    assert payload["lineItems"][0]["normalizedName"] == "milk"
    assert extractor.calls == [
        (receipt.resolve(), "receipt.jpg", "google/gemma-4-E4B-it")
    ]


def test_hf_receipt_sidecar_rejects_missing_file():
    client = TestClient(create_hf_receipt_app(extractor=FakeReceiptExtractor()))

    response = client.post(
        "/api/v1/extract-bill",
        json={"path": "/tmp/not-a-real-receipt.jpg", "fileName": "missing.jpg"},
    )

    assert response.status_code == 400
    assert response.json()["error"]["code"] == "INVALID_FILE"


def test_hf_receipt_parser_unwraps_processor_role_content_response():
    class WrappedResponseProcessor:
        def parse_response(self, _decoded: str):
            return {
                "role": "assistant",
                "content": (
                    '{"merchant":"REMA 1000","date":"2026-06-17",'
                    '"amount":52.6,"currency":"NOK","category":"Groceries",'
                    '"notes":"","lineItems":[],"confidence":0.8,"warnings":[]}'
                ),
            }

    parsed = HuggingFaceGemmaReceiptExtractor()._parse_response(
        WrappedResponseProcessor(),
        "ignored",
    )

    assert parsed["merchant"] == "REMA 1000"
    assert parsed["amount"] == 52.6
    assert parsed["currency"] == "NOK"


def test_hf_receipt_parser_tolerates_model_trailing_commas():
    parsed = parse_model_json(
        '{"merchant":"REMA 1000","lineItems":[{"itemName":"Brownie","unitPrice":16.,}],}'
    )

    assert parsed["merchant"] == "REMA 1000"
    assert parsed["lineItems"][0]["itemName"] == "Brownie"
    assert parsed["lineItems"][0]["unitPrice"] == 16.0
