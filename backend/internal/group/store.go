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
	ListMembers(ctx context.Context, groupID string) ([]GroupMember, error)
	GetByID(ctx context.Context, id string) (Group, error)
	AddMember(ctx context.Context, groupID, memberUID string) (Group, error)
	Leave(ctx context.Context, groupID, uid string) (deleted bool, err error)
	CreateExpense(ctx context.Context, expense GroupExpense) (GroupExpense, error)
	UpdateExpense(ctx context.Context, expense GroupExpense) (GroupExpense, error)
	ListExpenses(ctx context.Context, groupID string) ([]GroupExpense, error)
}
