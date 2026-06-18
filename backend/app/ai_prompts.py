from __future__ import annotations

import json
from pathlib import Path
from typing import Any


PROMPTS_DIR = Path(__file__).resolve().parent / "prompts"


def load_prompt(name: str) -> str:
    if "/" in name or "\\" in name:
        raise ValueError("prompt name must be a file name, not a path")
    path = PROMPTS_DIR / name
    return path.read_text(encoding="utf-8").strip()


def load_prompt_json(name: str) -> dict[str, Any]:
    if "/" in name or "\\" in name:
        raise ValueError("prompt JSON name must be a file name, not a path")
    path = PROMPTS_DIR / name
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("prompt JSON must be an object")
    return data
