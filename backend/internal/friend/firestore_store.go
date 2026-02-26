package friend

import (
	"context"
	"errors"
	"fmt"
	"sort"
	"strings"

	"cloud.google.com/go/firestore"
	"google.golang.org/api/option"
)

const (
	usersCollection       = "users"
	friendshipsCollection = "friendships"
)

type FirestoreStore struct {
	client *firestore.Client
}

func NewFirestoreStore(ctx context.Context, projectID, credentialsFile string) (*FirestoreStore, error) {
	if strings.TrimSpace(projectID) == "" {
		return nil, errors.New("firebase project id is required for friend store")
	}

	var (
		client *firestore.Client
		err    error
	)
	if strings.TrimSpace(credentialsFile) != "" {
		client, err = firestore.NewClient(ctx, projectID, option.WithCredentialsFile(credentialsFile))
	} else {
		client, err = firestore.NewClient(ctx, projectID)
	}
	if err != nil {
		return nil, fmt.Errorf("create firestore client: %w", err)
	}
	return &FirestoreStore{client: client}, nil
}

func (s *FirestoreStore) Close() error {
	return s.client.Close()
}

func (s *FirestoreStore) ResolveByEmailOrPhone(ctx context.Context, query string) (ResolveResult, error) {
	normalized := normalizeQuery(query)
	if normalized == "" {
		return ResolveResult{Exists: false}, nil
	}

	// Email lookup
	if strings.Contains(normalized, "@") {
		if uid, ok, err := s.lookupSingle(ctx, usersCollection, "email_normalized", normalized); err != nil {
			return ResolveResult{}, err
		} else if ok {
			return ResolveResult{Exists: true, UID: uid}, nil
		}
		if uid, ok, err := s.lookupSingle(ctx, usersCollection, "email", normalized); err != nil {
			return ResolveResult{}, err
		} else if ok {
			return ResolveResult{Exists: true, UID: uid}, nil
		}
		if uid, ok, err := s.lookupArray(ctx, usersCollection, "emails", normalized); err != nil {
			return ResolveResult{}, err
		} else if ok {
			return ResolveResult{Exists: true, UID: uid}, nil
		}
		return ResolveResult{Exists: false}, nil
	}

	// Phone lookup
	for _, field := range []string{"phone", "phone_e164", "primary_phone"} {
		if uid, ok, err := s.lookupSingle(ctx, usersCollection, field, normalized); err != nil {
			return ResolveResult{}, err
		} else if ok {
			return ResolveResult{Exists: true, UID: uid}, nil
		}
	}
	if uid, ok, err := s.lookupArray(ctx, usersCollection, "phones", normalized); err != nil {
		return ResolveResult{}, err
	} else if ok {
		return ResolveResult{Exists: true, UID: uid}, nil
	}

	return ResolveResult{Exists: false}, nil
}

func (s *FirestoreStore) AddFriendship(ctx context.Context, uid, friendUID string) error {
	pair := []string{uid, friendUID}
	sort.Strings(pair)
	docID := pair[0] + "_" + pair[1]

	docRef := s.client.Collection(friendshipsCollection).Doc(docID)
	return s.client.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		snap, err := tx.Get(docRef)
		now := firestore.ServerTimestamp
		data := map[string]any{
			"uidA":       pair[0],
			"uidB":       pair[1],
			"uids":       []string{pair[0], pair[1]},
			"updated_at": now,
		}
		if err != nil {
			data["created_at"] = now
			return tx.Set(docRef, data)
		}
		if snap.Exists() {
			return tx.Set(docRef, data, firestore.MergeAll)
		}
		data["created_at"] = now
		return tx.Set(docRef, data)
	})
}

func (s *FirestoreStore) ListFriends(ctx context.Context, uid string) ([]Friend, error) {
	docs, err := s.client.Collection(friendshipsCollection).
		Where("uids", "array-contains", uid).
		Documents(ctx).
		GetAll()
	if err != nil {
		return nil, fmt.Errorf("list friendships: %w", err)
	}

	friendIDs := make([]string, 0, len(docs))
	for _, doc := range docs {
		data := doc.Data()
		uidA, _ := data["uidA"].(string)
		uidB, _ := data["uidB"].(string)
		switch uid {
		case uidA:
			friendIDs = append(friendIDs, uidB)
		case uidB:
			friendIDs = append(friendIDs, uidA)
		}
	}

	friends := make([]Friend, 0, len(friendIDs))
	for _, friendUID := range friendIDs {
		userDoc, docErr := s.client.Collection(usersCollection).Doc(friendUID).Get(ctx)
		if docErr != nil {
			continue
		}
		data := userDoc.Data()
		displayName, _ := data["display_name"].(string)
		email, _ := data["email"].(string)
		friends = append(friends, Friend{
			UID:         friendUID,
			DisplayName: strings.TrimSpace(displayName),
			Email:       strings.TrimSpace(email),
		})
	}

	sort.Slice(friends, func(i, j int) bool {
		left := friends[i].DisplayName
		if left == "" {
			left = friends[i].Email
		}
		right := friends[j].DisplayName
		if right == "" {
			right = friends[j].Email
		}
		return strings.ToLower(left) < strings.ToLower(right)
	})

	return friends, nil
}

func (s *FirestoreStore) lookupSingle(ctx context.Context, collection, field, value string) (string, bool, error) {
	docs, err := s.client.Collection(collection).Where(field, "==", value).Limit(1).Documents(ctx).GetAll()
	if err != nil {
		return "", false, fmt.Errorf("lookup field %s: %w", field, err)
	}
	if len(docs) == 0 {
		return "", false, nil
	}
	return docs[0].Ref.ID, true, nil
}

func (s *FirestoreStore) lookupArray(ctx context.Context, collection, field, value string) (string, bool, error) {
	docs, err := s.client.Collection(collection).Where(field, "array-contains", value).Limit(1).Documents(ctx).GetAll()
	if err != nil {
		return "", false, fmt.Errorf("lookup array field %s: %w", field, err)
	}
	if len(docs) == 0 {
		return "", false, nil
	}
	return docs[0].Ref.ID, true, nil
}
