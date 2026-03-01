package recurring

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"

	"expense_tracker_backend/internal/expense"
	"expense_tracker_backend/internal/httpapi"
	"expense_tracker_backend/internal/middleware"
)

type ExpenseCreator interface {
	Create(ctx context.Context, uid string, input expense.CreateExpenseInput) (expense.Expense, error)
}

type Handler struct {
	store          Store
	expenseCreator ExpenseCreator
	now            func() time.Time
	idGen          func() string
}

func NewHandler(store Store, expenseCreator ExpenseCreator) *Handler {
	return &Handler{
		store:          store,
		expenseCreator: expenseCreator,
		now:            func() time.Time { return time.Now().UTC() },
		idGen:          defaultIDGen,
	}
}

func defaultIDGen() string {
	var b [10]byte
	if _, err := rand.Read(b[:]); err == nil {
		return hex.EncodeToString(b[:])
	}
	return fmt.Sprintf("%d", time.Now().UTC().UnixNano())
}

type templatePayload struct {
	Title     string  `json:"title"`
	Amount    float64 `json:"amount"`
	Category  string  `json:"category"`
	Frequency string  `json:"frequency"`
	StartDate string  `json:"startDate"`
}

func (h *Handler) TemplatesCollection(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		h.handleList(w, r)
	case http.MethodPost:
		h.handleCreate(w, r)
	default:
		httpapi.WriteError(w, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "unsupported method")
	}
}

func (h *Handler) ProcessDue(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		httpapi.WriteError(w, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "unsupported method")
		return
	}
	uid, ok := middleware.UserIDFromContext(r.Context())
	if !ok || uid == "" {
		httpapi.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "user missing from context")
		return
	}
	if h.expenseCreator == nil {
		httpapi.WriteError(w, http.StatusNotImplemented, "NOT_IMPLEMENTED", "expense creator unavailable")
		return
	}
	items, err := h.store.ListByUser(r.Context(), uid)
	if err != nil {
		httpapi.WriteError(w, http.StatusInternalServerError, "INTERNAL", "failed to list recurring templates")
		return
	}
	now := h.now()
	createdCount := 0
	for _, template := range items {
		if !template.Active || template.NextDueDate.After(now) {
			continue
		}
		_, err := h.expenseCreator.Create(r.Context(), uid, expense.CreateExpenseInput{
			Amount:      template.Amount,
			Category:    template.Category,
			Description: "Recurring: " + template.Title,
			Date:        template.NextDueDate,
		})
		if err != nil {
			httpapi.WriteError(w, http.StatusInternalServerError, "INTERNAL", "failed to create due recurring expense")
			return
		}
		template.NextDueDate = computeNextDue(template.NextDueDate, template.Frequency)
		template.UpdatedAt = now
		if _, err := h.store.Update(r.Context(), template); err != nil {
			httpapi.WriteError(w, http.StatusInternalServerError, "INTERNAL", "failed to update recurring template")
			return
		}
		createdCount++
	}
	httpapi.WriteJSON(w, http.StatusOK, map[string]any{"created": createdCount})
}

func (h *Handler) handleList(w http.ResponseWriter, r *http.Request) {
	uid, ok := middleware.UserIDFromContext(r.Context())
	if !ok || uid == "" {
		httpapi.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "user missing from context")
		return
	}
	items, err := h.store.ListByUser(r.Context(), uid)
	if err != nil {
		httpapi.WriteError(w, http.StatusInternalServerError, "INTERNAL", "failed to list recurring templates")
		return
	}
	httpapi.WriteJSON(w, http.StatusOK, map[string]any{"templates": items})
}

func (h *Handler) handleCreate(w http.ResponseWriter, r *http.Request) {
	uid, ok := middleware.UserIDFromContext(r.Context())
	if !ok || uid == "" {
		httpapi.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "user missing from context")
		return
	}

	var payload templatePayload
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		httpapi.WriteError(w, http.StatusBadRequest, "INVALID_ARGUMENT", "request body must be valid JSON")
		return
	}

	title := strings.TrimSpace(payload.Title)
	category := strings.TrimSpace(payload.Category)
	frequency := strings.ToLower(strings.TrimSpace(payload.Frequency))
	if title == "" || category == "" || payload.Amount <= 0 {
		httpapi.WriteError(w, http.StatusBadRequest, "INVALID_ARGUMENT", "title, category and positive amount are required")
		return
	}
	if frequency != "daily" && frequency != "weekly" && frequency != "monthly" {
		httpapi.WriteError(w, http.StatusBadRequest, "INVALID_ARGUMENT", "frequency must be daily, weekly or monthly")
		return
	}
	startDate, err := time.Parse(time.RFC3339, strings.TrimSpace(payload.StartDate))
	if err != nil {
		httpapi.WriteError(w, http.StatusBadRequest, "INVALID_ARGUMENT", "startDate must be RFC3339")
		return
	}
	nextDue := computeNextDue(startDate.UTC(), frequency)
	now := h.now()
	template := Template{
		ID:          h.idGen(),
		UID:         uid,
		Title:       title,
		Amount:      payload.Amount,
		Category:    category,
		Frequency:   frequency,
		StartDate:   startDate.UTC(),
		NextDueDate: nextDue,
		Active:      true,
		CreatedAt:   now,
		UpdatedAt:   now,
	}
	created, err := h.store.Create(r.Context(), template)
	if err != nil {
		httpapi.WriteError(w, http.StatusInternalServerError, "INTERNAL", "failed to create recurring template")
		return
	}
	httpapi.WriteJSON(w, http.StatusCreated, created)
}

func computeNextDue(startDate time.Time, frequency string) time.Time {
	switch frequency {
	case "daily":
		return startDate.Add(24 * time.Hour)
	case "weekly":
		return startDate.Add(7 * 24 * time.Hour)
	case "monthly":
		return startDate.AddDate(0, 1, 0)
	default:
		return startDate
	}
}
