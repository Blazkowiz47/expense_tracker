package group

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"expense_tracker_backend/internal/auth"
	"expense_tracker_backend/internal/middleware"
)

func setupTestServer() http.Handler {
	verifier := auth.NewStaticVerifier(map[string]string{"test-token": "user-1"})
	groupHandler := NewHandler(NewInMemoryStore())
	return middleware.RequireAuth(verifier, http.HandlerFunc(groupHandler.GroupsCollection))
}

func TestCreateGroupUnauthorized(t *testing.T) {
	router := setupTestServer()
	req := httptest.NewRequest(http.MethodPost, "/api/v1/groups", bytes.NewBufferString(`{"name":"Trip"}`))
	rr := httptest.NewRecorder()

	router.ServeHTTP(rr, req)
	if rr.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", rr.Code)
	}
}

func TestCreateAndListGroup(t *testing.T) {
	router := setupTestServer()
	payload := map[string]any{"name": "Home", "groupType": "family"}
	b, _ := json.Marshal(payload)

	createReq := httptest.NewRequest(http.MethodPost, "/api/v1/groups", bytes.NewReader(b))
	createReq.Header.Set("Authorization", "Bearer test-token")
	createReq.Header.Set("Content-Type", "application/json")
	createRR := httptest.NewRecorder()
	router.ServeHTTP(createRR, createReq)
	if createRR.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d body=%s", createRR.Code, createRR.Body.String())
	}

	listReq := httptest.NewRequest(http.MethodGet, "/api/v1/groups", nil)
	listReq.Header.Set("Authorization", "Bearer test-token")
	listRR := httptest.NewRecorder()
	router.ServeHTTP(listRR, listReq)
	if listRR.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", listRR.Code, listRR.Body.String())
	}

	var resp map[string]any
	if err := json.Unmarshal(listRR.Body.Bytes(), &resp); err != nil {
		t.Fatalf("failed to decode list response: %v", err)
	}
	groups, ok := resp["groups"].([]any)
	if !ok || len(groups) != 1 {
		t.Fatalf("expected one group in response, got %#v", resp["groups"])
	}
}
