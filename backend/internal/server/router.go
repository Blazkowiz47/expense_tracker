package server

import (
	"net/http"

	"expense_tracker_backend/internal/auth"
	"expense_tracker_backend/internal/expense"
	"expense_tracker_backend/internal/httpapi"
	"expense_tracker_backend/internal/middleware"
)

func NewRouter(verifier auth.Verifier, expenseHandler *expense.Handler) http.Handler {
	mux := http.NewServeMux()

	mux.HandleFunc("/health", func(w http.ResponseWriter, _ *http.Request) {
		httpapi.WriteJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})
	mux.HandleFunc("/api/v1/theme-packs", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			httpapi.WriteError(w, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "unsupported method")
			return
		}
		httpapi.WriteJSON(w, http.StatusOK, []map[string]any{
			{
				"familyId":           "splitwise",
				"displayName":        "Splitwise",
				"lightAccent":        0xFF26A17B,
				"darkAccent":         0xFF1A8F6C,
				"highContrastAccent": 0xFF000000,
			},
			{
				"familyId":           "tokyoNight",
				"displayName":        "Tokyo Night",
				"lightAccent":        0xFF7AA2F7,
				"darkAccent":         0xFF7DCFFF,
				"highContrastAccent": 0xFF1D1D1D,
			},
			{
				"familyId":           "mint",
				"displayName":        "Mint",
				"lightAccent":        0xFF3FBF9B,
				"darkAccent":         0xFF2FAE8E,
				"highContrastAccent": 0xFF0B3D2E,
			},
		})
	})

	mux.Handle("/api/v1/expenses", middleware.RequireAuth(verifier, http.HandlerFunc(expenseHandler.ExpensesCollection)))
	mux.Handle("/api/v1/expenses/", middleware.RequireAuth(verifier, http.HandlerFunc(expenseHandler.ExpenseByID)))
	mux.Handle("/api/v1/analytics", middleware.RequireAuth(verifier, http.HandlerFunc(expenseHandler.Analytics)))
	mux.Handle("/api/v1/dashboard/snapshot", middleware.RequireAuth(verifier, http.HandlerFunc(expenseHandler.DashboardSnapshot)))

	return middleware.CORS(mux)
}
