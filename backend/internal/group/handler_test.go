package group

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"expense_tracker_backend/internal/auth"
	"expense_tracker_backend/internal/friend"
	"expense_tracker_backend/internal/middleware"
)

func setupTestServer(friendStore friend.Store) http.Handler {
	verifier := auth.NewStaticVerifier(map[string]string{"test-token": "user-1"})
	groupHandler := NewHandler(NewInMemoryStore(), friendStore)
	return middleware.RequireAuth(verifier, http.HandlerFunc(groupHandler.GroupsCollection))
}

func TestCreateGroupUnauthorized(t *testing.T) {
	router := setupTestServer(&fakeFriendStore{})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/groups", bytes.NewBufferString(`{"name":"Trip"}`))
	rr := httptest.NewRecorder()

	router.ServeHTTP(rr, req)
	if rr.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", rr.Code)
	}
}

func TestCreateAndListGroup(t *testing.T) {
	store := &fakeFriendStore{
		resolvedByContact: map[string]friend.ResolveResult{
			"user2@example.com": {Exists: true, UID: "user-2"},
		},
	}
	router := setupTestServer(store)
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

func TestCreateGroupWithMembersAddsFriendships(t *testing.T) {
	store := &fakeFriendStore{
		resolvedByContact: map[string]friend.ResolveResult{
			"user2@example.com": {Exists: true, UID: "user-2"},
			"+15551234567":      {Exists: true, UID: "user-3"},
		},
	}
	router := setupTestServer(store)
	payload := map[string]any{
		"name":      "Trip",
		"groupType": "split",
		"members":   []string{"user2@example.com", "+15551234567"},
	}
	b, _ := json.Marshal(payload)

	createReq := httptest.NewRequest(http.MethodPost, "/api/v1/groups", bytes.NewReader(b))
	createReq.Header.Set("Authorization", "Bearer test-token")
	createReq.Header.Set("Content-Type", "application/json")
	createRR := httptest.NewRecorder()
	router.ServeHTTP(createRR, createReq)
	if createRR.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d body=%s", createRR.Code, createRR.Body.String())
	}

	if len(store.addedPairs) != 2 {
		t.Fatalf("expected 2 friendship additions, got %d", len(store.addedPairs))
	}

	var created map[string]any
	if err := json.Unmarshal(createRR.Body.Bytes(), &created); err != nil {
		t.Fatalf("decode create response: %v", err)
	}
	memberCount, ok := created["memberCount"].(float64)
	if !ok || int(memberCount) != 3 {
		t.Fatalf("expected memberCount 3, got %#v", created["memberCount"])
	}
}

func TestCreateGroupWithUnknownMemberFails(t *testing.T) {
	store := &fakeFriendStore{
		resolvedByContact: map[string]friend.ResolveResult{},
	}
	router := setupTestServer(store)
	payload := map[string]any{
		"name":      "Trip",
		"groupType": "split",
		"members":   []string{"missing@example.com"},
	}
	b, _ := json.Marshal(payload)

	createReq := httptest.NewRequest(http.MethodPost, "/api/v1/groups", bytes.NewReader(b))
	createReq.Header.Set("Authorization", "Bearer test-token")
	createReq.Header.Set("Content-Type", "application/json")
	createRR := httptest.NewRecorder()
	router.ServeHTTP(createRR, createReq)
	if createRR.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d body=%s", createRR.Code, createRR.Body.String())
	}
}

type fakeFriendStore struct {
	resolvedByContact map[string]friend.ResolveResult
	addedPairs        [][2]string
}

func (f *fakeFriendStore) ResolveByEmailOrPhone(_ context.Context, query string) (friend.ResolveResult, error) {
	if resolved, ok := f.resolvedByContact[query]; ok {
		return resolved, nil
	}
	return friend.ResolveResult{Exists: false}, nil
}

func (f *fakeFriendStore) AddFriendship(_ context.Context, uid, friendUID string) error {
	f.addedPairs = append(f.addedPairs, [2]string{uid, friendUID})
	return nil
}

func (f *fakeFriendStore) RemoveFriendship(_ context.Context, uid, friendUID string) error {
	return nil
}

func (f *fakeFriendStore) ListFriends(_ context.Context, uid string) ([]friend.Friend, error) {
	return nil, nil
}
