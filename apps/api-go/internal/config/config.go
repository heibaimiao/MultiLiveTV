package config

import (
	"os"
	"strconv"
)

type Config struct {
	Port            string
	DatabaseURL     string
	JWTSecret       string
	SourcesPath     string
	WeightsPath     string
	CategoriesPath  string
	BPZ5BaseURL     string
	BPZ5HMACSecret  string
	AdminUsername   string
	AdminPassword   string
	AdminJWTSecret  string
	AdminCORSOrigin string
}

func Load() Config {
	jwtSecret := getEnv("JWT_SECRET", "dev-secret-change-me")
	adminJWT := getEnv("ADMIN_JWT_SECRET", jwtSecret)
	return Config{
		Port:            getEnv("PORT", "8080"),
		DatabaseURL:     getEnv("DATABASE_URL", ""),
		JWTSecret:       jwtSecret,
		SourcesPath:     getEnv("SOURCES_PATH", "config/sources.json"),
		WeightsPath:     getEnv("PLAY_LINE_WEIGHTS_PATH", "config/play-line-weights.json"),
		CategoriesPath:  getEnv("UNIFIED_CATEGORIES_PATH", "config/unified-categories.json"),
		BPZ5BaseURL:     getEnv("BPZ5_BASE_URL", "https://bpz5.com"),
		BPZ5HMACSecret:  getEnv("BPZ5_HMAC_SECRET", ""),
		AdminUsername:   getEnv("ADMIN_USERNAME", ""),
		AdminPassword:   getEnv("ADMIN_PASSWORD", ""),
		AdminJWTSecret:  adminJWT,
		AdminCORSOrigin: getEnv("ADMIN_CORS_ORIGIN", "http://localhost:3001"),
	}
}

func (c Config) AdminEnabled() bool {
	return c.AdminUsername != "" && c.AdminPassword != ""
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func ParseTypeID(value string) *int {
	if value == "" {
		return nil
	}
	id, err := strconv.Atoi(value)
	if err != nil || id <= 0 {
		return nil
	}
	return &id
}
