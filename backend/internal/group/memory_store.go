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
	group.DisplayData = computeDisplayData(group.MemberUIDs, nil)
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
	group.DisplayData = computeDisplayData(group.MemberUIDs, s.groupExpenses[groupID])
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
	group.DisplayData = computeDisplayData(group.MemberUIDs, s.groupExpenses[groupID])
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
	if expense.UpdatedAt.IsZero() {
		expense.UpdatedAt = expense.CreatedAt
	}
	if strings.TrimSpace(expense.UpdatedBy) == "" {
		expense.UpdatedBy = expense.CreatedBy
	}
	if strings.TrimSpace(expense.PaidBy) == "" {
		expense.PaidBy = expense.CreatedBy
	}
	if strings.TrimSpace(expense.SplitMode) == "" {
		expense.SplitMode = "equally"
	}
	expense.SplitWith = append([]string{}, expense.SplitWith...)
	expense.Attachments = append([]string{}, expense.Attachments...)
	group.UpdatedAt = time.Now().UTC()
	updatedExpenses := append(s.groupExpenses[group.ID], expense)
	group.DisplayData = computeDisplayData(group.MemberUIDs, updatedExpenses)
	s.groups[group.ID] = group
	s.groupExpenses[group.ID] = updatedExpenses
	return expense, nil
}

func (s *InMemoryStore) UpdateExpense(_ context.Context, expense GroupExpense) (GroupExpense, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	group, ok := s.groups[expense.GroupID]
	if !ok {
		return GroupExpense{}, ErrGroupNotFound
	}
	items := s.groupExpenses[expense.GroupID]
	for i := range items {
		if items[i].ID == expense.ID {
			expense.CreatedBy = items[i].CreatedBy
			expense.CreatedAt = items[i].CreatedAt
			if strings.TrimSpace(expense.PaidBy) == "" {
				expense.PaidBy = items[i].PaidBy
			}
			if strings.TrimSpace(expense.SplitMode) == "" {
				expense.SplitMode = items[i].SplitMode
			}
			if len(expense.SplitWith) == 0 {
				expense.SplitWith = items[i].SplitWith
			}
			expense.UpdatedAt = time.Now().UTC()
			if strings.TrimSpace(expense.UpdatedBy) == "" {
				expense.UpdatedBy = expense.CreatedBy
			}
			expense.SplitWith = append([]string{}, expense.SplitWith...)
			expense.Attachments = append([]string{}, expense.Attachments...)
			items[i] = expense
			s.groupExpenses[expense.GroupID] = items
			group.UpdatedAt = time.Now().UTC()
			group.DisplayData = computeDisplayData(group.MemberUIDs, items)
			s.groups[group.ID] = group
			return expense, nil
		}
	}
	return GroupExpense{}, ErrGroupNotFound
}

func (s *InMemoryStore) DeleteExpense(_ context.Context, groupID, expenseID string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, ok := s.groups[groupID]; !ok {
		return ErrGroupNotFound
	}
	items := s.groupExpenses[groupID]
	for i := range items {
		if items[i].ID != expenseID {
			continue
		}
		s.groupExpenses[groupID] = append(items[:i], items[i+1:]...)
		group := s.groups[groupID]
		group.UpdatedAt = time.Now().UTC()
		group.DisplayData = computeDisplayData(group.MemberUIDs, s.groupExpenses[groupID])
		s.groups[groupID] = group
		return nil
	}
	return ErrGroupNotFound
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
