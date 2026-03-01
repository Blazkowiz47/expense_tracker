package group

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"slices"
	"strconv"
	"strings"
	"time"

	"expense_tracker_backend/internal/friend"
	"expense_tracker_backend/internal/httpapi"
	"expense_tracker_backend/internal/middleware"
	"github.com/google/uuid"
)

type Handler struct {
	store       Store
	friendStore friend.Store
	uploader    AttachmentUploader
}

func NewHandler(
	store Store,
	friendStore friend.Store,
	uploader AttachmentUploader,
) *Handler {
	return &Handler{
		store:       store,
		friendStore: friendStore,
		uploader:    uploader,
	}
}

func (h *Handler) GroupsCollection(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		h.handleList(w, r)
	case http.MethodPost:
		h.handleCreate(w, r)
	default:
		httpapi.WriteError(w, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "unsupported method")
	}
}

func (h *Handler) GroupByID(w http.ResponseWriter, r *http.Request) {
	path := strings.TrimPrefix(r.URL.Path, "/api/v1/groups/")
	if path == "" {
		httpapi.WriteError(w, http.StatusNotFound, "NOT_FOUND", "group path required")
		return
	}
	parts := strings.Split(path, "/")
	if parts[0] == "" {
		httpapi.WriteError(w, http.StatusNotFound, "NOT_FOUND", "route not found")
		return
	}
	groupID := parts[0]
	uid, ok := middleware.UserIDFromContext(r.Context())
	if !ok || uid == "" {
		httpapi.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "user missing from context")
		return
	}

	if len(parts) == 2 && parts[1] == "leave" {
		if r.Method != http.MethodPost {
			httpapi.WriteError(w, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "unsupported method")
			return
		}
		h.handleLeave(w, r, groupID, uid)
		return
	}
	if len(parts) == 3 && parts[1] == "members" && parts[2] == "add" {
		if r.Method != http.MethodPost {
			httpapi.WriteError(w, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "unsupported method")
			return
		}
		h.handleAddMember(w, r, groupID, uid)
		return
	}
	if len(parts) == 2 && parts[1] == "members" {
		if r.Method != http.MethodGet {
			httpapi.WriteError(w, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "unsupported method")
			return
		}
		h.handleListMembers(w, r, groupID, uid)
		return
	}
	if len(parts) == 2 && parts[1] == "expenses" {
		switch r.Method {
		case http.MethodGet:
			h.handleListExpenses(w, r, groupID, uid)
		case http.MethodPost:
			h.handleCreateExpense(w, r, groupID, uid)
		default:
			httpapi.WriteError(w, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "unsupported method")
		}
		return
	}
	if len(parts) == 2 && parts[1] == "attachments" {
		switch r.Method {
		case http.MethodPost:
			h.handleUploadAttachment(w, r, groupID, uid)
		default:
			httpapi.WriteError(w, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "unsupported method")
		}
		return
	}
	if len(parts) == 3 && parts[1] == "expenses" {
		expenseID := parts[2]
		switch r.Method {
		case http.MethodPut:
			h.handleUpdateExpense(w, r, groupID, expenseID, uid)
		default:
			httpapi.WriteError(w, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "unsupported method")
		}
		return
	}
	httpapi.WriteError(w, http.StatusNotFound, "NOT_FOUND", "route not found")
}

