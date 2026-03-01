package main

import (
	"context"
	"log"
	"net/http"

	"expense_tracker_backend/internal/auth"
	"expense_tracker_backend/internal/config"
	"expense_tracker_backend/internal/expense"
	"expense_tracker_backend/internal/friend"
	"expense_tracker_backend/internal/group"
	"expense_tracker_backend/internal/recurring"
	"expense_tracker_backend/internal/server"
)

func main() {
	cfg := config.Load()

	var (
		repo        expense.Repository = expense.NewInMemoryRepository()
		repoBackend                    = "in-memory"
	)
	if cfg.FirebaseProjectID != "" {
		firestoreRepo, err := expense.NewFirestoreRepository(
			context.Background(),
			cfg.FirebaseProjectID,
			cfg.FirebaseCredentialsFile,
		)
		if err != nil {
			log.Fatalf("firestore repository initialization failed: %v", err)
		}
		defer firestoreRepo.Close()
		repo = firestoreRepo
		repoBackend = "firestore"
	}

	service := expense.NewService(repo)
	handler := expense.NewHandler(service)

	var (
		friendStore   friend.Store = friend.NewInMemoryStore()
		friendBackend              = "in-memory"
	)
	if cfg.FirebaseProjectID != "" {
		firestoreFriendStore, err := friend.NewFirestoreStore(
			context.Background(),
			cfg.FirebaseProjectID,
			cfg.FirebaseCredentialsFile,
		)
		if err != nil {
			log.Fatalf("friend firestore store initialization failed: %v", err)
		}
		defer firestoreFriendStore.Close()
		friendStore = firestoreFriendStore
		friendBackend = "firestore"
	}
	friendHandler := friend.NewHandler(friendStore)

	var (
		groupStore   group.Store = group.NewInMemoryStore()
		groupBackend             = "in-memory"
	)
	if cfg.FirebaseProjectID != "" {
		firestoreGroupStore, err := group.NewFirestoreStore(
			context.Background(),
			cfg.FirebaseProjectID,
			cfg.FirebaseCredentialsFile,
		)
		if err != nil {
			log.Fatalf("group firestore store initialization failed: %v", err)
		}
		defer firestoreGroupStore.Close()
		groupStore = firestoreGroupStore
		groupBackend = "firestore"
	}
	var attachmentUploader group.AttachmentUploader
	if cfg.FirebaseProjectID != "" {
		firebaseUploader, err := group.NewFirebaseAttachmentUploader(
			context.Background(),
			cfg.FirebaseProjectID,
			cfg.FirebaseCredentialsFile,
			cfg.FirebaseStorageBucket,
		)
		if err != nil {
			log.Fatalf("group firebase storage uploader initialization failed: %v", err)
		}
		defer firebaseUploader.Close()
		attachmentUploader = firebaseUploader
	}
	groupHandler := group.NewHandler(groupStore, friendStore, attachmentUploader)
	recurringHandler := recurring.NewHandler(recurring.NewInMemoryStore())

	var verifier auth.Verifier
	switch cfg.AuthMode {
	case "firebase":
		firebaseVerifier, err := auth.NewFirebaseVerifier(context.Background(), auth.FirebaseVerifierConfig{
			ProjectID:       cfg.FirebaseProjectID,
			CredentialsFile: cfg.FirebaseCredentialsFile,
		})
		if err != nil {
			log.Fatalf("firebase auth initialization failed: %v", err)
		}
		verifier = firebaseVerifier
	case "dev":
		verifier = auth.NewStaticVerifier(map[string]string{
			cfg.DevAuthToken: cfg.DevAuthUID,
		})
	default:
		log.Fatalf("unsupported AUTH_MODE %q (allowed: dev, firebase)", cfg.AuthMode)
	}

	router := server.NewRouter(verifier, handler, friendHandler, groupHandler, recurringHandler)
	addr := ":" + cfg.Port

	log.Printf(
		"backend listening on %s (env=%s auth_mode=%s expense_repo=%s friend_repo=%s group_repo=%s)",
		addr,
		cfg.Environment,
		cfg.AuthMode,
		repoBackend,
		friendBackend,
		groupBackend,
	)
	if err := http.ListenAndServe(addr, router); err != nil {
		log.Fatalf("server failed: %v", err)
	}
}
