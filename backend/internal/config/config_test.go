package config

import "testing"

func TestLoadDefaults(t *testing.T) {
	t.Setenv("PORT", "")
	t.Setenv("APP_ENV", "")
	t.Setenv("AUTH_MODE", "")
	t.Setenv("DEV_AUTH_TOKEN", "")
	t.Setenv("DEV_AUTH_UID", "")
	t.Setenv("FIREBASE_PROJECT_ID", "")
	t.Setenv("FIREBASE_CREDENTIALS_FILE", "")
	t.Setenv("FIREBASE_STORAGE_BUCKET", "")
	t.Setenv("CORS_ALLOWED_ORIGINS", "")

	cfg := Load()

	if cfg.Port != "8080" {
		t.Fatalf("expected default port 8080, got %q", cfg.Port)
	}
	if cfg.Environment != "development" {
		t.Fatalf("expected default environment development, got %q", cfg.Environment)
	}
	if cfg.AuthMode != "dev" {
		t.Fatalf("expected default auth mode dev, got %q", cfg.AuthMode)
	}
	if cfg.DevAuthToken != "dev-token" {
		t.Fatalf("expected default token dev-token, got %q", cfg.DevAuthToken)
	}
	if cfg.DevAuthUID != "local-user" {
		t.Fatalf("expected default uid local-user, got %q", cfg.DevAuthUID)
	}
	if cfg.FirebaseProjectID != "" {
		t.Fatalf("expected empty firebase project id, got %q", cfg.FirebaseProjectID)
	}
	if cfg.FirebaseCredentialsFile != "" {
		t.Fatalf("expected empty firebase credentials file, got %q", cfg.FirebaseCredentialsFile)
	}
	if cfg.FirebaseStorageBucket != "" {
		t.Fatalf("expected empty firebase storage bucket, got %q", cfg.FirebaseStorageBucket)
	}
	if len(cfg.CORSAllowedOrigins) != 0 {
		t.Fatalf("expected no cors origins, got %+v", cfg.CORSAllowedOrigins)
	}
	if err := cfg.Validate(); err != nil {
		t.Fatalf("expected default config to validate: %v", err)
	}
}

func TestLoadFromEnv(t *testing.T) {
	t.Setenv("PORT", "9090")
	t.Setenv("APP_ENV", "test")
	t.Setenv("AUTH_MODE", "FIREBASE")
	t.Setenv("DEV_AUTH_TOKEN", "abc")
	t.Setenv("DEV_AUTH_UID", "uid-1")
	t.Setenv("FIREBASE_PROJECT_ID", "my-project")
	t.Setenv("FIREBASE_CREDENTIALS_FILE", "/tmp/service-account.json")
	t.Setenv("FIREBASE_STORAGE_BUCKET", "my-project.appspot.com")
	t.Setenv("CORS_ALLOWED_ORIGINS", "https://app.example.com,https://www.example.com")

	cfg := Load()

	if cfg.Port != "9090" ||
		cfg.Environment != "test" ||
		cfg.AuthMode != "firebase" ||
		cfg.DevAuthToken != "abc" ||
		cfg.DevAuthUID != "uid-1" ||
		cfg.FirebaseProjectID != "my-project" ||
		cfg.FirebaseCredentialsFile != "/tmp/service-account.json" ||
		cfg.FirebaseStorageBucket != "my-project.appspot.com" ||
		len(cfg.CORSAllowedOrigins) != 2 {
		t.Fatalf("unexpected config: %+v", cfg)
	}
	if err := cfg.Validate(); err != nil {
		t.Fatalf("expected env config to validate: %v", err)
	}
}

func TestValidateProductionRequiresCorsOrigins(t *testing.T) {
	t.Setenv("APP_ENV", "production")
	t.Setenv("AUTH_MODE", "dev")
	t.Setenv("DEV_AUTH_TOKEN", "dev-token")
	t.Setenv("DEV_AUTH_UID", "dev-user")
	t.Setenv("CORS_ALLOWED_ORIGINS", "")

	cfg := Load()
	if err := cfg.Validate(); err == nil {
		t.Fatalf("expected validation error for missing production CORS origins")
	}
}

func TestValidateFirebaseRequiresProjectID(t *testing.T) {
	t.Setenv("APP_ENV", "production")
	t.Setenv("AUTH_MODE", "firebase")
	t.Setenv("FIREBASE_PROJECT_ID", "")
	t.Setenv("CORS_ALLOWED_ORIGINS", "https://app.example.com")

	cfg := Load()
	if err := cfg.Validate(); err == nil {
		t.Fatalf("expected validation error for missing firebase project id")
	}
}
