package auth

import (
	"context"

	firebase "firebase.google.com/go/v4"
	firebaseauth "firebase.google.com/go/v4/auth"
	"google.golang.org/api/option"
)

// FirebaseVerifierConfig controls how the Firebase Admin client is initialized.
type FirebaseVerifierConfig struct {
	ProjectID       string
	CredentialsFile string
}

// FirebaseVerifier validates Firebase ID tokens and returns the Firebase UID.
type FirebaseVerifier struct {
	client *firebaseauth.Client
}

// NewFirebaseVerifier creates a Firebase-backed verifier.
func NewFirebaseVerifier(ctx context.Context, cfg FirebaseVerifierConfig) (*FirebaseVerifier, error) {
	appCfg := &firebase.Config{}
	if cfg.ProjectID != "" {
		appCfg.ProjectID = cfg.ProjectID
	}

	var opts []option.ClientOption
	if cfg.CredentialsFile != "" {
		opts = append(opts, option.WithCredentialsFile(cfg.CredentialsFile))
	}

	app, err := firebase.NewApp(ctx, appCfg, opts...)
	if err != nil {
		return nil, err
	}

	client, err := app.Auth(ctx)
	if err != nil {
		return nil, err
	}

	return &FirebaseVerifier{client: client}, nil
}

func (v *FirebaseVerifier) Verify(ctx context.Context, token string) (string, error) {
	if token == "" {
		return "", ErrMissingToken
	}

	verifiedToken, err := v.client.VerifyIDToken(ctx, token)
	if err != nil {
		return "", ErrInvalidToken
	}
	if verifiedToken == nil || verifiedToken.UID == "" {
		return "", ErrInvalidToken
	}

	return verifiedToken.UID, nil
}
