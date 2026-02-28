package group

import (
	"context"
	"errors"
	"fmt"
	"slices"
	"sort"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"
	"google.golang.org/api/option"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

const groupsCollection = "groups"
const groupExpensesSubcollection = "expenses"
const usersCollection = "users"

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

func (s *FirestoreStore) ListMembers(ctx context.Context, groupID string) ([]GroupMember, error) {
	group, err := s.GetByID(ctx, groupID)
	if err != nil {
		return nil, err
	}

	out := make([]GroupMember, 0, len(group.MemberUIDs))
	for _, uid := range group.MemberUIDs {
		doc, err := s.client.Collection(usersCollection).Doc(uid).Get(ctx)
		if err != nil {
			out = append(out, GroupMember{UID: uid, DisplayName: uid})
			continue
		}
		data := doc.Data()
		displayName, _ := data["display_name"].(string)
		email, _ := data["email"].(string)
		phone := firstNonEmptyString(
			stringFrom(data["phone"]),
			stringFrom(data["phone_e164"]),
			stringFrom(data["primary_phone"]),
		)
		if strings.TrimSpace(displayName) == "" {
			displayName = firstNonEmptyString(email, phone, uid)
		}
		out = append(out, GroupMember{
			UID:         uid,
			DisplayName: strings.TrimSpace(displayName),
			Email:       strings.TrimSpace(email),
			Phone:       phone,
		})
	}
	return out, nil
}

func (s *FirestoreStore) GetByID(ctx context.Context, id string) (Group, error) {
	doc, err := s.client.Collection(groupsCollection).Doc(id).Get(ctx)
	if err != nil {
		if status.Code(err) == codes.NotFound {
			return Group{}, ErrGroupNotFound
		}
		return Group{}, fmt.Errorf("get group: %w", err)
	}
	return fromFirestoreGroup(doc)
}

func (s *FirestoreStore) AddMember(ctx context.Context, groupID, memberUID string) (Group, error) {
	doc := s.client.Collection(groupsCollection).Doc(groupID)
	if err := s.client.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		snap, err := tx.Get(doc)
		if err != nil {
			return ErrGroupNotFound
		}
		group, err := fromFirestoreGroup(snap)
		if err != nil {
			return err
		}
		if slices.Contains(group.MemberUIDs, memberUID) {
			return nil
		}
		nextMembers := append([]string{}, group.MemberUIDs...)
		nextMembers = append(nextMembers, memberUID)
		sort.Strings(nextMembers)
		return tx.Set(doc, map[string]any{
			"member_uids":  nextMembers,
			"member_count": len(nextMembers),
			"updated_at":   time.Now().UTC(),
		}, firestore.MergeAll)
	}); err != nil {
		return Group{}, err
	}
	return s.GetByID(ctx, groupID)
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

func (s *FirestoreStore) CreateExpense(ctx context.Context, expense GroupExpense) (GroupExpense, error) {
	groupDoc := s.client.Collection(groupsCollection).Doc(expense.GroupID)
	if _, err := groupDoc.Get(ctx); err != nil {
		return GroupExpense{}, ErrGroupNotFound
	}

	doc := groupDoc.Collection(groupExpensesSubcollection).NewDoc()
	expense.ID = doc.ID
	if expense.CreatedAt.IsZero() {
		expense.CreatedAt = time.Now().UTC()
	}
	if _, err := doc.Set(ctx, map[string]any{
		"group_id":    expense.GroupID,
		"created_by":  expense.CreatedBy,
		"amount":      expense.Amount,
		"description": expense.Description,
		"attachments": expense.Attachments,
		"date":        expense.Date.UTC(),
		"created_at":  expense.CreatedAt.UTC(),
	}); err != nil {
		return GroupExpense{}, fmt.Errorf("create group expense: %w", err)
	}
	return expense, nil
}

