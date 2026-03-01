package config

import (
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

	return Config{
		Port:                    port,
		Environment:             env,
		AuthMode:                authMode,
		DevAuthToken:            devToken,
		DevAuthUID:              devUID,
		FirebaseProjectID:       firebaseProjectID,
		FirebaseCredentialsFile: firebaseCredentialsFile,
		FirebaseStorageBucket:   firebaseStorageBucket,
	}
}

func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
