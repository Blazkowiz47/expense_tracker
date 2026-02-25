package expense_test

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"expense_tracker_backend/internal/auth"
	"expense_tracker_backend/internal/expense"
	"expense_tracker_backend/internal/server"
)

func setupTestServer() http.Handler {
	repo := expense.NewInMemoryRepository()
	svc := expense.NewService(repo)
	h := expense.NewHandler(svc)
	verifier := auth.NewStaticVerifier(map[string]string{"dev-token": "uid-1"})
	return server.NewRouter(verifier, h)
}

func TestCreateExpenseUnauthorized(t *testing.T) {
	router := setupTestServer()

	body := map[string]any{
		"amount":      10,
		"category":    "Food",
		"description": "Lunch",
		"date":        time.Now().UTC().Format(time.RFC3339),
	}
	b, _ := json.Marshal(body)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/expenses", bytes.NewReader(b))
	rr := httptest.NewRecorder()

	router.ServeHTTP(rr, req)

	if rr.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", rr.Code)
	}
}

func TestCreateAndListExpenseFlow(t *testing.T) {
	router := setupTestServer()

	createPayload := map[string]any{
		"amount":      99.5,
		"category":    "Groceries",
		"description": "weekly",
		"date":        "2026-02-01T10:00:00Z",
	}
	createBody, _ := json.Marshal(createPayload)
	createReq := httptest.NewRequest(http.MethodPost, "/api/v1/expenses", bytes.NewReader(createBody))
	createReq.Header.Set("Authorization", "Bearer dev-token")
	createRR := httptest.NewRecorder()

	router.ServeHTTP(createRR, createReq)
	if createRR.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d. body=%s", createRR.Code, createRR.Body.String())
	}

	listReq := httptest.NewRequest(http.MethodGet, "/api/v1/expenses?page=1&limit=10", nil)
	listReq.Header.Set("Authorization", "Bearer dev-token")
	listRR := httptest.NewRecorder()

	router.ServeHTTP(listRR, listReq)
	if listRR.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d. body=%s", listRR.Code, listRR.Body.String())
	}

	var payload map[string]any
	if err := json.Unmarshal(listRR.Body.Bytes(), &payload); err != nil {
		t.Fatalf("failed to decode list response: %v", err)
	}
	expenses, ok := payload["expenses"].([]any)
	if !ok {
		t.Fatalf("expenses should be an array, got %T", payload["expenses"])
	}
	if len(expenses) != 1 {
		t.Fatalf("expected 1 expense, got %d", len(expenses))
	}
}

func TestDashboardSnapshotFlow(t *testing.T) {
	router := setupTestServer()

	createPayload := map[string]any{
		"amount":      120.0,
		"category":    "Groceries",
		"description": "Weekly grocery",
		"date":        "2026-02-01T10:00:00Z",
	}
	createBody, _ := json.Marshal(createPayload)
	createReq := httptest.NewRequest(http.MethodPost, "/api/v1/expenses", bytes.NewReader(createBody))
	createReq.Header.Set("Authorization", "Bearer dev-token")
	createRR := httptest.NewRecorder()
	router.ServeHTTP(createRR, createReq)
	if createRR.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d", createRR.Code)
	}

	req := httptest.NewRequest(http.MethodGet, "/api/v1/dashboard/snapshot", nil)
	req.Header.Set("Authorization", "Bearer dev-token")
	rr := httptest.NewRecorder()
	router.ServeHTTP(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d. body=%s", rr.Code, rr.Body.String())
	}

	var payload map[string]any
	if err := json.Unmarshal(rr.Body.Bytes(), &payload); err != nil {
		t.Fatalf("failed to decode snapshot response: %v", err)
	}

	if payload["overallLabel"] == "" {
		t.Fatalf("expected overallLabel to be present")
	}
	if _, ok := payload["groupItems"].([]any); !ok {
		t.Fatalf("expected groupItems array, got %T", payload["groupItems"])
	}
	if _, ok := payload["activityItems"].([]any); !ok {
		t.Fatalf("expected activityItems array, got %T", payload["activityItems"])
	}
}

func TestThemePacksEndpoint(t *testing.T) {
	router := setupTestServer()

	req := httptest.NewRequest(http.MethodGet, "/api/v1/theme-packs", nil)
	rr := httptest.NewRecorder()
	router.ServeHTTP(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rr.Code)
	}

	var payload []map[string]any
	if err := json.Unmarshal(rr.Body.Bytes(), &payload); err != nil {
		t.Fatalf("failed to decode theme packs response: %v", err)
	}
	if len(payload) == 0 {
		t.Fatalf("expected non-empty theme packs")
	}
}
