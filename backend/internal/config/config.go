package config

import "os"

// Config contains runtime server and local auth settings.
type Config struct {
	Port         string
	Environment  string
	DevAuthToken string
	DevAuthUID   string
}

// Load reads configuration from environment variables with sensible defaults.
func Load() Config {
	port := getenv("PORT", "8080")
	env := getenv("APP_ENV", "development")
	devToken := getenv("DEV_AUTH_TOKEN", "dev-token")
	devUID := getenv("DEV_AUTH_UID", "local-user")

	return Config{
		Port:         port,
		Environment:  env,
		DevAuthToken: devToken,
		DevAuthUID:   devUID,
	}
}

func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
