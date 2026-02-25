package middleware

import (
	"context"
	"net/http"
	"strings"

	"expense_tracker_backend/internal/auth"
	"expense_tracker_backend/internal/httpapi"
)

type contextKey string

const userIDContextKey contextKey = "userID"

// UserIDFromContext returns the authenticated user id if present.
func UserIDFromContext(ctx context.Context) (string, bool) {
	uid, ok := ctx.Value(userIDContextKey).(string)
	return uid, ok
}

// RequireAuth validates bearer tokens and injects uid in request context.
func RequireAuth(verifier auth.Verifier, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		authHeader := r.Header.Get("Authorization")
		if authHeader == "" {
			httpapi.WriteError(w, http.StatusUnauthorized, "MISSING_TOKEN", "missing Authorization header")
			return
		}

		parts := strings.SplitN(authHeader, " ", 2)
		if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") || strings.TrimSpace(parts[1]) == "" {
			httpapi.WriteError(w, http.StatusUnauthorized, "INVALID_TOKEN", "invalid bearer token format")
			return
		}

		uid, err := verifier.Verify(r.Context(), strings.TrimSpace(parts[1]))
		if err != nil {
			httpapi.WriteError(w, http.StatusUnauthorized, "INVALID_TOKEN", "token verification failed")
			return
		}

		ctx := context.WithValue(r.Context(), userIDContextKey, uid)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}