func (h *Handler) handleUploadAttachment(
	w http.ResponseWriter,
	r *http.Request,
	groupID, uid string,
) {
	if h.uploader == nil {
		httpapi.WriteError(w, http.StatusNotImplemented, "NOT_IMPLEMENTED", "attachment uploads are unavailable")
		return
	}
	group, err := h.store.GetByID(r.Context(), groupID)
	if err != nil {
		httpapi.WriteError(w, http.StatusNotFound, "NOT_FOUND", "group not found")
		return
	}
	if !slices.Contains(group.MemberUIDs, uid) {
		httpapi.WriteError(w, http.StatusForbidden, "FORBIDDEN", "you are not a group member")
		return
	}
	if err := r.ParseMultipartForm(10 << 20); err != nil {
		httpapi.WriteError(w, http.StatusBadRequest, "INVALID_ARGUMENT", "invalid multipart payload")
		return
	}
	file, header, err := r.FormFile("file")
	if err != nil {
		httpapi.WriteError(w, http.StatusBadRequest, "INVALID_ARGUMENT", "file is required")
		return
	}
	defer file.Close()
	contentType := detectContentType(header, file)
	if !strings.HasPrefix(contentType, "image/") {
		httpapi.WriteError(w, http.StatusBadRequest, "INVALID_ARGUMENT", "only image attachments are supported")
		return
	}
	raw, err := io.ReadAll(file)
	if err != nil {
		httpapi.WriteError(w, http.StatusInternalServerError, "INTERNAL", "failed to read uploaded file")
		return
	}
	if len(raw) == 0 {
		httpapi.WriteError(w, http.StatusBadRequest, "INVALID_ARGUMENT", "uploaded file is empty")
		return
	}
	expenseID := strings.TrimSpace(r.FormValue("expenseId"))
	if expenseID == "" {
		httpapi.WriteError(w, http.StatusBadRequest, "INVALID_ARGUMENT", "expenseId is required")
		return
	}
	downloadURL, err := h.uploader.UploadGroupAttachment(r.Context(), AttachmentUploadInput{
		GroupID:     groupID,
		ExpenseID:   expenseID,
		UploaderUID: uid,
		FileName:    header.Filename,
		ContentType: contentType,
		Bytes:       raw,
	})
	if err != nil {
		httpapi.WriteError(w, http.StatusInternalServerError, "INTERNAL", fmt.Sprintf("failed to upload attachment: %v", err))
		return
	}
	httpapi.WriteJSON(w, http.StatusCreated, map[string]any{"url": downloadURL})
}

func detectContentType(
	header *multipart.FileHeader,
	file multipart.File,
) string {
	if header != nil {
		if header.Header != nil {
			if contentType := strings.TrimSpace(header.Header.Get("Content-Type")); contentType != "" {
				return contentType
			}
		}
	}
	sniff := make([]byte, 512)
	n, _ := file.Read(sniff)
	_, _ = file.Seek(0, io.SeekStart)
	if n > 0 {
		return http.DetectContentType(sniff[:n])
	}
	return "application/octet-stream"
}

func (h *Handler) handleListMembers(w http.ResponseWriter, r *http.Request, groupID, uid string) {
	group, err := h.store.GetByID(r.Context(), groupID)
	if err != nil {
		httpapi.WriteError(w, http.StatusNotFound, "NOT_FOUND", "group not found")
		return
	}
	if !slices.Contains(group.MemberUIDs, uid) {
		httpapi.WriteError(w, http.StatusForbidden, "FORBIDDEN", "you are not a group member")
		return
	}
	members, err := h.store.ListMembers(r.Context(), groupID)
	if err != nil {
		httpapi.WriteError(w, http.StatusInternalServerError, "INTERNAL", "failed to list members")
		return
	}
	httpapi.WriteJSON(w, http.StatusOK, map[string]any{"members": members})
}

func (h *Handler) handleLeave(w http.ResponseWriter, r *http.Request, groupID, uid string) {

	deleted, err := h.store.Leave(r.Context(), groupID, uid)
	if err != nil {
		switch {
		case errors.Is(err, ErrGroupNotFound):
			httpapi.WriteError(w, http.StatusNotFound, "NOT_FOUND", "group not found")
		case errors.Is(err, ErrNotMember):
			httpapi.WriteError(w, http.StatusForbidden, "FORBIDDEN", "you are not a group member")
		default:
			httpapi.WriteError(w, http.StatusInternalServerError, "INTERNAL", "failed to leave group")
		}
		return
	}
	httpapi.WriteJSON(w, http.StatusOK, map[string]any{
		"left":    true,
		"deleted": deleted,
	})
}

type addMemberPayload struct {
	EmailOrPhone string `json:"emailOrPhone"`
}