func (s *FirestoreStore) ListExpenses(ctx context.Context, groupID string) ([]GroupExpense, error) {
	groupDoc := s.client.Collection(groupsCollection).Doc(groupID)
	if _, err := groupDoc.Get(ctx); err != nil {
		return nil, ErrGroupNotFound
	}
	docs, err := groupDoc.Collection(groupExpensesSubcollection).Documents(ctx).GetAll()
	if err != nil {
		return nil, fmt.Errorf("list group expenses: %w", err)
	}
	out := make([]GroupExpense, 0, len(docs))
	for _, doc := range docs {
		data := doc.Data()
		amount, _ := data["amount"].(float64)
		if amount == 0 {
			if n, ok := data["amount"].(int64); ok {
				amount = float64(n)
			}
		}
		description, _ := data["description"].(string)
		attachments := stringSliceFrom(data["attachments"])
		createdBy, _ := data["created_by"].(string)
		date, _ := data["date"].(time.Time)
		createdAt, _ := data["created_at"].(time.Time)
		out = append(out, GroupExpense{
			ID:          doc.Ref.ID,
			GroupID:     groupID,
			CreatedBy:   createdBy,
			Amount:      amount,
			Description: description,
			Attachments: attachments,
			Date:        date.UTC(),
			CreatedAt:   createdAt.UTC(),
		})
	}
	sort.Slice(out, func(i, j int) bool {
		return out[i].Date.After(out[j].Date)
	})
	return out, nil
}

func (s *FirestoreStore) UpdateExpense(ctx context.Context, expense GroupExpense) (GroupExpense, error) {
	groupDoc := s.client.Collection(groupsCollection).Doc(expense.GroupID)
	if _, err := groupDoc.Get(ctx); err != nil {
		return GroupExpense{}, ErrGroupNotFound
	}
	expenseDoc := groupDoc.Collection(groupExpensesSubcollection).Doc(expense.ID)
	snap, err := expenseDoc.Get(ctx)
	if err != nil {
		if status.Code(err) == codes.NotFound {
			return GroupExpense{}, ErrGroupNotFound
		}
		return GroupExpense{}, fmt.Errorf("get group expense: %w", err)
	}
	data := snap.Data()
	createdBy, _ := data["created_by"].(string)
	createdAt, _ := data["created_at"].(time.Time)
	if createdBy == "" {
		createdBy = expense.CreatedBy
	}
	if createdAt.IsZero() {
		createdAt = expense.CreatedAt
	}
	if _, err := expenseDoc.Set(ctx, map[string]any{
		"group_id":    expense.GroupID,
		"created_by":  createdBy,
		"amount":      expense.Amount,
		"description": expense.Description,
		"attachments": expense.Attachments,
		"date":        expense.Date.UTC(),
		"created_at":  createdAt.UTC(),
	}, firestore.MergeAll); err != nil {
		return GroupExpense{}, fmt.Errorf("update group expense: %w", err)
	}
	return GroupExpense{
		ID:          expense.ID,
		GroupID:     expense.GroupID,
		CreatedBy:   createdBy,
		Amount:      expense.Amount,
		Description: expense.Description,
		Attachments: append([]string{}, expense.Attachments...),
		Date:        expense.Date.UTC(),
		CreatedAt:   createdAt.UTC(),
	}, nil
}

func stringSliceFrom(value any) []string {
	items, ok := value.([]any)
	if !ok {
		if direct, ok := value.([]string); ok {
			return append([]string{}, direct...)
		}
		return nil
	}
	out := make([]string, 0, len(items))
	for _, item := range items {
		if text, ok := item.(string); ok && strings.TrimSpace(text) != "" {
			out = append(out, strings.TrimSpace(text))
		}
	}
	if len(out) == 0 {
		return nil
	}
	return out
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

func stringFrom(value any) string {
	v, _ := value.(string)
	return strings.TrimSpace(v)
}

func firstNonEmptyString(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return strings.TrimSpace(value)
		}
	}
	return ""
}
