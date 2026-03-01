package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestCORSAllowsAnyOriginInDevByDefault(t *testing.T) {
	t.Setenv("APP_ENV", "development")
	t.Setenv("CORS_ALLOWED_ORIGINS", "")
	handler := CORS(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))

	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	req.Header.Set("Origin", "http://127.0.0.1:7357")
	rr := httptest.NewRecorder()
	handler.ServeHTTP(rr, req)

	if got := rr.Header().Get("Access-Control-Allow-Origin"); got != "*" {
		t.Fatalf("expected wildcard CORS in dev, got %q", got)
	}
}

func TestCORSRestrictsOriginInProduction(t *testing.T) {
	t.Setenv("APP_ENV", "production")
	t.Setenv("CORS_ALLOWED_ORIGINS", "https://app.example.com")
	handler := CORS(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))

	req := httptest.NewRequest(http.MethodOptions, "/api/v1/expenses", nil)
	req.Header.Set("Origin", "https://evil.example.com")
	rr := httptest.NewRecorder()
	handler.ServeHTTP(rr, req)
	if rr.Code != http.StatusForbidden {
		t.Fatalf("expected 403 for disallowed preflight origin, got %d", rr.Code)
	}

	allowedReq := httptest.NewRequest(http.MethodGet, "/api/v1/expenses", nil)
	allowedReq.Header.Set("Origin", "https://app.example.com")
	allowedRR := httptest.NewRecorder()
	handler.ServeHTTP(allowedRR, allowedReq)
	if got := allowedRR.Header().Get("Access-Control-Allow-Origin"); got != "https://app.example.com" {
		t.Fatalf("expected allow origin header for whitelisted origin, got %q", got)
	}
}