func (h *Handler) handleAddMember(w http.ResponseWriter, r *http.Request, groupID, uid string) {
	group, err := h.store.GetByID(r.Context(), groupID)
	if err != nil {
		httpapi.WriteError(w, http.StatusNotFound, "NOT_FOUND", "group not found")
		return
	}
	if !slices.Contains(group.MemberUIDs, uid) {
		httpapi.WriteError(w, http.StatusForbidden, "FORBIDDEN", "you are not a group member")
		return
	}

	var payload addMemberPayload
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		httpapi.WriteError(w, http.StatusBadRequest, "INVALID_ARGUMENT", "invalid payload")
		return
	}
	contact := strings.TrimSpace(payload.EmailOrPhone)
	if contact == "" {
		httpapi.WriteError(w, http.StatusBadRequest, "INVALID_ARGUMENT", "emailOrPhone is required")
		return
	}
	resolved, err := h.friendStore.ResolveByEmailOrPhone(r.Context(), contact)
	if err != nil {
		httpapi.WriteError(w, http.StatusInternalServerError, "INTERNAL", "failed to resolve member")
		return
	}
	if !resolved.Exists || strings.TrimSpace(resolved.UID) == "" {
		httpapi.WriteError(w, http.StatusNotFound, "NOT_FOUND", "member not found")
		return
	}
	if err := h.friendStore.AddFriendship(r.Context(), uid, resolved.UID); err != nil {
		httpapi.WriteError(w, http.StatusInternalServerError, "INTERNAL", "failed to link friendship")
		return
	}
	updated, err := h.store.AddMember(r.Context(), groupID, resolved.UID)
	if err != nil {
		httpapi.WriteError(w, http.StatusInternalServerError, "INTERNAL", "failed to add member")
		return
	}
	httpapi.WriteJSON(w, http.StatusOK, updated)
}

type groupExpensePayload struct {
	ID          string   `json:"id"`
	Amount      float64  `json:"amount"`
	Description string   `json:"description"`
	PaidBy      string   `json:"paidBy"`
	SplitMode   string   `json:"splitMode"`
	SplitWith   []string `json:"splitWith"`
	Attachments []string `json:"attachments"`
	Date        string   `json:"date"`
}

func (h *Handler) handleListExpenses(w http.ResponseWriter, r *http.Request, groupID, uid string) {
	group, err := h.store.GetByID(r.Context(), groupID)
	if err != nil {
		httpapi.WriteError(w, http.StatusNotFound, "NOT_FOUND", "group not found")
		return
	}
	if !slices.Contains(group.MemberUIDs, uid) {
		httpapi.WriteError(w, http.StatusForbidden, "FORBIDDEN", "you are not a group member")
		return
	}
	items, err := h.store.ListExpenses(r.Context(), groupID)
	if err != nil {
		httpapi.WriteError(w, http.StatusInternalServerError, "INTERNAL", "failed to list group expenses")
		return
	}
	httpapi.WriteJSON(w, http.StatusOK, map[string]any{"expenses": items})
}

