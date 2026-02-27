package group

import (
	"encoding/json"
	"net/http"
	"strings"
	"time"

	"expense_tracker_backend/internal/httpapi"
	"expense_tracker_backend/internal/middleware"
	"github.com/google/uuid"
)

type Handler struct {
	store Store
}

func NewHandler(store Store) *Handler {
	return &Handler{store: store}
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
	Name      string `json:"name"`
	GroupType string `json:"groupType"`
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

	now := time.Now().UTC()
	group := Group{
		ID:          uuid.NewString(),
		Name:        name,
		GroupType:   normalizeGroupType(payload.GroupType),
		CreatedBy:   uid,
		MemberUIDs:  []string{uid},
		MemberCount: 1,
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
