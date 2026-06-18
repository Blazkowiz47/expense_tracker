import pytest

from app.ai_prompts import load_prompt
from app.hf_receipt_server import SYSTEM_PROMPT, USER_PROMPT


def test_load_prompt_reads_prompt_file():
    prompt = load_prompt("receipt_extraction_system.md")

    assert "Return exactly one valid JSON object and nothing else." in prompt


def test_load_prompt_rejects_paths():
    with pytest.raises(ValueError):
        load_prompt("../receipt_extraction_system.md")

    with pytest.raises(ValueError):
        load_prompt("nested/receipt_extraction_system.md")


def test_receipt_prompt_contract_is_json_only():
    system_prompt = load_prompt("receipt_extraction_system.md").lower()
    user_prompt = load_prompt("receipt_extraction_user.md").lower()
    combined = f"{system_prompt}\n{user_prompt}"

    assert "return exactly one valid json object and nothing else" in combined
    assert "no greeting" in combined or "do not include greetings" in combined
    assert "no markdown" in combined or "do not include" in combined and "markdown" in combined
    assert "no code fence" in combined or "code fences" in combined
    assert "prose outside json" in combined


def test_receipt_prompt_declares_required_schema_keys():
    prompt = load_prompt("receipt_extraction_user.md")

    for key in [
        "merchant",
        "date",
        "amount",
        "currency",
        "category",
        "notes",
        "lineItems",
        "confidence",
        "warnings",
    ]:
        assert f'"{key}"' in prompt

    for key in [
        "originalText",
        "detectedLanguage",
        "itemName",
        "normalizedName",
        "brand",
        "quantity",
        "unit",
        "unitPrice",
        "lineTotal",
        "discount",
        "category",
        "confidence",
    ]:
        assert f'"{key}"' in prompt


def test_structured_json_prompt_has_shared_contract_placeholders():
    prompt = load_prompt("structured_json_system.md")

    assert "{schema_version}" in prompt
    assert "{instructions}" in prompt
    assert "Return exactly one valid JSON object and nothing else." in prompt


def test_hf_sidecar_uses_shared_receipt_prompts():
    assert SYSTEM_PROMPT == load_prompt("receipt_extraction_system.md")
    assert USER_PROMPT == load_prompt("receipt_extraction_user.md")
