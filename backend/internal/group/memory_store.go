package group

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"sort"
	"strings"
	"sync"
	"time"
)

type InMemoryStore struct {
	mu            sync.RWMutex
	groups        map[string]Group
	groupExpenses map[string][]GroupExpense
}

func NewInMemoryStore() *InMemoryStore {
	return &InMemoryStore{
		groups:        make(map[string]Group),
		groupExpenses: make(map[string][]GroupExpense),
	}
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

func (s *InMemoryStore) GetByID(_ context.Context, id string) (Group, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	group, ok := s.groups[id]
	if !ok {
		return Group{}, ErrGroupNotFound
	}
	return group, nil
}

func (s *InMemoryStore) ListMembers(_ context.Context, groupID string) ([]GroupMember, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	group, ok := s.groups[groupID]
	if !ok {
		return nil, ErrGroupNotFound
	}
	out := make([]GroupMember, 0, len(group.MemberUIDs))
	for _, uid := range group.MemberUIDs {
		out = append(out, GroupMember{
			UID:         uid,
			DisplayName: uid,
		})
	}
	return out, nil
}

func (s *InMemoryStore) AddMember(_ context.Context, groupID, memberUID string) (Group, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	group, ok := s.groups[groupID]
	if !ok {
		return Group{}, ErrGroupNotFound
	}
	for _, uid := range group.MemberUIDs {
		if uid == memberUID {
			return group, nil
		}
	}
	group.MemberUIDs = append(group.MemberUIDs, memberUID)
	group.MemberCount = len(group.MemberUIDs)
	group.UpdatedAt = time.Now().UTC()
	s.groups[groupID] = group
	return group, nil
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

func (s *InMemoryStore) CreateExpense(_ context.Context, expense GroupExpense) (GroupExpense, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	group, ok := s.groups[expense.GroupID]
	if !ok {
		return GroupExpense{}, ErrGroupNotFound
	}
	if expense.ID == "" {
		expense.ID = generateID()
	}
	if expense.CreatedAt.IsZero() {
		expense.CreatedAt = time.Now().UTC()
	}
	group.UpdatedAt = time.Now().UTC()
	s.groups[group.ID] = group
	s.groupExpenses[group.ID] = append(s.groupExpenses[group.ID], expense)
	return expense, nil
}

func (s *InMemoryStore) ListExpenses(_ context.Context, groupID string) ([]GroupExpense, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	if _, ok := s.groups[groupID]; !ok {
		return nil, ErrGroupNotFound
	}
	items := append([]GroupExpense{}, s.groupExpenses[groupID]...)
	sort.Slice(items, func(i, j int) bool {
		return items[i].Date.After(items[j].Date)
	})
	return items, nil
}

func generateID() string {
	var b [12]byte
	if _, err := rand.Read(b[:]); err == nil {
		return hex.EncodeToString(b[:])
	}
	return strings.ReplaceAll(time.Now().UTC().Format("20060102150405.000000"), ".", "")
}
