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

Uploaded files are stored under `DATA_DIR/uploads` and default to
`backend/data/uploads`.

## AI

Bill extraction is backend-only. Set `AI_BASE_URL` to a local Gemma-compatible
HTTP endpoint if one is available. Without it, extraction falls back to a
deterministic placeholder so upload/review flows continue to work.

