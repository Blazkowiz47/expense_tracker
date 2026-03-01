package middleware

import (
	"net/http"
	"os"
	"strings"
)

// CORS enables cross-origin requests for local development.
func CORS(next http.Handler) http.Handler {
	allowedOrigins := parseAllowedOrigins(os.Getenv("CORS_ALLOWED_ORIGINS"))
	allowAny := len(allowedOrigins) == 0 && !strings.EqualFold(os.Getenv("APP_ENV"), "production")

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := strings.TrimSpace(r.Header.Get("Origin"))
		if allowAny {
			w.Header().Set("Access-Control-Allow-Origin", "*")
		} else if origin != "" {
			if _, ok := allowedOrigins[origin]; ok {
				w.Header().Set("Access-Control-Allow-Origin", origin)
				w.Header().Set("Vary", "Origin")
			} else if r.Method == http.MethodOptions {
				http.Error(w, "origin not allowed", http.StatusForbidden)
				return
			}
		}
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type")

		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}

		next.ServeHTTP(w, r)
	})
}

func parseAllowedOrigins(raw string) map[string]struct{} {
	out := map[string]struct{}{}
	for _, part := range strings.Split(raw, ",") {
		origin := strings.TrimSpace(part)
		if origin == "" {
			continue
		}
		out[origin] = struct{}{}
	}
	return out
}
