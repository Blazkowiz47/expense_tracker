package group

import (
	"context"
	"sort"
	"strings"
	"sync"
)

type InMemoryStore struct {
	mu     sync.RWMutex
	groups map[string]Group
}

func NewInMemoryStore() *InMemoryStore {
	return &InMemoryStore{groups: make(map[string]Group)}
}

func (s *InMemoryStore) Create(_ context.Context, group Group) (Group, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.groups[group.ID] = group
	return group, nil
}

func (s *InMemoryStore) ListByMember(_ context.Context, uid string) ([]Group, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	out := make([]Group, 0)
	for _, group := range s.groups {
		for _, memberUID := range group.MemberUIDs {
			if memberUID == uid {
				out = append(out, group)
				break
			}
		}
	}
	sort.Slice(out, func(i, j int) bool {
		return strings.ToLower(out[i].Name) < strings.ToLower(out[j].Name)
	})
	return out, nil
}
