package friend

import (
	"context"
	"sort"
	"strings"
)

type InMemoryStore struct {
	usersByUID map[string]Friend
	byEmail    map[string]string
	byPhone    map[string]string
	links      map[string]struct{}
}

func NewInMemoryStore() *InMemoryStore {
	return &InMemoryStore{
		usersByUID: map[string]Friend{},
		byEmail:    map[string]string{},
		byPhone:    map[string]string{},
		links:      map[string]struct{}{},
	}
}

func (s *InMemoryStore) ResolveByEmailOrPhone(_ context.Context, query string) (ResolveResult, error) {
	normalized := normalizeQuery(query)
	if normalized == "" {
		return ResolveResult{Exists: false}, nil
	}
	if strings.Contains(normalized, "@") {
		if uid, ok := s.byEmail[normalized]; ok {
			return ResolveResult{Exists: true, UID: uid}, nil
		}
		return ResolveResult{Exists: false}, nil
	}
	if uid, ok := s.byPhone[normalized]; ok {
		return ResolveResult{Exists: true, UID: uid}, nil
	}
	return ResolveResult{Exists: false}, nil
}

func (s *InMemoryStore) AddFriendship(_ context.Context, uid, friendUID string) error {
	pair := []string{uid, friendUID}
	sort.Strings(pair)
	s.links[pair[0]+"_"+pair[1]] = struct{}{}
	return nil
}

func (s *InMemoryStore) RemoveFriendship(_ context.Context, uid, friendUID string) error {
	pair := []string{uid, friendUID}
	sort.Strings(pair)
	delete(s.links, pair[0]+"_"+pair[1])
	return nil
}

func (s *InMemoryStore) ListFriends(_ context.Context, uid string) ([]Friend, error) {
	result := make([]Friend, 0)
	for link := range s.links {
		parts := strings.SplitN(link, "_", 2)
		if len(parts) != 2 {
			continue
		}
		var friendUID string
		switch uid {
		case parts[0]:
			friendUID = parts[1]
		case parts[1]:
			friendUID = parts[0]
		default:
			continue
		}
		if friend, ok := s.usersByUID[friendUID]; ok {
			result = append(result, friend)
		}
	}
	return result, nil
}
