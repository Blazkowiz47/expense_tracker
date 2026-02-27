package group

import (
	"context"
	"errors"
	"fmt"
	"slices"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"
	"google.golang.org/api/option"
)

const groupsCollection = "groups"

type FirestoreStore struct {
	client *firestore.Client
}

func NewFirestoreStore(ctx context.Context, projectID, credentialsFile string) (*FirestoreStore, error) {
	if strings.TrimSpace(projectID) == "" {
		return nil, errors.New("firebase project id is required for group store")
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

func (s *FirestoreStore) Create(ctx context.Context, group Group) (Group, error) {
	doc := s.client.Collection(groupsCollection).NewDoc()
	group.ID = doc.ID
	if _, err := doc.Set(ctx, toFirestoreGroup(group)); err != nil {
		return Group{}, fmt.Errorf("create group: %w", err)
	}
	return group, nil
}

func (s *FirestoreStore) ListByMember(ctx context.Context, uid string) ([]Group, error) {
	iter := s.client.Collection(groupsCollection).
		Where("member_uids", "array-contains", uid).
		Documents(ctx)
	defer iter.Stop()

	out := make([]Group, 0)
	for {
		doc, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return nil, fmt.Errorf("list groups: %w", err)
		}
		group, err := fromFirestoreGroup(doc)
		if err != nil {
			return nil, err
		}
		out = append(out, group)
	}

	return out, nil
}

func (s *FirestoreStore) Leave(ctx context.Context, groupID, uid string) (bool, error) {
	doc := s.client.Collection(groupsCollection).Doc(groupID)
	deleted := false
	err := s.client.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		snap, err := tx.Get(doc)
		if err != nil {
			return ErrGroupNotFound
		}
		group, err := fromFirestoreGroup(snap)
		if err != nil {
			return err
		}
		if !slices.Contains(group.MemberUIDs, uid) {
			return ErrNotMember
		}

		nextMembers := make([]string, 0, len(group.MemberUIDs))
		for _, memberUID := range group.MemberUIDs {
			if memberUID != uid {
				nextMembers = append(nextMembers, memberUID)
			}
		}
		if len(nextMembers) == 0 {
			deleted = true
			return tx.Delete(doc)
		}
		return tx.Set(doc, map[string]any{
			"member_uids":  nextMembers,
			"member_count": len(nextMembers),
			"updated_at":   time.Now().UTC(),
		}, firestore.MergeAll)
	})
	if err != nil {
		return false, err
	}
	return deleted, nil
}

type firestoreGroup struct {
	Name        string    `firestore:"name"`
	GroupType   string    `firestore:"group_type"`
	CreatedBy   string    `firestore:"created_by"`
	MemberUIDs  []string  `firestore:"member_uids"`
	MemberCount int       `firestore:"member_count"`
	CreatedAt   time.Time `firestore:"created_at"`
	UpdatedAt   time.Time `firestore:"updated_at"`
}

func toFirestoreGroup(group Group) firestoreGroup {
	return firestoreGroup{
		Name:        group.Name,
		GroupType:   string(group.GroupType),
		CreatedBy:   group.CreatedBy,
		MemberUIDs:  group.MemberUIDs,
		MemberCount: group.MemberCount,
		CreatedAt:   group.CreatedAt.UTC(),
		UpdatedAt:   group.UpdatedAt.UTC(),
	}
}

func fromFirestoreGroup(doc *firestore.DocumentSnapshot) (Group, error) {
	var raw firestoreGroup
	if err := doc.DataTo(&raw); err != nil {
		return Group{}, fmt.Errorf("decode group %s: %w", doc.Ref.ID, err)
	}
	return Group{
		ID:          doc.Ref.ID,
		Name:        raw.Name,
		GroupType:   normalizeGroupType(raw.GroupType),
		CreatedBy:   raw.CreatedBy,
		MemberUIDs:  raw.MemberUIDs,
		MemberCount: raw.MemberCount,
		CreatedAt:   raw.CreatedAt.UTC(),
		UpdatedAt:   raw.UpdatedAt.UTC(),
	}, nil
}
