package group

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"net/textproto"
	"net/url"
	"testing"

	"expense_tracker_backend/internal/auth"
	"expense_tracker_backend/internal/friend"
	"expense_tracker_backend/internal/middleware"
)

func setupTestServer(friendStore friend.Store) http.Handler {
	verifier := auth.NewStaticVerifier(map[string]string{"test-token": "user-1"})
	groupHandler := NewHandler(NewInMemoryStore(), friendStore, &fakeAttachmentUploader{})
	mux := http.NewServeMux()
	mux.Handle("/api/v1/groups", middleware.RequireAuth(verifier, http.HandlerFunc(groupHandler.GroupsCollection)))
	mux.Handle("/api/v1/groups/", middleware.RequireAuth(verifier, http.HandlerFunc(groupHandler.GroupByID)))
	return mux
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

func TestLeaveGroupDeletesWhenLastMember(t *testing.T) {
	store := &fakeFriendStore{}
	router := setupTestServer(store)

	createPayload := map[string]any{"name": "Solo", "groupType": "split"}
	b, _ := json.Marshal(createPayload)
	createReq := httptest.NewRequest(http.MethodPost, "/api/v1/groups", bytes.NewReader(b))
	createReq.Header.Set("Authorization", "Bearer test-token")
	createReq.Header.Set("Content-Type", "application/json")
	createRR := httptest.NewRecorder()
	router.ServeHTTP(createRR, createReq)
	if createRR.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d body=%s", createRR.Code, createRR.Body.String())
	}

	var created map[string]any
	_ = json.Unmarshal(createRR.Body.Bytes(), &created)
	groupID, _ := created["id"].(string)

	leaveReq := httptest.NewRequest(http.MethodPost, "/api/v1/groups/"+groupID+"/leave", nil)
	leaveReq.Header.Set("Authorization", "Bearer test-token")
	leaveRR := httptest.NewRecorder()
	router.ServeHTTP(leaveRR, leaveReq)
	if leaveRR.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", leaveRR.Code, leaveRR.Body.String())
	}

	listReq := httptest.NewRequest(http.MethodGet, "/api/v1/groups", nil)
	listReq.Header.Set("Authorization", "Bearer test-token")
	listRR := httptest.NewRecorder()
	router.ServeHTTP(listRR, listReq)
	var listPayload map[string]any
	_ = json.Unmarshal(listRR.Body.Bytes(), &listPayload)
	groups, _ := listPayload["groups"].([]any)
	if len(groups) != 0 {
		t.Fatalf("expected group list to be empty after leave-delete, got %d", len(groups))
	}
}

func TestAddMemberEndpoint(t *testing.T) {
	store := &fakeFriendStore{
		resolvedByContact: map[string]friend.ResolveResult{
			"user2@example.com": {Exists: true, UID: "user-2"},
		},
	}
	router := setupTestServer(store)

	createPayload := map[string]any{"name": "Team", "groupType": "split"}
	b, _ := json.Marshal(createPayload)
	createReq := httptest.NewRequest(http.MethodPost, "/api/v1/groups", bytes.NewReader(b))
	createReq.Header.Set("Authorization", "Bearer test-token")
	createReq.Header.Set("Content-Type", "application/json")
	createRR := httptest.NewRecorder()
	router.ServeHTTP(createRR, createReq)
	if createRR.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d body=%s", createRR.Code, createRR.Body.String())
	}
	var created map[string]any
	_ = json.Unmarshal(createRR.Body.Bytes(), &created)
	groupID, _ := created["id"].(string)

	addPayload := []byte(`{"emailOrPhone":"user2@example.com"}`)
	addReq := httptest.NewRequest(http.MethodPost, "/api/v1/groups/"+groupID+"/members/add", bytes.NewReader(addPayload))
	addReq.Header.Set("Authorization", "Bearer test-token")
	addReq.Header.Set("Content-Type", "application/json")
	addRR := httptest.NewRecorder()
	router.ServeHTTP(addRR, addReq)
	if addRR.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", addRR.Code, addRR.Body.String())
	}
}

