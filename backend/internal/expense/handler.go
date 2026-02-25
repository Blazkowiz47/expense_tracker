package expense

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"time"

	"expense_tracker_backend/internal/httpapi"
	"expense_tracker_backend/internal/middleware"
)

// Handler serves expense-related API endpoints.
type Handler struct {
	service *Service
}

func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

func (h *Handler) ExpensesCollection(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		h.handleListExpenses(w, r)
	case http.MethodPost:
		h.handleCreateExpense(w, r)
	default:
		httpapi.WriteError(w, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "unsupported method")
	}
}

func (h *Handler) ExpenseByID(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimPrefix(r.URL.Path, "/api/v1/expenses/")
	if strings.TrimSpace(id) == "" || strings.Contains(id, "/") {
		httpapi.WriteError(w, http.StatusNotFound, "NOT_FOUND", "resource not found")
		return
	}

	switch r.Method {
	case http.MethodPut:
		h.handleUpdateExpense(w, r, id)
	case http.MethodDelete:
		h.handleDeleteExpense(w, r, id)
	default:
		httpapi.WriteError(w, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "unsupported method")
	}
}

func (h *Handler) Analytics(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		httpapi.WriteError(w, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "unsupported method")
		return
	}
	uid, ok := middleware.UserIDFromContext(r.Context())
	if !ok || uid == "" {
		httpapi.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "user missing from context")
		return
	}

	from, err := parseTimeParam(r.URL.Query().Get("from"))
	if err != nil {
		httpapi.WriteError(w, http.StatusBadRequest, "INVALID_ARGUMENT", "invalid 'from' query param")
		return
	}
	to, err := parseTimeParam(r.URL.Query().Get("to"))
	if err != nil {
		httpapi.WriteError(w, http.StatusBadRequest, "INVALID_ARGUMENT", "invalid 'to' query param")
		return
	}

	analytics, err := h.service.Analytics(r.Context(), uid, from, to)
	if err != nil {
		h.handleServiceError(w, err)
		return
	}

	httpapi.WriteJSON(w, http.StatusOK, analytics)
}

func (h *Handler) DashboardSnapshot(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		httpapi.WriteError(w, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "unsupported method")
		return
	}
	uid, ok := middleware.UserIDFromContext(r.Context())
	if !ok || uid == "" {
		httpapi.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "user missing from context")
		return
	}

	analytics, err := h.service.Analytics(r.Context(), uid, nil, nil)
	if err != nil {
		h.handleServiceError(w, err)
		return
	}

	expenses, err := h.service.List(r.Context(), uid, ListFilter{Page: 1, Limit: 20})
	if err != nil {
		h.handleServiceError(w, err)
		return
	}

	type categoryTotal struct {
		category string
		amount   float64
	}

	categoryTotals := make([]categoryTotal, 0, len(analytics.ByCategory))
	for category, amount := range analytics.ByCategory {
		categoryTotals = append(categoryTotals, categoryTotal{
			category: category,
			amount:   amount,
		})
	}
	sort.Slice(categoryTotals, func(i, j int) bool {
		return categoryTotals[i].amount > categoryTotals[j].amount
	})

	balanceItems := make([]DashboardBalanceItem, 0, len(categoryTotals))
	for _, total := range categoryTotals {
		balanceItems = append(balanceItems, DashboardBalanceItem{
			Title:      total.category,
			Subtitle:   "category total",
			AmountText: formatINR(total.amount),
			Positive:   total.amount >= 0,
		})
	}

	activityItems := make([]DashboardActivityItem, 0, len(expenses))
	for _, exp := range expenses {
		title := exp.Description
		if strings.TrimSpace(title) == "" {
			title = "Expense in " + exp.Category
		}
		activityItems = append(activityItems, DashboardActivityItem{
			Title:      title,
			Subtitle:   exp.Date.UTC().Format(time.RFC3339),
			AmountText: "You owe " + formatINR(exp.Amount),
			Positive:   false,
		})
	}

	total := analytics.TotalAmount
	snapshot := DashboardSnapshot{
		OverallLabel:      "Overall, you are owed",
		OverallAmountText: formatINR(abs(total)),
		OverallPositive:   total >= 0,
		FriendItems:       firstNBalanceItems(balanceItems, 5),
		GroupItems:        balanceItems,
		ActivityItems:     activityItems,
		AccountName:       "Local User",
		AccountEmail:      uid + "@local",
	}
	if total < 0 {
		snapshot.OverallLabel = "Overall, you owe"
	}

	httpapi.WriteJSON(w, http.StatusOK, snapshot)
}

type expensePayload struct {
	Amount      float64 `json:"amount"`
	Category    string  `json:"category"`
	Description string  `json:"description"`
	Date        string  `json:"date"`
}

