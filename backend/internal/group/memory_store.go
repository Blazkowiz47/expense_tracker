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

func (s *InMemoryStore) Leave(_ context.Context, groupID, uid string) (bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	group, ok := s.groups[groupID]
	if !ok {
		return false, ErrGroupNotFound
	}

	nextMembers := make([]string, 0, len(group.MemberUIDs))
	wasMember := false
	for _, memberUID := range group.MemberUIDs {
		if memberUID == uid {
			wasMember = true
			continue
		}
		nextMembers = append(nextMembers, memberUID)
	}
	if !wasMember {
		return false, ErrNotMember
	}
	if len(nextMembers) == 0 {
		delete(s.groups, groupID)
		return true, nil
	}

	group.MemberUIDs = nextMembers
	group.MemberCount = len(nextMembers)
	s.groups[groupID] = group
	return false, nil
}