func TestCreateAndListGroupExpenses(t *testing.T) {
	router := setupTestServer(&fakeFriendStore{})
	createPayload := map[string]any{"name": "Trip", "groupType": "split"}
	b, _ := json.Marshal(createPayload)
	createReq := httptest.NewRequest(http.MethodPost, "/api/v1/groups", bytes.NewReader(b))
	createReq.Header.Set("Authorization", "Bearer test-token")
	createReq.Header.Set("Content-Type", "application/json")
	createRR := httptest.NewRecorder()
	router.ServeHTTP(createRR, createReq)
	if createRR.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d body=%s", createRR.Code, createRR.Body.String())
	}
	var created map[string]any
	_ = json.Unmarshal(createRR.Body.Bytes(), &created)
	groupID, _ := created["id"].(string)

	expensePayload := []byte(`{"amount":1200.5,"description":"Groceries","paidBy":"user-1","splitMode":"equally","splitWith":["user-1"],"date":"2026-02-27T10:00:00Z"}`)
	createExpenseReq := httptest.NewRequest(http.MethodPost, "/api/v1/groups/"+groupID+"/expenses", bytes.NewReader(expensePayload))
	createExpenseReq.Header.Set("Authorization", "Bearer test-token")
	createExpenseReq.Header.Set("Content-Type", "application/json")
	createExpenseRR := httptest.NewRecorder()
	router.ServeHTTP(createExpenseRR, createExpenseReq)
	if createExpenseRR.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d body=%s", createExpenseRR.Code, createExpenseRR.Body.String())
	}

	listReq := httptest.NewRequest(http.MethodGet, "/api/v1/groups/"+groupID+"/expenses", nil)
	listReq.Header.Set("Authorization", "Bearer test-token")
	listRR := httptest.NewRecorder()
	router.ServeHTTP(listRR, listReq)
	if listRR.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", listRR.Code, listRR.Body.String())
	}
}

func TestUpdateGroupExpense(t *testing.T) {
	router := setupTestServer(&fakeFriendStore{})
	createPayload := map[string]any{"name": "Trip", "groupType": "split"}
	b, _ := json.Marshal(createPayload)
	createReq := httptest.NewRequest(http.MethodPost, "/api/v1/groups", bytes.NewReader(b))
	createReq.Header.Set("Authorization", "Bearer test-token")
	createReq.Header.Set("Content-Type", "application/json")
	createRR := httptest.NewRecorder()
	router.ServeHTTP(createRR, createReq)
	if createRR.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d body=%s", createRR.Code, createRR.Body.String())
	}
	var created map[string]any
	_ = json.Unmarshal(createRR.Body.Bytes(), &created)
	groupID, _ := created["id"].(string)

	expensePayload := []byte(`{"amount":1200.5,"description":"Groceries","date":"2026-02-27T10:00:00Z"}`)
	createExpenseReq := httptest.NewRequest(http.MethodPost, "/api/v1/groups/"+groupID+"/expenses", bytes.NewReader(expensePayload))
	createExpenseReq.Header.Set("Authorization", "Bearer test-token")
	createExpenseReq.Header.Set("Content-Type", "application/json")
	createExpenseRR := httptest.NewRecorder()
	router.ServeHTTP(createExpenseRR, createExpenseReq)
	if createExpenseRR.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d body=%s", createExpenseRR.Code, createExpenseRR.Body.String())
	}
	var createdExpense map[string]any
	_ = json.Unmarshal(createExpenseRR.Body.Bytes(), &createdExpense)
	expenseID, _ := createdExpense["id"].(string)

	updatePayload := []byte(`{"amount":999.0,"description":"Groceries updated","paidBy":"user-2","splitMode":"exact","splitWith":["user-1","user-2"],"date":"2026-02-28T10:00:00Z"}`)
	updateReq := httptest.NewRequest(http.MethodPut, "/api/v1/groups/"+groupID+"/expenses/"+expenseID, bytes.NewReader(updatePayload))
	updateReq.Header.Set("Authorization", "Bearer test-token")
	updateReq.Header.Set("Content-Type", "application/json")
	updateRR := httptest.NewRecorder()
	router.ServeHTTP(updateRR, updateReq)
	if updateRR.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", updateRR.Code, updateRR.Body.String())
	}
	var updated map[string]any
	_ = json.Unmarshal(updateRR.Body.Bytes(), &updated)
	if updated["paidBy"] != "user-2" {
		t.Fatalf("expected paidBy=user-2 got %#v", updated["paidBy"])
	}
	if updated["splitMode"] != "exact" {
		t.Fatalf("expected splitMode=exact got %#v", updated["splitMode"])
	}
	if _, ok := updated["updatedAt"].(string); !ok {
		t.Fatalf("expected updatedAt string got %#v", updated["updatedAt"])
	}
	if updated["updatedBy"] != "user-1" {
		t.Fatalf("expected updatedBy=user-1 got %#v", updated["updatedBy"])
	}
}

