package friend_test

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"expense_tracker_backend/internal/auth"
	"expense_tracker_backend/internal/expense"
	"expense_tracker_backend/internal/friend"
	"expense_tracker_backend/internal/server"
)

type fakeStore struct {
	resolve friend.ResolveResult
	friends []friend.Friend
}

func (f *fakeStore) ResolveByEmailOrPhone(_ context.Context, _ string) (friend.ResolveResult, error) {
	return f.resolve, nil
}

func (f *fakeStore) AddFriendship(_ context.Context, _, _ string) error {
	return nil
}

func (f *fakeStore) ListFriends(_ context.Context, _ string) ([]friend.Friend, error) {
	return f.friends, nil
}

func setupTestServer(store friend.Store) http.Handler {
	expenseRepo := expense.NewInMemoryRepository()
	expenseSvc := expense.NewService(expenseRepo)
	expenseHandler := expense.NewHandler(expenseSvc)

	friendHandler := friend.NewHandler(store)
	verifier := auth.NewStaticVerifier(map[string]string{"dev-token": "uid-1"})
	return server.NewRouter(verifier, expenseHandler, friendHandler)
}

func TestResolveFound(t *testing.T) {
	router := setupTestServer(&fakeStore{
		resolve: friend.ResolveResult{Exists: true, UID: "uid-2"},
	})

	body := []byte(`{"emailOrPhone":"friend@example.com"}`)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/friends/resolve", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer dev-token")
	rr := httptest.NewRecorder()
	router.ServeHTTP(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("expected 200 got %d body=%s", rr.Code, rr.Body.String())
	}
}

func TestAddFriendNotFound(t *testing.T) {
	router := setupTestServer(&fakeStore{
		resolve: friend.ResolveResult{Exists: false},
	})

	body := []byte(`{"emailOrPhone":"missing@example.com"}`)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/friends/add", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer dev-token")
	rr := httptest.NewRecorder()
	router.ServeHTTP(rr, req)

	if rr.Code != http.StatusNotFound {
		t.Fatalf("expected 404 got %d body=%s", rr.Code, rr.Body.String())
	}
}

func TestListFriends(t *testing.T) {
	router := setupTestServer(&fakeStore{
		friends: []friend.Friend{
			{UID: "uid-2", DisplayName: "Friend Two", Email: "friend2@example.com"},
		},
	})

	req := httptest.NewRequest(http.MethodGet, "/api/v1/friends", nil)
	req.Header.Set("Authorization", "Bearer dev-token")
	rr := httptest.NewRecorder()
	router.ServeHTTP(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("expected 200 got %d body=%s", rr.Code, rr.Body.String())
	}

	var payload map[string]any
	if err := json.Unmarshal(rr.Body.Bytes(), &payload); err != nil {
		t.Fatalf("decode failed: %v", err)
	}
	rawFriends, ok := payload["friends"].([]any)
	if !ok || len(rawFriends) != 1 {
		t.Fatalf("expected one friend entry, got %#v", payload["friends"])
	}
}
