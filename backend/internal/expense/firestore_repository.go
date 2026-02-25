package expense

import (
	"context"
	"errors"
	"fmt"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/api/option"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

const expensesCollection = "expenses"

type firestoreExpense struct {
	UID         string    `firestore:"uid"`
	Amount      float64   `firestore:"amount"`
	Category    string    `firestore:"category"`
	Description string    `firestore:"description"`
	Date        time.Time `firestore:"date"`
	CreatedAt   time.Time `firestore:"createdAt"`
	UpdatedAt   time.Time `firestore:"updatedAt"`
}

// FirestoreRepository persists expenses into Firestore collection "expenses".
type FirestoreRepository struct {
	client *firestore.Client
}

func NewFirestoreRepository(ctx context.Context, projectID, credentialsFile string) (*FirestoreRepository, error) {
	if projectID == "" {
		return nil, errors.New("firebase project id is required for firestore repository")
	}

	var (
		client *firestore.Client
		err    error
	)
	if credentialsFile != "" {
		client, err = firestore.NewClient(ctx, projectID, option.WithCredentialsFile(credentialsFile))
	} else {
		client, err = firestore.NewClient(ctx, projectID)
	}
	if err != nil {
		return nil, fmt.Errorf("create firestore client: %w", err)
	}

	return &FirestoreRepository{client: client}, nil
}

func (r *FirestoreRepository) Close() error {
	return r.client.Close()
}

func (r *FirestoreRepository) Create(ctx context.Context, expense Expense) (Expense, error) {
	doc := r.client.Collection(expensesCollection).Doc(expense.ID)
	if _, err := doc.Set(ctx, toFirestoreExpense(expense)); err != nil {
		return Expense{}, fmt.Errorf("create expense in firestore: %w", err)
	}
	return expense, nil
}

func (r *FirestoreRepository) GetByID(ctx context.Context, id string) (Expense, error) {
	doc, err := r.client.Collection(expensesCollection).Doc(id).Get(ctx)
	if err != nil {
		if isNotFound(err) {
			return Expense{}, ErrRepositoryNotFound
		}
		return Expense{}, fmt.Errorf("get expense by id from firestore: %w", err)
	}
	return fromFirestoreExpense(doc.Ref.ID, doc)
}

func (r *FirestoreRepository) Update(ctx context.Context, expense Expense) (Expense, error) {
	doc := r.client.Collection(expensesCollection).Doc(expense.ID)
	if _, err := doc.Get(ctx); err != nil {
		if isNotFound(err) {
			return Expense{}, ErrRepositoryNotFound
		}
		return Expense{}, fmt.Errorf("load expense before update: %w", err)
	}
	if _, err := doc.Set(ctx, toFirestoreExpense(expense)); err != nil {
		return Expense{}, fmt.Errorf("update expense in firestore: %w", err)
	}
	return expense, nil
}

func (r *FirestoreRepository) Delete(ctx context.Context, id string) error {
	doc := r.client.Collection(expensesCollection).Doc(id)
	if _, err := doc.Get(ctx); err != nil {
		if isNotFound(err) {
			return ErrRepositoryNotFound
		}
		return fmt.Errorf("load expense before delete: %w", err)
	}
	if _, err := doc.Delete(ctx); err != nil {
		return fmt.Errorf("delete expense in firestore: %w", err)
	}
	return nil
}

func (r *FirestoreRepository) ListByUser(ctx context.Context, uid string) ([]Expense, error) {
	query := r.client.Collection(expensesCollection).Where("uid", "==", uid)
	docs, err := query.Documents(ctx).GetAll()
	if err != nil {
		return nil, fmt.Errorf("list expenses by user from firestore: %w", err)
	}

	result := make([]Expense, 0, len(docs))
	for _, doc := range docs {
		expense, convErr := fromFirestoreExpense(doc.Ref.ID, doc)
		if convErr != nil {
			return nil, convErr
		}
		result = append(result, expense)
	}
	return result, nil
}

func toFirestoreExpense(expense Expense) firestoreExpense {
	return firestoreExpense{
		UID:         expense.UID,
		Amount:      expense.Amount,
		Category:    expense.Category,
		Description: expense.Description,
		Date:        expense.Date,
		CreatedAt:   expense.CreatedAt,
		UpdatedAt:   expense.UpdatedAt,
	}
}

func fromFirestoreExpense(id string, doc *firestore.DocumentSnapshot) (Expense, error) {
	var row firestoreExpense
	if err := doc.DataTo(&row); err != nil {
		return Expense{}, fmt.Errorf("decode firestore expense %s: %w", id, err)
	}
	return Expense{
		ID:          id,
		UID:         row.UID,
		Amount:      row.Amount,
		Category:    row.Category,
		Description: row.Description,
		Date:        row.Date,
		CreatedAt:   row.CreatedAt,
		UpdatedAt:   row.UpdatedAt,
	}, nil
}

func isNotFound(err error) bool {
	if status.Code(err) == codes.NotFound {
		return true
	}
	return false
}
