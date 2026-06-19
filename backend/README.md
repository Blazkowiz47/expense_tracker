# Expense Tracker Backend

FastAPI backend for local-first expense tracking.

## Run

```sh
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements-dev.txt
uvicorn app.main:app --host 127.0.0.1 --port 8080 --reload
```

The server expects MongoDB at `MONGO_URI` and defaults to
`mongodb://127.0.0.1:27017`. Runtime data is stored in `expense_tracker_local`
unless `MONGO_DB` is set.

From the repository root, the tmux dev script uses backend port `8080` and
frontend port `7357` by default. Override `BACKEND_PORT` / `FRONTEND_PORT`
when those ports are busy:

```sh
BACKEND_PORT=8081 FRONTEND_PORT=7358 scripts/start_expense_dev_tmux.sh --no-attach
```

Uploaded files are stored under `DATA_DIR/uploads` and default to
`backend/data/uploads`.

## Exchange Rates

Group expenses can store purchase-time conversion snapshots. The backend owns
FX lookups so clients never need provider keys. By default it calls
Frankfurter's no-key rates API:

```sh
FX_BASE_URL=https://api.frankfurter.dev/v2
FX_TIMEOUT_SECONDS=10
```

Each converted group expense stores the original `amount`/`currency`, converted
amounts, exchange rates, provider, and rate timestamps. Historical expenses use
the saved purchase/addition-time rate instead of being recalculated later.

## AI

Bill extraction is backend-only. Set `AI_BASE_URL` to a local Gemma-compatible
HTTP endpoint if one is available. Without it, extraction falls back to a
deterministic placeholder so upload/review flows continue to work.

### Gemma 4 E4B via Hugging Face Transformers

The recommended local Hugging Face path is the optional receipt AI sidecar in
`app.hf_receipt_server`. It runs Google's `google/gemma-4-E4B-it` with
Transformers and exposes the `/api/v1/extract-bill` endpoint expected by the
main backend.

Install the optional AI dependencies into the backend virtualenv:

```sh
cd backend
. .venv/bin/activate
pip install -r requirements-ai.txt
```

If Hugging Face asks for model access, accept the Gemma terms on the model page
and log in locally with your Hugging Face token before starting the sidecar.
Do not commit the token.

From the repository root, start the sidecar on port `8001`:

```sh
HF_RECEIPT_MODEL=google/gemma-4-E4B-it \
scripts/start_hf_gemma_receipts.sh
```

Then start the app pointed at that sidecar, also from the repository root:

```sh
AI_BASE_URL=http://127.0.0.1:8001 \
AI_MODEL=google/gemma-4-E4B-it \
scripts/start_expense_dev_tmux.sh --no-attach
```

Or let the tmux script start the AI sidecar as window `:3`:

```sh
START_HF_AI=1 \
HF_RECEIPT_MODEL=google/gemma-4-E4B-it \
scripts/start_expense_dev_tmux.sh --no-attach
```

The first request downloads/loads the model and can be slow. The sidecar keeps
the model warm after that.

Useful optional knobs:

```sh
HF_DEVICE=mps                 # force Apple Silicon GPU when supported
HF_DEVICE=cuda                # force CUDA
HF_TORCH_DTYPE=bfloat16       # or float16/float32/auto
HF_RECEIPT_MAX_NEW_TOKENS=1536
```

### Hosted AI via Gemini and OpenRouter

The default hosted AI provider is Gemini, with OpenRouter behind it as a
fallback when Gemini is capped, slow, or temporarily unavailable. Configure one
or both API keys in env. Model order lives beside the prompts in
`app/prompts/gemini_models.json` and `app/prompts/openrouter_models.json` so
receipt/planning model choices are code-reviewed and easy to edit. The backend
tries models in order when a model is at capacity or unavailable. All model
calls use `temperature=0` for predictable JSON extraction and planning
responses. Dashboard AI summaries are cached once per user/day/month/currency so
normal home loads preserve hosted AI quota for receipt extraction.

```sh
AI_PROVIDER=gemini
GEMINI_API_KEY=...
OPENROUTER_API_KEY=...
```

### Gemma 4 E4B via llama-server

The backend can call a local OpenAI-compatible `llama-server` directly:

```sh
AI_PROVIDER=llama-server
AI_BASE_URL=http://127.0.0.1:8001
AI_MODEL=unsloth/gemma-4-E4B-it-GGUF
```

For the 16-bit E4B setup, download the 16-bit model and multimodal projector:

```sh
mkdir -p models
hf download unsloth/gemma-4-E4B-it-GGUF \
  --local-dir models/gemma-4-E4B-it-GGUF \
  --include "gemma-4-E4B-it-BF16.gguf" \
  --include "mmproj-F16.gguf"
```

Then run `llama-server` on port `8001`:

```sh
llama-server \
  --model models/gemma-4-E4B-it-GGUF/gemma-4-E4B-it-BF16.gguf \
  --mmproj models/gemma-4-E4B-it-GGUF/mmproj-F16.gguf \
  --host 127.0.0.1 \
  --port 8001 \
  --alias unsloth/gemma-4-E4B-it-GGUF \
  --ctx-size 32768 \
  --chat-template-kwargs '{"enable_thinking":false}'
```

Start the app with those AI variables exported before running
`scripts/start_expense_dev_tmux.sh --no-attach`.