func TestDeleteGroupExpense(t *testing.T) {
	router := setupTestServer(&fakeFriendStore{})
	createPayload := map[string]any{"name": "Trip", "groupType": "split"}
	b, _ := json.Marshal(createPayload)
	createReq := httptest.NewRequest(http.MethodPost, "/api/v1/groups", bytes.NewReader(b))
	createReq.Header.Set("Authorization", "Bearer test-token")
	createReq.Header.Set("Content-Type", "application/json")
	createRR := httptest.NewRecorder()
	router.ServeHTTP(createRR, createReq)
	if createRR.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d body=%s", createRR.Code, createRR.Body.String())
	}
	var created map[string]any
	_ = json.Unmarshal(createRR.Body.Bytes(), &created)
	groupID, _ := created["id"].(string)

	expensePayload := []byte(`{"amount":1200.5,"description":"Groceries","date":"2026-02-27T10:00:00Z"}`)
	createExpenseReq := httptest.NewRequest(http.MethodPost, "/api/v1/groups/"+groupID+"/expenses", bytes.NewReader(expensePayload))
	createExpenseReq.Header.Set("Authorization", "Bearer test-token")
	createExpenseReq.Header.Set("Content-Type", "application/json")
	createExpenseRR := httptest.NewRecorder()
	router.ServeHTTP(createExpenseRR, createExpenseReq)
	if createExpenseRR.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d body=%s", createExpenseRR.Code, createExpenseRR.Body.String())
	}
	var createdExpense map[string]any
	_ = json.Unmarshal(createExpenseRR.Body.Bytes(), &createdExpense)
	expenseID, _ := createdExpense["id"].(string)

	deleteReq := httptest.NewRequest(http.MethodDelete, "/api/v1/groups/"+groupID+"/expenses/"+expenseID, nil)
	deleteReq.Header.Set("Authorization", "Bearer test-token")
	deleteRR := httptest.NewRecorder()
	router.ServeHTTP(deleteRR, deleteReq)
	if deleteRR.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d body=%s", deleteRR.Code, deleteRR.Body.String())
	}

	listReq := httptest.NewRequest(http.MethodGet, "/api/v1/groups/"+groupID+"/expenses", nil)
	listReq.Header.Set("Authorization", "Bearer test-token")
	listRR := httptest.NewRecorder()
	router.ServeHTTP(listRR, listReq)
	if listRR.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", listRR.Code, listRR.Body.String())
	}
	var listed map[string]any
	_ = json.Unmarshal(listRR.Body.Bytes(), &listed)
	expenses, _ := listed["expenses"].([]any)
	if len(expenses) != 0 {
		t.Fatalf("expected 0 expenses, got %d", len(expenses))
	}
}

