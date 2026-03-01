package recurring

import (
	"context"
	"slices"
	"sync"
)

type InMemoryStore struct {
	mu    sync.RWMutex
	items map[string][]Template
}

func NewInMemoryStore() *InMemoryStore {
	return &InMemoryStore{items: make(map[string][]Template)}
}

func (s *InMemoryStore) Create(_ context.Context, template Template) (Template, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	s.items[template.UID] = append(s.items[template.UID], template)
	return template, nil
}

func (s *InMemoryStore) ListByUser(_ context.Context, uid string) ([]Template, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	items := s.items[uid]
	out := make([]Template, len(items))
	copy(out, items)
	slices.SortFunc(out, func(a, b Template) int {
		if a.NextDueDate.Before(b.NextDueDate) {
			return -1
		}
		if a.NextDueDate.After(b.NextDueDate) {
			return 1
		}
		if a.CreatedAt.Before(b.CreatedAt) {
			return -1
		}
		if a.CreatedAt.After(b.CreatedAt) {
			return 1
		}
		return 0
	})
	return out, nil
}

func (s *InMemoryStore) Update(_ context.Context, template Template) (Template, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	items := s.items[template.UID]
	for index := range items {
		if items[index].ID == template.ID {
			items[index] = template
			s.items[template.UID] = items
			return template, nil
		}
	}
	return Template{}, ErrNotFound
}
