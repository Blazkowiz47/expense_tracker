package group

import (
	"context"
	"errors"
)

var (
	ErrGroupNotFound = errors.New("group not found")
	ErrNotMember     = errors.New("user is not a group member")
)

type Store interface {
	Create(ctx context.Context, group Group) (Group, error)
	ListByMember(ctx context.Context, uid string) ([]Group, error)
	Leave(ctx context.Context, groupID, uid string) (deleted bool, err error)
}