func TestUploadGroupAttachment(t *testing.T) {
	router := setupTestServer(&fakeFriendStore{})
	createPayload := map[string]any{"name": "Trip", "groupType": "split"}
	b, _ := json.Marshal(createPayload)
	createReq := httptest.NewRequest(http.MethodPost, "/api/v1/groups", bytes.NewReader(b))
	createReq.Header.Set("Authorization", "Bearer test-token")
	createReq.Header.Set("Content-Type", "application/json")
	createRR := httptest.NewRecorder()
	router.ServeHTTP(createRR, createReq)
	if createRR.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d body=%s", createRR.Code, createRR.Body.String())
	}
	var created map[string]any
	_ = json.Unmarshal(createRR.Body.Bytes(), &created)
	groupID, _ := created["id"].(string)

	expensePayload := []byte(`{"amount":1200.5,"description":"Groceries","date":"2026-02-27T10:00:00Z"}`)
	createExpenseReq := httptest.NewRequest(http.MethodPost, "/api/v1/groups/"+groupID+"/expenses", bytes.NewReader(expensePayload))
	createExpenseReq.Header.Set("Authorization", "Bearer test-token")
	createExpenseReq.Header.Set("Content-Type", "application/json")
	createExpenseRR := httptest.NewRecorder()
	router.ServeHTTP(createExpenseRR, createExpenseReq)
	if createExpenseRR.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d body=%s", createExpenseRR.Code, createExpenseRR.Body.String())
	}
	var createdExpense map[string]any
	_ = json.Unmarshal(createExpenseRR.Body.Bytes(), &createdExpense)
	expenseID, _ := createdExpense["id"].(string)
	if expenseID == "" {
		t.Fatalf("expected expense id to be set")
	}

	var payload bytes.Buffer
	writer := multipart.NewWriter(&payload)
	headers := make(textproto.MIMEHeader)
	headers.Set("Content-Disposition", `form-data; name="file"; filename="bill.png"`)
	headers.Set("Content-Type", "image/png")
	part, _ := writer.CreatePart(headers)
	_, _ = part.Write([]byte{0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a})
	_ = writer.WriteField("expenseId", expenseID)
	_ = writer.Close()

	uploadReq := httptest.NewRequest(http.MethodPost, "/api/v1/groups/"+groupID+"/attachments", &payload)
	uploadReq.Header.Set("Authorization", "Bearer test-token")
	uploadReq.Header.Set("Content-Type", writer.FormDataContentType())
	uploadRR := httptest.NewRecorder()
	router.ServeHTTP(uploadRR, uploadReq)
	if uploadRR.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d body=%s", uploadRR.Code, uploadRR.Body.String())
	}

	listReq := httptest.NewRequest(http.MethodGet, "/api/v1/groups/"+groupID+"/expenses", nil)
	listReq.Header.Set("Authorization", "Bearer test-token")
	listRR := httptest.NewRecorder()
	router.ServeHTTP(listRR, listReq)
	if listRR.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", listRR.Code, listRR.Body.String())
	}
	var listPayload map[string]any
	if err := json.Unmarshal(listRR.Body.Bytes(), &listPayload); err != nil {
		t.Fatalf("decode list response: %v", err)
	}
	expenses, ok := listPayload["expenses"].([]any)
	if !ok || len(expenses) == 0 {
		t.Fatalf("expected at least one expense in list")
	}
	first, ok := expenses[0].(map[string]any)
	if !ok {
		t.Fatalf("expected expense object, got %#v", expenses[0])
	}
	attachments, ok := first["attachments"].([]any)
	if !ok || len(attachments) != 1 {
		t.Fatalf("expected exactly one attachment, got %#v", first["attachments"])
	}
}

func TestAttachmentPreviewProxy(t *testing.T) {
	router := setupTestServer(&fakeFriendStore{})
	createPayload := map[string]any{"name": "Trip", "groupType": "split"}
	b, _ := json.Marshal(createPayload)
	createReq := httptest.NewRequest(http.MethodPost, "/api/v1/groups", bytes.NewReader(b))
	createReq.Header.Set("Authorization", "Bearer test-token")
	createReq.Header.Set("Content-Type", "application/json")
	createRR := httptest.NewRecorder()
	router.ServeHTTP(createRR, createReq)
	if createRR.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d body=%s", createRR.Code, createRR.Body.String())
	}
	var created map[string]any
	_ = json.Unmarshal(createRR.Body.Bytes(), &created)
	groupID, _ := created["id"].(string)

	raw := []byte{0x89, 0x50, 0x4e, 0x47}
	imageServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "image/png")
		_, _ = w.Write(raw)
	}))
	defer imageServer.Close()
	attachmentURL := imageServer.URL + "/bill.png"

	expensePayload := []byte(`{"amount":1200.5,"description":"Groceries","attachments":["` + attachmentURL + `"],"date":"2026-02-27T10:00:00Z"}`)
	createExpenseReq := httptest.NewRequest(http.MethodPost, "/api/v1/groups/"+groupID+"/expenses", bytes.NewReader(expensePayload))
	createExpenseReq.Header.Set("Authorization", "Bearer test-token")
	createExpenseReq.Header.Set("Content-Type", "application/json")
	createExpenseRR := httptest.NewRecorder()
	router.ServeHTTP(createExpenseRR, createExpenseReq)
	if createExpenseRR.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d body=%s", createExpenseRR.Code, createExpenseRR.Body.String())
	}
	var createdExpense map[string]any
	_ = json.Unmarshal(createExpenseRR.Body.Bytes(), &createdExpense)
	expenseID, _ := createdExpense["id"].(string)

	previewReq := httptest.NewRequest(
		http.MethodGet,
		"/api/v1/groups/"+groupID+"/expenses/"+expenseID+"/attachments/preview?url="+url.QueryEscape(attachmentURL),
		nil,
	)
	previewReq.Header.Set("Authorization", "Bearer test-token")
	previewRR := httptest.NewRecorder()
	router.ServeHTTP(previewRR, previewReq)
	if previewRR.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", previewRR.Code, previewRR.Body.String())
	}
	if got := previewRR.Header().Get("Content-Type"); got != "image/png" {
		t.Fatalf("expected content-type image/png, got %q", got)
	}
	body, _ := io.ReadAll(previewRR.Body)
	if !bytes.Equal(body, raw) {
		t.Fatalf("unexpected body: %v", body)
	}
}

