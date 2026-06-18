# AI Prompts

Prompt files used by backend AI providers live here so they can be edited and tested without searching through Python code.

- `receipt_extraction_system.md`: system prompt for receipt/bill image extraction.
- `receipt_extraction_user.md`: user prompt and JSON schema contract for receipt/bill extraction.
- `openrouter_models.json`: ordered OpenRouter model fallbacks used by hosted AI providers.
- `receipt_review_memory_system.md`: JSON-only prompt for generating user-specific memory candidates from final receipt reviews.
- `receipt_store_quirks.json`: merchant/store-specific receipt cleanup rules gathered from user feedback.
- `structured_json_system.md`: reusable system prompt for structured finance AI responses.
