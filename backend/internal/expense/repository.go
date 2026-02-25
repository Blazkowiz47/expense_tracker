package expense

import (
	"context"
	"errors"
	"sync"
)

var ErrRepositoryNotFound = errors.New("expense not found")

// Repository abstracts data persistence for expenses.
type Repository interface {
	Create(ctx context.Context, expense Expense) (Expense, error)
	GetByID(ctx context.Context, id string) (Expense, error)
	Update(ctx context.Context, expense Expense) (Expense, error)
	Delete(ctx context.Context, id string) error
	ListByUser(ctx context.Context, uid string) ([]Expense, error)
}

// InMemoryRepository is a local-dev repository implementation.
type InMemoryRepository struct {
	mu       sync.RWMutex
	expenses map[string]Expense
}

func NewInMemoryRepository() *InMemoryRepository {
	return &InMemoryRepository{expenses: make(map[string]Expense)}
}

func (r *InMemoryRepository) Create(_ context.Context, expense Expense) (Expense, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.expenses[expense.ID] = expense
	return expense, nil
}

func (r *InMemoryRepository) GetByID(_ context.Context, id string) (Expense, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	expense, ok := r.expenses[id]
	if !ok {
		return Expense{}, ErrRepositoryNotFound
	}
	return expense, nil
}

func (r *InMemoryRepository) Update(_ context.Context, expense Expense) (Expense, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if _, ok := r.expenses[expense.ID]; !ok {
		return Expense{}, ErrRepositoryNotFound
	}
	r.expenses[expense.ID] = expense
	return expense, nil
}

func (r *InMemoryRepository) Delete(_ context.Context, id string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	if _, ok := r.expenses[id]; !ok {
		return ErrRepositoryNotFound
	}
	delete(r.expenses, id)
	return nil
}

func (r *InMemoryRepository) ListByUser(_ context.Context, uid string) ([]Expense, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	result := make([]Expense, 0)
	for _, e := range r.expenses {
		if e.UID == uid {
			result = append(result, e)
		}
	}
	return result, nil
}
