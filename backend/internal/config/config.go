package config

import (
	"errors"
	"fmt"
	"os"
	"strings"
)

// Config contains runtime server and local auth settings.
type Config struct {
	Port                    string
	Environment             string
	AuthMode                string
	DevAuthToken            string
	DevAuthUID              string
	FirebaseProjectID       string
	FirebaseCredentialsFile string
	FirebaseStorageBucket   string
	CORSAllowedOrigins      []string
}

// Load reads configuration from environment variables with sensible defaults.
func Load() Config {
	port := getenv("PORT", "8080")
	env := getenv("APP_ENV", "development")
	authMode := strings.ToLower(getenv("AUTH_MODE", "dev"))
	devToken := getenv("DEV_AUTH_TOKEN", "dev-token")
	devUID := getenv("DEV_AUTH_UID", "local-user")
	firebaseProjectID := getenv("FIREBASE_PROJECT_ID", "")
	firebaseCredentialsFile := getenv("FIREBASE_CREDENTIALS_FILE", "")
	firebaseStorageBucket := getenv("FIREBASE_STORAGE_BUCKET", "")
	corsAllowedOrigins := parseCSVEnv("CORS_ALLOWED_ORIGINS")

	return Config{
		Port:                    port,
		Environment:             env,
		AuthMode:                authMode,
		DevAuthToken:            devToken,
		DevAuthUID:              devUID,
		FirebaseProjectID:       firebaseProjectID,
		FirebaseCredentialsFile: firebaseCredentialsFile,
		FirebaseStorageBucket:   firebaseStorageBucket,
		CORSAllowedOrigins:      corsAllowedOrigins,
	}
}

func (c Config) Validate() error {
	if strings.TrimSpace(c.Port) == "" {
		return errors.New("PORT must not be empty")
	}
	switch strings.ToLower(strings.TrimSpace(c.AuthMode)) {
	case "dev":
		if strings.TrimSpace(c.DevAuthToken) == "" || strings.TrimSpace(c.DevAuthUID) == "" {
			return errors.New("DEV_AUTH_TOKEN and DEV_AUTH_UID are required for AUTH_MODE=dev")
		}
	case "firebase":
		if strings.TrimSpace(c.FirebaseProjectID) == "" {
			return errors.New("FIREBASE_PROJECT_ID is required for AUTH_MODE=firebase")
		}
	default:
		return fmt.Errorf("unsupported AUTH_MODE %q (allowed: dev, firebase)", c.AuthMode)
	}
	if strings.EqualFold(c.Environment, "production") && len(c.CORSAllowedOrigins) == 0 {
		return errors.New("CORS_ALLOWED_ORIGINS must be set in production")
	}
	return nil
}

func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func parseCSVEnv(key string) []string {
	raw := getenv(key, "")
	if strings.TrimSpace(raw) == "" {
		return nil
	}
	parts := strings.Split(raw, ",")
	out := make([]string, 0, len(parts))
	seen := map[string]struct{}{}
	for _, item := range parts {
		trimmed := strings.TrimSpace(item)
		if trimmed == "" {
			continue
		}
		if _, ok := seen[trimmed]; ok {
			continue
		}
		seen[trimmed] = struct{}{}
		out = append(out, trimmed)
	}
	if len(out) == 0 {
		return nil
	}
	return out
}
