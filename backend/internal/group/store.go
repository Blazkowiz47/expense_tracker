package group

import "context"

type Store interface {
	Create(ctx context.Context, group Group) (Group, error)
	ListByMember(ctx context.Context, uid string) ([]Group, error)
}
