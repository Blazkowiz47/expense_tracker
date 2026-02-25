package auth

import (
	"context"
	"errors"
)

var (
	ErrMissingToken = errors.New("missing token")
	ErrInvalidToken = errors.New("invalid token")
)

// Verifier validates a bearer token and returns the user uid.
type Verifier interface {
	Verify(ctx context.Context, token string) (string, error)
}
