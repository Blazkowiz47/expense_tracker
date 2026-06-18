from __future__ import annotations

from pathlib import Path


PROMPTS_DIR = Path(__file__).resolve().parent / "prompts"


def load_prompt(name: str) -> str:
    if "/" in name or "\\" in name:
        raise ValueError("prompt name must be a file name, not a path")
    path = PROMPTS_DIR / name
    return path.read_text(encoding="utf-8").strip()
