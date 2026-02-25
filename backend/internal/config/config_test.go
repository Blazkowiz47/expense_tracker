package config

import "testing"

func TestLoadDefaults(t *testing.T) {
	t.Setenv("PORT", "")
	t.Setenv("APP_ENV", "")
	t.Setenv("DEV_AUTH_TOKEN", "")
	t.Setenv("DEV_AUTH_UID", "")

	cfg := Load()

	if cfg.Port != "8080" {
		t.Fatalf("expected default port 8080, got %q", cfg.Port)
	}
	if cfg.Environment != "development" {
		t.Fatalf("expected default environment development, got %q", cfg.Environment)
	}
	if cfg.DevAuthToken != "dev-token" {
		t.Fatalf("expected default token dev-token, got %q", cfg.DevAuthToken)
	}
	if cfg.DevAuthUID != "local-user" {
		t.Fatalf("expected default uid local-user, got %q", cfg.DevAuthUID)
	}
}

func TestLoadFromEnv(t *testing.T) {
	t.Setenv("PORT", "9090")
	t.Setenv("APP_ENV", "test")
	t.Setenv("DEV_AUTH_TOKEN", "abc")
	t.Setenv("DEV_AUTH_UID", "uid-1")

	cfg := Load()

	if cfg.Port != "9090" || cfg.Environment != "test" || cfg.DevAuthToken != "abc" || cfg.DevAuthUID != "uid-1" {
		t.Fatalf("unexpected config: %+v", cfg)
	}
}
