package httpapi

import (
	"encoding/json"
	"net/http"
)

// APIError is the standard error response payload.
type APIError struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

// ErrorEnvelope wraps all API errors.
type ErrorEnvelope struct {
	Error APIError `json:"error"`
}

func WriteJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}

func WriteError(w http.ResponseWriter, status int, code, message string) {
	WriteJSON(w, status, ErrorEnvelope{
		Error: APIError{Code: code, Message: message},
	})
}
