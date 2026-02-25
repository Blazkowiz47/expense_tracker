package main

import (
	"log"
	"net/http"

	"expense_tracker_backend/internal/auth"
	"expense_tracker_backend/internal/config"
	"expense_tracker_backend/internal/expense"
	"expense_tracker_backend/internal/server"
)

func main() {
	cfg := config.Load()

	repo := expense.NewInMemoryRepository()
	service := expense.NewService(repo)
	handler := expense.NewHandler(service)
	verifier := auth.NewStaticVerifier(map[string]string{
		cfg.DevAuthToken: cfg.DevAuthUID,
	})

	router := server.NewRouter(verifier, handler)
	addr := ":" + cfg.Port

	log.Printf("backend listening on %s (env=%s)", addr, cfg.Environment)
	if err := http.ListenAndServe(addr, router); err != nil {
		log.Fatalf("server failed: %v", err)
	}
}
