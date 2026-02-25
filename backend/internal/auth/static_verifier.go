package auth

import "context"

// StaticVerifier is a local development verifier backed by an in-memory token map.
type StaticVerifier struct {
	tokenToUID map[string]string
}

func NewStaticVerifier(tokenToUID map[string]string) *StaticVerifier {
	copied := make(map[string]string, len(tokenToUID))
	for k, v := range tokenToUID {
		copied[k] = v
	}
	return &StaticVerifier{tokenToUID: copied}
}

func (v *StaticVerifier) Verify(_ context.Context, token string) (string, error) {
	if token == "" {
		return "", ErrMissingToken
	}
	uid, ok := v.tokenToUID[token]
	if !ok {
		return "", ErrInvalidToken
	}
	return uid, nil
}