func (h *Handler) handleCreateExpense(w http.ResponseWriter, r *http.Request, groupID, uid string) {
	group, err := h.store.GetByID(r.Context(), groupID)
	if err != nil {
		httpapi.WriteError(w, http.StatusNotFound, "NOT_FOUND", "group not found")
		return
	}
	if !slices.Contains(group.MemberUIDs, uid) {
		httpapi.WriteError(w, http.StatusForbidden, "FORBIDDEN", "you are not a group member")
		return
	}
	var payload groupExpensePayload
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		httpapi.WriteError(w, http.StatusBadRequest, "INVALID_ARGUMENT", "invalid payload")
		return
	}
	description := strings.TrimSpace(payload.Description)
	if description == "" || payload.Amount <= 0 {
		httpapi.WriteError(w, http.StatusBadRequest, "INVALID_ARGUMENT", "description and positive amount required")
		return
	}
	date := time.Now().UTC()
	if strings.TrimSpace(payload.Date) != "" {
		parsed, err := time.Parse(time.RFC3339, payload.Date)
		if err != nil {
			httpapi.WriteError(w, http.StatusBadRequest, "INVALID_ARGUMENT", "date must be RFC3339")
			return
		}
		date = parsed.UTC()
	}
	expenseID := strings.TrimSpace(payload.ID)
	if expenseID == "" {
		expenseID = strconv.FormatInt(time.Now().UTC().UnixNano(), 10)
	}
	expense := GroupExpense{
		ID:          expenseID,
		GroupID:     groupID,
		CreatedBy:   uid,
		PaidBy:      strings.TrimSpace(payload.PaidBy),
		SplitMode:   sanitizeSplitMode(payload.SplitMode),
		SplitWith:   sanitizeSplitWith(payload.SplitWith),
		Amount:      payload.Amount,
		Description: description,
		Attachments: sanitizeAttachments(payload.Attachments),
		Date:        date,
		CreatedAt:   time.Now().UTC(),
	}
	if expense.PaidBy == "" {
		expense.PaidBy = uid
	}
	created, err := h.store.CreateExpense(r.Context(), expense)
	if err != nil {
		httpapi.WriteError(w, http.StatusInternalServerError, "INTERNAL", fmt.Sprintf("failed to create group expense: %v", err))
		return
	}
	httpapi.WriteJSON(w, http.StatusCreated, created)
}

func (h *Handler) handleUpdateExpense(
	w http.ResponseWriter,
	r *http.Request,
	groupID, expenseID, uid string,
) {
	group, err := h.store.GetByID(r.Context(), groupID)
	if err != nil {
		httpapi.WriteError(w, http.StatusNotFound, "NOT_FOUND", "group not found")
		return
	}
	if !slices.Contains(group.MemberUIDs, uid) {
		httpapi.WriteError(w, http.StatusForbidden, "FORBIDDEN", "you are not a group member")
		return
	}
	var payload groupExpensePayload
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		httpapi.WriteError(w, http.StatusBadRequest, "INVALID_ARGUMENT", "invalid payload")
		return
	}
	description := strings.TrimSpace(payload.Description)
	if description == "" || payload.Amount <= 0 {
		httpapi.WriteError(w, http.StatusBadRequest, "INVALID_ARGUMENT", "description and positive amount required")
		return
	}
	date := time.Now().UTC()
	if strings.TrimSpace(payload.Date) != "" {
		parsed, err := time.Parse(time.RFC3339, payload.Date)
		if err != nil {
			httpapi.WriteError(w, http.StatusBadRequest, "INVALID_ARGUMENT", "date must be RFC3339")
			return
		}
		date = parsed.UTC()
	}
	updated, err := h.store.UpdateExpense(r.Context(), GroupExpense{
		ID:          strings.TrimSpace(expenseID),
		GroupID:     groupID,
		CreatedBy:   uid,
		PaidBy:      strings.TrimSpace(payload.PaidBy),
		SplitMode:   sanitizeSplitMode(payload.SplitMode),
		SplitWith:   sanitizeSplitWith(payload.SplitWith),
		Amount:      payload.Amount,
		Description: description,
		Attachments: sanitizeAttachments(payload.Attachments),
		Date:        date,
	})
	if err != nil {
		switch {
		case errors.Is(err, ErrGroupNotFound):
			httpapi.WriteError(w, http.StatusNotFound, "NOT_FOUND", "group or expense not found")
		default:
			httpapi.WriteError(w, http.StatusInternalServerError, "INTERNAL", fmt.Sprintf("failed to update group expense: %v", err))
		}
		return
	}
	httpapi.WriteJSON(w, http.StatusOK, updated)
}

func sanitizeAttachments(raw []string) []string {
	if len(raw) == 0 {
		return nil
	}
	out := make([]string, 0, len(raw))
	seen := make(map[string]struct{}, len(raw))
	for _, item := range raw {
		trimmed := strings.TrimSpace(item)
		if trimmed == "" {
			continue
		}
		if _, ok := seen[trimmed]; ok {
			continue
		}
		seen[trimmed] = struct{}{}
		out = append(out, trimmed)
	}
	if len(out) == 0 {
		return nil
	}
	return out
}