func (h *Handler) handleCreateExpense(w http.ResponseWriter, r *http.Request) {
	uid, ok := middleware.UserIDFromContext(r.Context())
	if !ok || uid == "" {
		httpapi.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "user missing from context")
		return
	}

	var payload expensePayload
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		httpapi.WriteError(w, http.StatusBadRequest, "INVALID_ARGUMENT", "request body must be valid JSON")
		return
	}
	date, err := time.Parse(time.RFC3339, payload.Date)
	if err != nil {
		httpapi.WriteError(w, http.StatusBadRequest, "INVALID_ARGUMENT", "date must be RFC3339")
		return
	}

	expense, err := h.service.Create(r.Context(), uid, CreateExpenseInput{
		Amount:      payload.Amount,
		Category:    payload.Category,
		Description: payload.Description,
		Date:        date,
	})
	if err != nil {
		h.handleServiceError(w, err)
		return
	}

	httpapi.WriteJSON(w, http.StatusCreated, expense)
}

func (h *Handler) handleListExpenses(w http.ResponseWriter, r *http.Request) {
	uid, ok := middleware.UserIDFromContext(r.Context())
	if !ok || uid == "" {
		httpapi.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "user missing from context")
		return
	}

	page := parseIntOrDefault(r.URL.Query().Get("page"), 1)
	limit := parseIntOrDefault(r.URL.Query().Get("limit"), 20)
	from, err := parseTimeParam(r.URL.Query().Get("from"))
	if err != nil {
		httpapi.WriteError(w, http.StatusBadRequest, "INVALID_ARGUMENT", "invalid 'from' query param")
		return
	}
	to, err := parseTimeParam(r.URL.Query().Get("to"))
	if err != nil {
		httpapi.WriteError(w, http.StatusBadRequest, "INVALID_ARGUMENT", "invalid 'to' query param")
		return
	}

	expenses, err := h.service.List(r.Context(), uid, ListFilter{
		Page:     page,
		Limit:    limit,
		Category: r.URL.Query().Get("category"),
		From:     from,
		To:       to,
	})
	if err != nil {
		h.handleServiceError(w, err)
		return
	}

	httpapi.WriteJSON(w, http.StatusOK, map[string]any{"expenses": expenses})
}

func (h *Handler) handleUpdateExpense(w http.ResponseWriter, r *http.Request, id string) {
	uid, ok := middleware.UserIDFromContext(r.Context())
	if !ok || uid == "" {
		httpapi.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "user missing from context")
		return
	}

	var payload expensePayload
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		httpapi.WriteError(w, http.StatusBadRequest, "INVALID_ARGUMENT", "request body must be valid JSON")
		return
	}
	date, err := time.Parse(time.RFC3339, payload.Date)
	if err != nil {
		httpapi.WriteError(w, http.StatusBadRequest, "INVALID_ARGUMENT", "date must be RFC3339")
		return
	}

	expense, err := h.service.Update(r.Context(), uid, id, UpdateExpenseInput{
		Amount:      payload.Amount,
		Category:    payload.Category,
		Description: payload.Description,
		Date:        date,
	})
	if err != nil {
		h.handleServiceError(w, err)
		return
	}

	httpapi.WriteJSON(w, http.StatusOK, expense)
}

func (h *Handler) handleDeleteExpense(w http.ResponseWriter, r *http.Request, id string) {
	uid, ok := middleware.UserIDFromContext(r.Context())
	if !ok || uid == "" {
		httpapi.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "user missing from context")
		return
	}

	if err := h.service.Delete(r.Context(), uid, id); err != nil {
		h.handleServiceError(w, err)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

func (h *Handler) handleServiceError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, ErrInvalidInput):
		httpapi.WriteError(w, http.StatusBadRequest, "INVALID_ARGUMENT", err.Error())
	case errors.Is(err, ErrNotFound):
		httpapi.WriteError(w, http.StatusNotFound, "NOT_FOUND", "expense not found")
	case errors.Is(err, ErrForbidden):
		httpapi.WriteError(w, http.StatusForbidden, "FORBIDDEN", "not allowed to access this expense")
	default:
		httpapi.WriteError(w, http.StatusInternalServerError, "INTERNAL", "internal server error")
	}
}

func parseTimeParam(value string) (*time.Time, error) {
	if strings.TrimSpace(value) == "" {
		return nil, nil
	}
	t, err := time.Parse(time.RFC3339, value)
	if err != nil {
		return nil, err
	}
	u := t.UTC()
	return &u, nil
}

func parseIntOrDefault(value string, fallback int) int {
	if strings.TrimSpace(value) == "" {
		return fallback
	}
	parsed, err := strconv.Atoi(value)
	if err != nil {
		return fallback
	}
	return parsed
}

func formatINR(amount float64) string {
	return fmt.Sprintf("INR %.2f", amount)
}

func abs(v float64) float64 {
	if v < 0 {
		return -v
	}
	return v
}

func firstNBalanceItems(items []DashboardBalanceItem, n int) []DashboardBalanceItem {
	if n <= 0 || len(items) == 0 {
		return []DashboardBalanceItem{}
	}
	if len(items) <= n {
		out := make([]DashboardBalanceItem, len(items))
		copy(out, items)
		return out
	}
	out := make([]DashboardBalanceItem, n)
	copy(out, items[:n])
	return out
}
