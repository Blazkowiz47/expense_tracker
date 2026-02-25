package expense

import (
	"context"
	"errors"
	"fmt"
	"sort"
	"strings"
	"sync/atomic"
	"time"
)

var (
	ErrInvalidInput = errors.New("invalid input")
	ErrNotFound     = errors.New("not found")
	ErrForbidden    = errors.New("forbidden")
)

type idGenerator func() string
type nowFn func() time.Time

// Service provides expense business operations.
type Service struct {
	repo        Repository
	idGenerator idGenerator
	now         nowFn
}

var idCounter atomic.Uint64

func defaultIDGenerator() string {
	return fmt.Sprintf("exp_%d", idCounter.Add(1))
}

func defaultNow() time.Time {
	return time.Now().UTC()
}

func NewService(repo Repository) *Service {
	return &Service{
		repo:        repo,
		idGenerator: defaultIDGenerator,
		now:         defaultNow,
	}
}

func (s *Service) Create(ctx context.Context, uid string, input CreateExpenseInput) (Expense, error) {
	if strings.TrimSpace(uid) == "" {
		return Expense{}, fmt.Errorf("uid is required: %w", ErrInvalidInput)
	}
	if err := validateInput(input.Amount, input.Category, input.Date); err != nil {
		return Expense{}, err
	}

	now := s.now()
	expense := Expense{
		ID:          s.idGenerator(),
		UID:         uid,
		Amount:      input.Amount,
		Category:    strings.TrimSpace(input.Category),
		Description: strings.TrimSpace(input.Description),
		Date:        input.Date.UTC(),
		CreatedAt:   now,
		UpdatedAt:   now,
	}
	return s.repo.Create(ctx, expense)
}

func (s *Service) List(ctx context.Context, uid string, filter ListFilter) ([]Expense, error) {
	if strings.TrimSpace(uid) == "" {
		return nil, fmt.Errorf("uid is required: %w", ErrInvalidInput)
	}
	if filter.From != nil && filter.To != nil && filter.From.After(*filter.To) {
		return nil, fmt.Errorf("from cannot be after to: %w", ErrInvalidInput)
	}

	items, err := s.repo.ListByUser(ctx, uid)
	if err != nil {
		return nil, err
	}

	filtered := make([]Expense, 0, len(items))
	category := strings.TrimSpace(filter.Category)
	for _, e := range items {
		if category != "" && !strings.EqualFold(e.Category, category) {
			continue
		}
		if filter.From != nil && e.Date.Before(filter.From.UTC()) {
			continue
		}
		if filter.To != nil && e.Date.After(filter.To.UTC()) {
			continue
		}
		filtered = append(filtered, e)
	}

	sort.Slice(filtered, func(i, j int) bool {
		if filtered[i].Date.Equal(filtered[j].Date) {
			if filtered[i].CreatedAt.Equal(filtered[j].CreatedAt) {
				return filtered[i].ID > filtered[j].ID
			}
			return filtered[i].CreatedAt.After(filtered[j].CreatedAt)
		}
		return filtered[i].Date.After(filtered[j].Date)
	})

	page, limit := normalizePagination(filter.Page, filter.Limit)
	start := (page - 1) * limit
	if start >= len(filtered) {
		return []Expense{}, nil
	}
	end := start + limit
	if end > len(filtered) {
		end = len(filtered)
	}

	result := make([]Expense, end-start)
	copy(result, filtered[start:end])
	return result, nil
}

func (s *Service) Update(ctx context.Context, uid, id string, input UpdateExpenseInput) (Expense, error) {
	if strings.TrimSpace(id) == "" {
		return Expense{}, fmt.Errorf("id is required: %w", ErrInvalidInput)
	}
	if strings.TrimSpace(uid) == "" {
		return Expense{}, fmt.Errorf("uid is required: %w", ErrInvalidInput)
	}
	if err := validateInput(input.Amount, input.Category, input.Date); err != nil {
		return Expense{}, err
	}

	existing, err := s.repo.GetByID(ctx, id)
	if err != nil {
		if errors.Is(err, ErrRepositoryNotFound) {
			return Expense{}, ErrNotFound
		}
		return Expense{}, err
	}
	if existing.UID != uid {
		return Expense{}, ErrForbidden
	}

	existing.Amount = input.Amount
	existing.Category = strings.TrimSpace(input.Category)
	existing.Description = strings.TrimSpace(input.Description)
	existing.Date = input.Date.UTC()
	existing.UpdatedAt = s.now()

	updated, err := s.repo.Update(ctx, existing)
	if err != nil {
		if errors.Is(err, ErrRepositoryNotFound) {
			return Expense{}, ErrNotFound
		}
		return Expense{}, err
	}
	return updated, nil
}

func (s *Service) Delete(ctx context.Context, uid, id string) error {
	if strings.TrimSpace(id) == "" {
		return fmt.Errorf("id is required: %w", ErrInvalidInput)
	}
	if strings.TrimSpace(uid) == "" {
		return fmt.Errorf("uid is required: %w", ErrInvalidInput)
	}

	existing, err := s.repo.GetByID(ctx, id)
	if err != nil {
		if errors.Is(err, ErrRepositoryNotFound) {
			return ErrNotFound
		}
		return err
	}
	if existing.UID != uid {
		return ErrForbidden
	}
	if err := s.repo.Delete(ctx, id); err != nil {
		if errors.Is(err, ErrRepositoryNotFound) {
			return ErrNotFound
		}
		return err
	}
	return nil
}

func (s *Service) Analytics(ctx context.Context, uid string, from, to *time.Time) (Analytics, error) {
	if strings.TrimSpace(uid) == "" {
		return Analytics{}, fmt.Errorf("uid is required: %w", ErrInvalidInput)
	}
	items, err := s.repo.ListByUser(ctx, uid)
	if err != nil {
		return Analytics{}, err
	}

	result := Analytics{
		ByCategory: make(map[string]float64),
		ByMonth:    make(map[string]float64),
	}

	for _, e := range items {
		if from != nil && e.Date.Before(from.UTC()) {
			continue
		}
		if to != nil && e.Date.After(to.UTC()) {
			continue
		}
		result.TotalAmount += e.Amount
		result.ByCategory[e.Category] += e.Amount
		result.ByMonth[e.Date.UTC().Format("2006-01")] += e.Amount
	}

	return result, nil
}

func validateInput(amount float64, category string, date time.Time) error {
	if amount <= 0 {
		return fmt.Errorf("amount must be > 0: %w", ErrInvalidInput)
	}
	if strings.TrimSpace(category) == "" {
		return fmt.Errorf("category is required: %w", ErrInvalidInput)
	}
	if date.IsZero() {
		return fmt.Errorf("date is required: %w", ErrInvalidInput)
	}
	return nil
}

func normalizePagination(page, limit int) (int, int) {
	if page <= 0 {
		page = 1
	}
	if limit <= 0 {
		limit = 20
	}
	if limit > 100 {
		limit = 100
	}
	return page, limit
}
