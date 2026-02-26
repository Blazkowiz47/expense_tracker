package friend

import (
	"encoding/json"
	"errors"
	"net/http"
	"strings"

	"expense_tracker_backend/internal/httpapi"
	"expense_tracker_backend/internal/middleware"
)

var ErrInvalidInput = errors.New("invalid input")

type Handler struct {
	store Store
}

func NewHandler(store Store) *Handler {
	return &Handler{store: store}
}

type resolvePayload struct {
	EmailOrPhone string `json:"emailOrPhone"`
}

func (h *Handler) Resolve(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		httpapi.WriteError(w, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "unsupported method")
		return
	}
	uid, ok := middleware.UserIDFromContext(r.Context())
	if !ok || uid == "" {
		httpapi.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "user missing from context")
		return
	}

	payload, err := decodePayload(r)
	if err != nil {
		httpapi.WriteError(w, http.StatusBadRequest, "INVALID_ARGUMENT", err.Error())
		return
	}
	resolved, err := h.store.ResolveByEmailOrPhone(r.Context(), payload.EmailOrPhone)
	if err != nil {
		httpapi.WriteError(w, http.StatusInternalServerError, "INTERNAL", "resolve failed")
		return
	}
	if resolved.Exists && resolved.UID == uid {
		resolved.Exists = false
		resolved.UID = ""
	}
	httpapi.WriteJSON(w, http.StatusOK, resolved)
}

func (h *Handler) Add(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		httpapi.WriteError(w, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "unsupported method")
		return
	}
	uid, ok := middleware.UserIDFromContext(r.Context())
	if !ok || uid == "" {
		httpapi.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "user missing from context")
		return
	}

	payload, err := decodePayload(r)
	if err != nil {
		httpapi.WriteError(w, http.StatusBadRequest, "INVALID_ARGUMENT", err.Error())
		return
	}
	resolved, err := h.store.ResolveByEmailOrPhone(r.Context(), payload.EmailOrPhone)
	if err != nil {
		httpapi.WriteError(w, http.StatusInternalServerError, "INTERNAL", "resolve failed")
		return
	}
	if !resolved.Exists {
		httpapi.WriteError(w, http.StatusNotFound, "NOT_FOUND", "user not found")
		return
	}
	if resolved.UID == uid {
		httpapi.WriteError(w, http.StatusBadRequest, "INVALID_ARGUMENT", "cannot add yourself as friend")
		return
	}
	if err := h.store.AddFriendship(r.Context(), uid, resolved.UID); err != nil {
		httpapi.WriteError(w, http.StatusInternalServerError, "INTERNAL", "failed to add friend")
		return
	}
	httpapi.WriteJSON(w, http.StatusOK, map[string]any{
		"added": true,
		"uid":   resolved.UID,
	})
}

func (h *Handler) ByUID(w http.ResponseWriter, r *http.Request) {
	friendUID := strings.TrimPrefix(r.URL.Path, "/api/v1/friends/")
	if strings.TrimSpace(friendUID) == "" || strings.Contains(friendUID, "/") {
		httpapi.WriteError(w, http.StatusNotFound, "NOT_FOUND", "resource not found")
		return
	}

	switch r.Method {
	case http.MethodDelete:
		h.removeByUID(w, r, friendUID)
	default:
		httpapi.WriteError(w, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "unsupported method")
	}
}

func (h *Handler) List(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		httpapi.WriteError(w, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "unsupported method")
		return
	}
	uid, ok := middleware.UserIDFromContext(r.Context())
	if !ok || uid == "" {
		httpapi.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "user missing from context")
		return
	}

	friends, err := h.store.ListFriends(r.Context(), uid)
	if err != nil {
		httpapi.WriteError(w, http.StatusInternalServerError, "INTERNAL", "failed to list friends")
		return
	}
	httpapi.WriteJSON(w, http.StatusOK, map[string]any{"friends": friends})
}

func (h *Handler) removeByUID(w http.ResponseWriter, r *http.Request, friendUID string) {
	uid, ok := middleware.UserIDFromContext(r.Context())
	if !ok || uid == "" {
		httpapi.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "user missing from context")
		return
	}
	if uid == friendUID {
		httpapi.WriteError(w, http.StatusBadRequest, "INVALID_ARGUMENT", "cannot remove yourself")
		return
	}
	if err := h.store.RemoveFriendship(r.Context(), uid, friendUID); err != nil {
		httpapi.WriteError(w, http.StatusInternalServerError, "INTERNAL", "failed to remove friend")
		return
	}
	httpapi.WriteJSON(w, http.StatusOK, map[string]any{"removed": true})
}

func decodePayload(r *http.Request) (resolvePayload, error) {
	var payload resolvePayload
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		return payload, ErrInvalidInput
	}
	if strings.TrimSpace(payload.EmailOrPhone) == "" {
		return payload, ErrInvalidInput
	}
	return payload, nil
}
