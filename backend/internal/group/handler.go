package group

import (
	"encoding/json"
	"errors"
	"net/http"
	"slices"
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
}

func NewHandler(store Store, friendStore friend.Store) *Handler {
	return &Handler{
		store:       store,
		friendStore: friendStore,
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
	if len(parts) != 2 || parts[1] != "leave" || parts[0] == "" {
		httpapi.WriteError(w, http.StatusNotFound, "NOT_FOUND", "route not found")
		return
	}
	groupID := parts[0]
	if r.Method != http.MethodPost {
		httpapi.WriteError(w, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "unsupported method")
		return
	}
	uid, ok := middleware.UserIDFromContext(r.Context())
	if !ok || uid == "" {
		httpapi.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "user missing from context")
		return
	}

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
