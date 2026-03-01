package recurring_test

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"expense_tracker_backend/internal/auth"
	"expense_tracker_backend/internal/expense"
	"expense_tracker_backend/internal/friend"
	"expense_tracker_backend/internal/group"
	"expense_tracker_backend/internal/recurring"
	"expense_tracker_backend/internal/server"
)

func setupRouter() http.Handler {
	verifier := auth.NewStaticVerifier(map[string]string{"test-token": "user-1"})
	expenseHandler := expense.NewHandler(expense.NewService(expense.NewInMemoryRepository()))
	friendHandler := friend.NewHandler(friend.NewInMemoryStore())
	groupHandler := group.NewHandler(group.NewInMemoryStore(), friend.NewInMemoryStore(), nil)
	recurringHandler := recurring.NewHandler(recurring.NewInMemoryStore())
	return server.NewRouter(verifier, expenseHandler, friendHandler, groupHandler, recurringHandler)
}

func TestCreateAndListTemplates(t *testing.T) {
	router := setupRouter()

	payload := map[string]any{
		"title":     "Internet bill",
		"amount":    499.0,
		"category":  "Utilities",
		"frequency": "monthly",
		"startDate": "2026-03-01T00:00:00Z",
	}
	raw, _ := json.Marshal(payload)
	createReq := httptest.NewRequest(http.MethodPost, "/api/v1/recurring/templates", bytes.NewReader(raw))
	createReq.Header.Set("Authorization", "Bearer test-token")
	createReq.Header.Set("Content-Type", "application/json")
	createRR := httptest.NewRecorder()
	router.ServeHTTP(createRR, createReq)
	if createRR.Code != http.StatusCreated {
		t.Fatalf("expected 201 got %d body=%s", createRR.Code, createRR.Body.String())
	}

	listReq := httptest.NewRequest(http.MethodGet, "/api/v1/recurring/templates", nil)
	listReq.Header.Set("Authorization", "Bearer test-token")
	listRR := httptest.NewRecorder()
	router.ServeHTTP(listRR, listReq)
	if listRR.Code != http.StatusOK {
		t.Fatalf("expected 200 got %d body=%s", listRR.Code, listRR.Body.String())
	}

	var response map[string]any
	_ = json.Unmarshal(listRR.Body.Bytes(), &response)
	templates, ok := response["templates"].([]any)
	if !ok || len(templates) != 1 {
		t.Fatalf("expected one template got %#v", response["templates"])
	}
}
