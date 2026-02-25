package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"expense_tracker_backend/internal/auth"
)

func TestRequireAuthMissingHeader(t *testing.T) {
	verifier := auth.NewStaticVerifier(map[string]string{"valid-token": "uid-1"})
	called := false
	next := http.HandlerFunc(func(http.ResponseWriter, *http.Request) { called = true })

	h := RequireAuth(verifier, next)
	req := httptest.NewRequest(http.MethodGet, "/api/v1/expenses", nil)
	rr := httptest.NewRecorder()

	h.ServeHTTP(rr, req)

	if rr.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", rr.Code)
	}
	if called {
		t.Fatalf("next handler should not be called")
	}
}

func TestRequireAuthSuccessInjectsUID(t *testing.T) {
	verifier := auth.NewStaticVerifier(map[string]string{"valid-token": "uid-1"})
	receivedUID := ""
	next := http.HandlerFunc(func(_ http.ResponseWriter, r *http.Request) {
		uid, ok := UserIDFromContext(r.Context())
		if !ok {
			t.Fatalf("uid missing from context")
		}
		receivedUID = uid
	})

	h := RequireAuth(verifier, next)
	req := httptest.NewRequest(http.MethodGet, "/api/v1/expenses", nil)
	req.Header.Set("Authorization", "Bearer valid-token")
	rr := httptest.NewRecorder()

	h.ServeHTTP(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rr.Code)
	}
	if receivedUID != "uid-1" {
		t.Fatalf("expected uid-1, got %q", receivedUID)
	}
}