func TestAttachmentPreviewRejectsUnknownURL(t *testing.T) {
	router := setupTestServer(&fakeFriendStore{})
	createPayload := map[string]any{"name": "Trip", "groupType": "split"}
	b, _ := json.Marshal(createPayload)
	createReq := httptest.NewRequest(http.MethodPost, "/api/v1/groups", bytes.NewReader(b))
	createReq.Header.Set("Authorization", "Bearer test-token")
	createReq.Header.Set("Content-Type", "application/json")
	createRR := httptest.NewRecorder()
	router.ServeHTTP(createRR, createReq)
	if createRR.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d body=%s", createRR.Code, createRR.Body.String())
	}
	var created map[string]any
	_ = json.Unmarshal(createRR.Body.Bytes(), &created)
	groupID, _ := created["id"].(string)

	expensePayload := []byte(`{"amount":1200.5,"description":"Groceries","attachments":["https://example.com/allowed.png"],"date":"2026-02-27T10:00:00Z"}`)
	createExpenseReq := httptest.NewRequest(http.MethodPost, "/api/v1/groups/"+groupID+"/expenses", bytes.NewReader(expensePayload))
	createExpenseReq.Header.Set("Authorization", "Bearer test-token")
	createExpenseReq.Header.Set("Content-Type", "application/json")
	createExpenseRR := httptest.NewRecorder()
	router.ServeHTTP(createExpenseRR, createExpenseReq)
	if createExpenseRR.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d body=%s", createExpenseRR.Code, createExpenseRR.Body.String())
	}
	var createdExpense map[string]any
	_ = json.Unmarshal(createExpenseRR.Body.Bytes(), &createdExpense)
	expenseID, _ := createdExpense["id"].(string)

	previewReq := httptest.NewRequest(
		http.MethodGet,
		"/api/v1/groups/"+groupID+"/expenses/"+expenseID+"/attachments/preview?url="+url.QueryEscape("https://example.com/other.png"),
		nil,
	)
	previewReq.Header.Set("Authorization", "Bearer test-token")
	previewRR := httptest.NewRecorder()
	router.ServeHTTP(previewRR, previewReq)
	if previewRR.Code != http.StatusForbidden {
		t.Fatalf("expected 403, got %d body=%s", previewRR.Code, previewRR.Body.String())
	}
}

func TestListGroupMembers(t *testing.T) {
	router := setupTestServer(&fakeFriendStore{})
	createPayload := map[string]any{"name": "Trip", "groupType": "split"}
	b, _ := json.Marshal(createPayload)
	createReq := httptest.NewRequest(http.MethodPost, "/api/v1/groups", bytes.NewReader(b))
	createReq.Header.Set("Authorization", "Bearer test-token")
	createReq.Header.Set("Content-Type", "application/json")
	createRR := httptest.NewRecorder()
	router.ServeHTTP(createRR, createReq)
	if createRR.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d body=%s", createRR.Code, createRR.Body.String())
	}
	var created map[string]any
	_ = json.Unmarshal(createRR.Body.Bytes(), &created)
	groupID, _ := created["id"].(string)

	listReq := httptest.NewRequest(http.MethodGet, "/api/v1/groups/"+groupID+"/members", nil)
	listReq.Header.Set("Authorization", "Bearer test-token")
	listRR := httptest.NewRecorder()
	router.ServeHTTP(listRR, listReq)
	if listRR.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", listRR.Code, listRR.Body.String())
	}
}

type fakeFriendStore struct {
	resolvedByContact map[string]friend.ResolveResult
	addedPairs        [][2]string
}

type fakeAttachmentUploader struct{}

func (f *fakeAttachmentUploader) UploadGroupAttachment(_ context.Context, input AttachmentUploadInput) (string, error) {
	return "https://example.com/groups/" + input.GroupID + "/file.jpg", nil
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