func sanitizeSplitMode(raw string) string {
	normalized := strings.TrimSpace(strings.ToLower(raw))
	switch normalized {
	case "equally", "exact", "percent", "shares", "adjustment":
		return normalized
	default:
		return "equally"
	}
}

func sanitizeSplitWith(raw []string) []string {
	if len(raw) == 0 {
		return nil
	}
	out := make([]string, 0, len(raw))
	seen := make(map[string]struct{}, len(raw))
	for _, item := range raw {
		trimmed := strings.TrimSpace(item)
		if trimmed == "" {
			continue
		}
		if _, ok := seen[trimmed]; ok {
			continue
		}
		seen[trimmed] = struct{}{}
		out = append(out, trimmed)
	}
	if len(out) == 0 {
		return nil
	}
	return out
}

func (h *Handler) handleList(w http.ResponseWriter, r *http.Request) {
	uid, ok := middleware.UserIDFromContext(r.Context())
	if !ok || uid == "" {
		httpapi.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "user missing from context")
		return
	}

	groups, err := h.store.ListByMember(r.Context(), uid)
	if err != nil {
		httpapi.WriteError(w, http.StatusInternalServerError, "INTERNAL", "failed to list groups")
		return
	}
	httpapi.WriteJSON(w, http.StatusOK, map[string]any{"groups": groups})
}

type createGroupPayload struct {
	Name      string   `json:"name"`
	GroupType string   `json:"groupType"`
	Members   []string `json:"members"`
}

func (h *Handler) handleCreate(w http.ResponseWriter, r *http.Request) {
	uid, ok := middleware.UserIDFromContext(r.Context())
	if !ok || uid == "" {
		httpapi.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "user missing from context")
		return
	}

	var payload createGroupPayload
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		httpapi.WriteError(w, http.StatusBadRequest, "INVALID_ARGUMENT", "invalid payload")
		return
	}
	name := strings.TrimSpace(payload.Name)
	if name == "" {
		httpapi.WriteError(w, http.StatusBadRequest, "INVALID_ARGUMENT", "group name is required")
		return
	}
	memberUIDs := []string{uid}
	for _, contact := range payload.Members {
		trimmed := strings.TrimSpace(contact)
		if trimmed == "" {
			continue
		}
		if h.friendStore == nil {
			httpapi.WriteError(w, http.StatusInternalServerError, "INTERNAL", "friend store unavailable")
			return
		}
		resolved, err := h.friendStore.ResolveByEmailOrPhone(r.Context(), trimmed)
		if err != nil {
			httpapi.WriteError(w, http.StatusInternalServerError, "INTERNAL", "failed to resolve group member")
			return
		}
		if !resolved.Exists {
			httpapi.WriteError(
				w,
				http.StatusNotFound,
				"NOT_FOUND",
				"group member not found: "+trimmed,
			)
			return
		}
		if resolved.UID == uid {
			continue
		}
		if !slices.Contains(memberUIDs, resolved.UID) {
			memberUIDs = append(memberUIDs, resolved.UID)
		}
		if err := h.friendStore.AddFriendship(r.Context(), uid, resolved.UID); err != nil {
			httpapi.WriteError(w, http.StatusInternalServerError, "INTERNAL", "failed to add member friendship")
			return
		}
	}

	now := time.Now().UTC()
	group := Group{
		ID:          uuid.NewString(),
		Name:        name,
		GroupType:   normalizeGroupType(payload.GroupType),
		CreatedBy:   uid,
		MemberUIDs:  memberUIDs,
		MemberCount: len(memberUIDs),
		CreatedAt:   now,
		UpdatedAt:   now,
	}

	created, err := h.store.Create(r.Context(), group)
	if err != nil {
		httpapi.WriteError(w, http.StatusInternalServerError, "INTERNAL", "failed to create group")
		return
	}
	httpapi.WriteJSON(w, http.StatusCreated, created)
}

func normalizeGroupType(raw string) GroupType {
	switch strings.ToLower(strings.TrimSpace(raw)) {
	case string(GroupTypeFamily):
		return GroupTypeFamily
	default:
		return GroupTypeSplit
	}
}
